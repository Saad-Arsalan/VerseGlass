import AppKit
import Combine
import OSLog
import os.lock

@MainActor final class SaverLauncher {
    private let log = Logger(subsystem: "local.verseglass.app", category: "screen-saver")
    private var subscriptions = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var lastHostActivity: TimeInterval = -.infinity
    private var handlingLock = false
    private var command: Process?
    private static let query = "get running of screen saver preferences"
    private static let launch = "if not (running of screen saver preferences) then start screen saver preferences"
    private nonisolated static let sessionVersion = OSAllocatedUnfairLock(initialState: UInt(0))

    init(engine: Engine, prefs: Preferences) {
        prefs.$startSaverOnLock.removeDuplicates().sink { [weak self] enabled in
            guard let self else { return }
            cancelLockRequests()
            if enabled && !Self.isLocked { run(Self.query, prefs: prefs) }
        }.store(in: &subscriptions)

        prefs.$saverFirstShortcut.removeDuplicates().sink { [weak self] enabled in
            if enabled && !prefs.startSaverOnLock && !Self.isLocked { self?.run(Self.query, prefs: prefs) }
        }.store(in: &subscriptions)

        let center = DistributedNotificationCenter.default()
        center.publisher(for: SaverPacket.hostActive).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                lastHostActivity = ProcessInfo.processInfo.systemUptime
                if handlingLock && prefs.saverMessage != "VerseGlass screen saver is running." {
                    prefs.saverMessage = "VerseGlass screen saver is running."
                    log.notice("Received live VerseGlass screen saver heartbeat during lock")
                }
            }.store(in: &subscriptions)
        center.publisher(for: .init("com.apple.screenIsUnlocked")).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Self.sessionVersion.withLock { $0 &+= 1 }
                guard let self else { return }
                cancelLockRequests()
                if prefs.startSaverOnLock || prefs.saverFirstShortcut { run(Self.query, prefs: prefs) }
            }.store(in: &subscriptions)
        center.publisher(for: .init("com.apple.screenIsLocked")).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Self.sessionVersion.withLock { $0 &+= 1 }
                guard let self, !handlingLock, prefs.startSaverOnLock, prefs.enabled, engine.playing else { return }
                handlingLock = true
                startTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard self.shouldStart(engine, prefs) else { return }
                    // Query the current grant. A launch during a locked session may
                    // never have run the unlocked permission check.
                    let status = await Self.checkLaunchPermission()
                    guard self.shouldStart(engine, prefs) else { return }
                    guard status == noErr else {
                        prefs.saverAutomationReady = false
                        self.log.notice("System Events permission check returned \(status); waiting for system saver fallback")
                        return
                    }
                    prefs.saverAutomationReady = true
                    do {
                        try await Self.requestSelectedSaver()
                        guard self.shouldStart(engine, prefs) else { return }
                        prefs.saverMessage = "Start request sent to macOS."
                        self.log.notice("Requested selected screen saver during lock")
                    } catch {
                        guard self.shouldStart(engine, prefs) else { return }
                        self.log.error("System Events start failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                fallbackTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard self.shouldStart(engine, prefs) else { return }
                    self.startTask?.cancel()
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
                    do {
                        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                        guard self.shouldStart(engine, prefs) else { return }
                        prefs.saverMessage = "Asked macOS to open the screen saver."
                        self.log.notice("Opened system ScreenSaverEngine after no VerseGlass host heartbeat")
                    } catch {
                        guard self.shouldStart(engine, prefs) else { return }
                        prefs.saverMessage = error.localizedDescription
                        self.log.error("Opening system ScreenSaverEngine failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }.store(in: &subscriptions)
    }

    private func cancelLockRequests() {
        startTask?.cancel()
        fallbackTask?.cancel()
        handlingLock = false
    }

    private func shouldStart(_ engine: Engine, _ prefs: Preferences) -> Bool {
        !Task.isCancelled && handlingLock && Self.isLocked && prefs.enabled && prefs.startSaverOnLock
            && engine.playing && ProcessInfo.processInfo.systemUptime - lastHostActivity > 2
    }

    func startFromDesktop(prefs: Preferences) {
        guard !Self.isLocked else { return }
        run(Self.launch, prefs: prefs)
    }

    nonisolated static var isLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    // Public command codes from System Events' Screen Saver scripting suite.
    private nonisolated static let suite: UInt32 = 0x73637376 // scsv
    private nonisolated static let start: UInt32 = 0x73747274 // strt
    private nonisolated static let systemEventsID = "com.apple.systemevents"
    private nonisolated static func checkLaunchPermission() async -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: systemEventsID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, suite, start, false)
    }

    private nonisolated static func requestSelectedSaver() async throws {
        _ = try sendSelectedSaverRequest(whileLocked: true)
    }

    // Called on a worker thread. An Apple event alone does not start System Events.
    nonisolated static func sendSelectedSaverRequest(whileLocked: Bool, before deadline: DispatchTime = .distantFuture) throws -> Bool {
        let generation = sessionVersion.withLock { $0 }
        func isCurrent() -> Bool {
            !Task.isCancelled && DispatchTime.now() < deadline && isLocked == whileLocked
                && (whileLocked || sessionVersion.withLock { $0 == generation })
        }
        guard isCurrent() else { return false }
        if whileLocked || NSRunningApplication.runningApplications(withBundleIdentifier: systemEventsID).contains(where: { !$0.isTerminated }) {
            do { return try sendStartEvent(before: deadline, isCurrent: isCurrent) }
            catch let error as NSError {
                // A previously running System Events can exit between lookup and delivery.
                guard !whileLocked, error.domain == NSOSStatusErrorDomain,
                      error.code == Int(procNotFound) || error.code == Int(connectionInvalid) else { throw error }
            }
        }
        guard isCurrent() else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        let launchFinished = DispatchSemaphore(value: 0)
        let launched = OSAllocatedUnfairLock(initialState: false)
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            launched.withLock { $0 = app != nil && error == nil }
            launchFinished.signal()
        }
        // The callback only wakes this worker. A late callback cannot start a saver.
        let launchDeadline = min(deadline, .now() + .seconds(5))
        guard launchFinished.wait(timeout: launchDeadline) == .success, launched.withLock({ $0 }) else { return false }
        return try sendStartEvent(before: deadline, isCurrent: isCurrent)
    }

    private nonisolated static func sendStartEvent(before deadline: DispatchTime, isCurrent: () -> Bool) throws -> Bool {
        let object = NSAppleEventDescriptor.record()
        object.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: UInt32(keyAEDesiredClass))
        object.setDescriptor(NSAppleEventDescriptor(enumCode: UInt32(formPropertyID)), forKeyword: UInt32(keyAEKeyForm))
        object.setDescriptor(NSAppleEventDescriptor(typeCode: 0x73737670), forKeyword: UInt32(keyAEKeyData)) // ssvp
        object.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: UInt32(keyAEContainer))
        guard let preferences = object.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw CocoaError(.coderInvalidValue)
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: systemEventsID)
        let event = NSAppleEventDescriptor(eventClass: suite, eventID: start, targetDescriptor: target,
                                           returnID: -1, transactionID: 0)
        event.setParam(preferences, forKeyword: keyDirectObject)
        guard isCurrent() else { return false }
        let now = DispatchTime.now()
        guard now < deadline else { return false }
        let timeout = min(5.0, Double(deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000_000)
        let quiet = NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent))
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, quiet], timeout: timeout)
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return true
    }

    private func run(_ action: String, prefs: Preferences) {
        if let existing = command, existing.isRunning {
            guard action == Self.launch else { return }
            existing.terminate()
        }
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"com.apple.systemevents\"\nwith timeout of 5 seconds\n\(action)\nend timeout\nend tell"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.terminationHandler = { [weak self] task in
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                guard let self, self.command === task else { return }
                self.command = nil
                guard !Self.isLocked else { return }
                if task.terminationStatus == 0 {
                    prefs.saverAutomationReady = true
                    prefs.saverMessage = action == Self.query ? "System Events is ready." : "Start request sent to macOS."
                    self.log.info("System Events command completed: \(action, privacy: .public)")
                } else {
                    prefs.saverMessage = message
                    if action == Self.query || message.contains("-1743") { prefs.saverAutomationReady = false }
                    self.log.error("Screen saver command failed: \(message, privacy: .public)")
                }
            }
        }
        do { try process.run(); command = process }
        catch { prefs.saverMessage = error.localizedDescription }
    }
}
