import AppKit
import OSLog

/// On an enabled, unlocked Mac, give the selected system saver a brief chance
/// to acquire the real session lock before macOS handles the lock shortcut.
@MainActor final class LockShortcut {
    private let log = Logger(subsystem: "local.verseglass.app", category: "lock-shortcut")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var playbackActive = false
    private var reportedAccessFailure = false

    @discardableResult
    func configure(enabled: Bool, playbackActive: Bool) -> Bool {
        self.playbackActive = playbackActive
        guard enabled, AXIsProcessTrusted() else {
            if enabled && !reportedAccessFailure {
                log.notice("Lock shortcut unavailable: Accessibility access has not been granted")
            }
            reportedAccessFailure = enabled
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            if let tap { CFMachPortInvalidate(tap) }
            source = nil
            tap = nil
            return false
        }
        reportedAccessFailure = false
        if let tap { return CGEvent.tapIsEnabled(tap: tap) }
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let shortcut = Unmanaged<LockShortcut>.fromOpaque(pointer).takeUnretainedValue()
            return MainActor.assumeIsolated { shortcut.handle(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            log.notice("Lock shortcut unavailable: macOS did not create an event tap")
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let active = CGEvent.tapIsEnabled(tap: tap)
        log.notice("Lock shortcut tap active: \(active, privacy: .public)")
        return active
    }

    deinit {
        if let tap { CFMachPortInvalidate(tap) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let original = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        guard type == .keyDown, playbackActive,
              LockShortcutDecision.matches(flags: event.flags, repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                           character: NSEvent(cgEvent: event)?.charactersIgnoringModifiers),
              !SaverLauncher.isLocked else { return original }

        let deadline = DispatchTime.now() + .milliseconds(150)
        let accepted = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            if (try? SaverLauncher.sendSelectedSaverRequest(whileLocked: false, before: deadline)) == true {
                accepted.signal()
            }
        }
        // A successful saver start can leave the desktop unlocked during the
        // user's password grace period. Only an OS-reported lock is sufficient.
        let confirmed = LockShortcutDecision.confirmed(before: deadline, accepted: accepted,
                                                        isLocked: { SaverLauncher.isLocked })
        if confirmed {
            log.notice("Lock shortcut: system saver start acknowledged and session lock confirmed")
            return nil
        }
        log.notice("Lock shortcut: passed original event to macOS")
        return original
    }
}

enum LockShortcutDecision {
    static func matches(flags: CGEventFlags, repeating: Bool, character: @autoclosure () -> String?) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]
        return !repeating && flags.intersection(modifiers) == [.maskCommand, .maskControl] && character()?.lowercased() == "q"
    }

    static func confirmed(before deadline: DispatchTime, accepted: DispatchSemaphore, isLocked: () -> Bool) -> Bool {
        guard accepted.wait(timeout: deadline) == .success else { return false }
        while DispatchTime.now() < deadline {
            if isLocked() { return DispatchTime.now() < deadline }
            Thread.sleep(forTimeInterval: 0.004)
        }
        return false
    }
}
