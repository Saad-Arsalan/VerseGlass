import AppKit
import Carbon.HIToolbox
import OSLog

/// Register only the system lock chord and only during lyric playback.
@MainActor final class LockShortcut {
    private let log = Logger(subsystem: "local.verseglass.app", category: "lock-shortcut")
    private let identifier = EventHotKeyID(signature: 0x56474C53, id: 1) // VGLS
    private var observers: [NSObjectProtocol] = []
    private var handler: EventHandlerRef?
    private var chord: EventHotKeyRef?
    private var keyCode: UInt32?
    private var wantsChord = false
    private var fallbackRefused = false
    private var keyHeld = false
    private var locking = false
    var availabilityChanged: ((Bool) -> Void)?
    var onLockFailure: (() -> Void)?

    init() {
        let center = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged as String,
                     "com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // The key release can arrive while loginwindow owns the keyboard.
                    if name == "com.apple.screenIsUnlocked" { self.keyHeld = false }
                    _ = self.refreshRegistration()
                }
            })
        }
    }

    deinit {
        if let chord { UnregisterEventHotKey(chord) }
        if let handler { RemoveEventHandler(handler) }
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    @discardableResult
    func configure(enabled: Bool, playbackActive: Bool) -> Bool {
        if !enabled { fallbackRefused = false }
        wantsChord = enabled && playbackActive
        return refreshRegistration()
    }

    private func refreshRegistration() -> Bool {
        let desired: UInt32? = wantsChord && !fallbackRefused && !SaverLauncher.isLocked && NativeSessionLock.isAvailable
            ? Self.commandQKeyCode() : nil
        if desired == keyCode { return chord != nil }

        if let chord { UnregisterEventHotKey(chord) }
        chord = nil
        keyCode = nil
        keyHeld = false
        if let desired, installHandler() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(desired, UInt32(cmdKey | controlKey), identifier,
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref {
                chord = ref
                keyCode = desired
                log.notice("Registered saver-first Control–Command–Q")
            } else {
                log.notice("Lock shortcut registration failed: \(status, privacy: .public)")
            }
        }
        availabilityChanged?(chord != nil)
        return chord != nil
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        let events = [UInt32(kEventHotKeyPressed), UInt32(kEventHotKeyReleased)].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: $0)
        }
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<LockShortcut>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { shortcut.handle(event) }
        }
        return InstallEventHandler(GetApplicationEventTarget(), callback, events.count, events,
                                   Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var received = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout.size(ofValue: received), nil, &received) == noErr,
              received.signature == identifier.signature, received.id == identifier.id else {
            return OSStatus(eventNotHandledErr)
        }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
            keyHeld = false
            return noErr
        }
        guard !keyHeld, !locking else { return noErr }
        keyHeld = true
        guard !SaverLauncher.isLocked else { return noErr }
        locking = true
        let trySaver = wantsChord && chord != nil
        let deadline = DispatchTime.now() + .milliseconds(320)
        log.notice("Received saver-first Control–Command–Q")
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Self.finishLock(trySaverFirst: trySaver, deadline: deadline)
            switch result {
            case .alreadyLocked: log.notice("Saver-first shortcut confirmed native session lock")
            case .requestedLock: log.notice("Saver-first shortcut requested native fallback lock")
            case .lockRequestFailed: log.error("macOS rejected the native fallback lock request")
            }
            DispatchQueue.main.async {
                self.locking = false
                if result == .lockRequestFailed {
                    self.fallbackRefused = true
                    _ = self.refreshRegistration()
                    if !SaverLauncher.isLocked { self.onLockFailure?() }
                }
            }
        }
        return noErr
    }

    enum Outcome { case alreadyLocked, requestedLock, lockRequestFailed }

    // The fallback runs on its own worker even if System Events or the UI stops responding.
    nonisolated static func finishLock(trySaverFirst: Bool, deadline: DispatchTime) -> Outcome {
        if SaverLauncher.isLocked { return .alreadyLocked }
        if trySaverFirst {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? SaverLauncher.sendSelectedSaverRequest(whileLocked: false, before: deadline)
            }
            while DispatchTime.now() < deadline {
                if SaverLauncher.isLocked { return .alreadyLocked }
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
        if SaverLauncher.isLocked { return .alreadyLocked }
        if NativeSessionLock.request() { return .requestedLock }
        if !trySaverFirst {
            _ = try? SaverLauncher.sendSelectedSaverRequest(whileLocked: false, before: .now() + .seconds(1))
        }
        return .lockRequestFailed
    }

    // Resolve Q in the Command layer (including Dvorak–QWERTY and AZERTY).
    private static func commandQKeyCode() -> UInt32? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        defer { withExtendedLifetime(data) {} }
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboard = UInt32(LMGetKbdType())
        var characters = [UniChar](repeating: 0, count: 4)
        for code in UInt16(0)..<128 {
            var state: UInt32 = 0
            var count = 0
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8), keyboard,
                                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &state, characters.count,
                                        &count, &characters)
            if status == noErr && count == 1 && (characters[0] == 0x71 || characters[0] == 0x51) {
                return UInt32(code)
            }
        }
        return nil
    }
}
