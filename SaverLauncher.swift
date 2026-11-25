import AppKit
import Combine
import OSLog
import os.lock

@MainActor final class SaverLauncher {
    private let log = Logger(subsystem: "local.verseglass.app", category: "screen-saver")
    private var subscriptions = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?
    private var lastHostActivity: TimeInterval = -.infinity
    private var handlingLock = false
    private var command: Process?
    private static let query = "get running of screen saver preferences"
    private static let launch = "if not (running of screen saver preferences) then start screen saver preferences"
    // A shortcut start may be accepted before the saver sends its first heartbeat.
    // The ticket belongs to one unlock generation, including the subsequent lock.
    struct Session {
        private(set) var generation: UInt = 0
        private var shortcutExpiry: DispatchTime?

        mutating func unlock() {
            generation &+= 1
            shortcutExpiry = nil
        }

        mutating func recordStart(generation expected: UInt, expires: DispatchTime) -> Bool {
            guard expected == generation else { return false }
            shortcutExpiry = expires
            return true
        }

        mutating func refuseStart(expires: DispatchTime) {
            if shortcutExpiry == expires { shortcutExpiry = nil }
        }

        func hasShortcutStart(at now: DispatchTime) -> Bool {
            shortcutExpiry.map { now < $0 } ?? false
        }
    }
    private nonisolated static let session = OSAllocatedUnfairLock(initialState: Session())

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
                if handlingLock { startTask?.cancel() }
                if handlingLock && prefs.saverMessage != "VerseGlass screen saver is running." {
                    prefs.saverMessage = "VerseGlass screen saver is running."
                    log.notice("Received live VerseGlass screen saver heartbeat during lock")
                }
            }.store(in: &subscriptions)
        center.publisher(for: .init("com.apple.screenIsUnlocked")).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Self.session.withLock { $0.unlock() }
                guard let self else { return }
                lastHostActivity = -.infinity
                cancelLockRequests()
                if prefs.startSaverOnLock || prefs.saverFirstShortcut { run(Self.query, prefs: prefs) }
            }.store(in: &subscriptions)
        center.publisher(for: .init("com.apple.screenIsLocked")).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !handlingLock, prefs.startSaverOnLock, prefs.enabled, engine.playing else { return }
                handlingLock = true
                let lockedAt = ContinuousClock.now
                startTask = Task {
                    await Self.recover(
                        shortcutStarted: { Self.session.withLock { $0.hasShortcutStart(at: .now()) } },
                        isCurrent: { self.shouldStart(engine, prefs) },
                        waitUntil: { try await Task.sleep(until: lockedAt + $0, clock: .continuous) },
                        running: Self.saverIsRunning,
                        start: { await self.startDuringLock(engine, prefs) },
                        openEngine: { await self.openEngineDuringLock(engine, prefs) }
                    )
                }
            }.store(in: &subscriptions)
    }

    // Give a shortcut-started saver time to load. An external lock still gets the
    // usual early start and one rescue if neither macOS nor the saver confirms it.
    static func recover(shortcutStarted: () -> Bool, isCurrent: () -> Bool,
                        waitUntil: (Duration) async throws -> Void, running: () async -> Bool?,
                        start: () async -> Void, openEngine: () async -> Void) async {
        do {
            try await waitUntil(.milliseconds(400))
            guard isCurrent() else { return }
            let coldStart = shortcutStarted()
            if coldStart {
                try await waitUntil(.seconds(3))
                guard isCurrent() else { return }
            }
            if !coldStart || !shortcutStarted() {
                let alreadyRunning = await running()
                guard isCurrent() else { return }
                if alreadyRunning != true { await start() }
            }
            try await waitUntil(coldStart ? .seconds(6) : .seconds(3))
            guard isCurrent() else { return }
            let alreadyRunning = await running()
            guard isCurrent(), alreadyRunning != true else { return }
            await openEngine()
        } catch { return } // The lock ended or the saver sent its heartbeat.
    }

    private func startDuringLock(_ engine: Engine, _ prefs: Preferences) async {
        do {
            let sent = try await Self.requestSelectedSaver()
            guard sent, shouldStart(engine, prefs) else { return }
            prefs.saverAutomationReady = true
            prefs.saverMessage = "Start request sent to macOS."
            log.notice("Requested selected screen saver during lock")
        } catch {
            guard shouldStart(engine, prefs) else { return }
            let failure = error as NSError
            if failure.domain == NSOSStatusErrorDomain && (failure.code == Int(errAEEventNotPermitted) || failure.code == Int(errAEEventWouldRequireUserConsent)) {
                prefs.saverAutomationReady = false
            }
            log.error("System Events start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func openEngineDuringLock(_ engine: Engine, _ prefs: Preferences) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            guard shouldStart(engine, prefs) else { return }
            prefs.saverMessage = "Asked macOS to open the screen saver."
            log.notice("Opened system ScreenSaverEngine after no VerseGlass host heartbeat")
        } catch {
            guard shouldStart(engine, prefs) else { return }
            prefs.saverMessage = error.localizedDescription
            log.error("Opening system ScreenSaverEngine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cancelLockRequests() {
        startTask?.cancel()
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
    private nonisolated static func saverIsRunning() async -> Bool? {
        // System Events' "running of screen saver preferences" is core/getd on runn of ssvp.
        guard let preferences = try? property(0x73737670),
              let running = try? property(0x72756e6e, of: preferences),
              let reply = try? sendEvent(eventClass: UInt32(kAECoreSuite), id: UInt32(kAEGetData), object: running,
                                         before: .now() + .milliseconds(650)),
              let value = reply.paramDescriptor(forKeyword: UInt32(keyDirectObject))?.coerce(toDescriptorType: typeBoolean)
        else { return nil }
        return value.booleanValue
    }

    private nonisolated static func requestSelectedSaver() async throws -> Bool {
        try sendSelectedSaverRequest(whileLocked: true, before: .now() + .seconds(1))
    }

    // Called on a worker thread. An Apple event alone does not start System Events.
    nonisolated static func sendSelectedSaverRequest(whileLocked: Bool, before deadline: DispatchTime = .distantFuture) throws -> Bool {
        let generation = session.withLock { $0.generation }
        func isCurrent() -> Bool {
            !Task.isCancelled && DispatchTime.now() < deadline && isLocked == whileLocked
                && session.withLock { $0.generation == generation }
        }
        guard isCurrent() else { return false }
        if whileLocked || NSRunningApplication.runningApplications(withBundleIdentifier: systemEventsID).contains(where: { !$0.isTerminated }) {
            do { return try sendStartEvent(whileLocked: whileLocked, generation: generation, before: deadline, isCurrent: isCurrent) }
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
        return try sendStartEvent(whileLocked: whileLocked, generation: generation, before: deadline, isCurrent: isCurrent)
    }

    private nonisolated static func property(_ code: UInt32, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let object = NSAppleEventDescriptor.record()
        object.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: UInt32(keyAEDesiredClass))
        object.setDescriptor(NSAppleEventDescriptor(enumCode: UInt32(formPropertyID)), forKeyword: UInt32(keyAEKeyForm))
        object.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: UInt32(keyAEKeyData))
        object.setDescriptor(container, forKeyword: UInt32(keyAEContainer))
        guard let specifier = object.coerce(toDescriptorType: typeObjectSpecifier) else { throw CocoaError(.coderInvalidValue) }
        return specifier
    }

    private nonisolated static func sendStartEvent(whileLocked: Bool, generation: UInt, before deadline: DispatchTime,
                                                  isCurrent: () -> Bool) throws -> Bool {
        let preferences = try property(0x73737670) // ssvp
        guard isCurrent() else { return false }
        let expires = DispatchTime.now() + .seconds(6)
        if !whileLocked, !session.withLock({ $0.recordStart(generation: generation, expires: expires) }) { return false }
        do {
            _ = try sendEvent(eventClass: suite, id: start, object: preferences, before: deadline)
            return true
        } catch {
            // A reply timeout leaves delivery unknown. Keep its ticket while the host starts.
            let failure = error as NSError
            if !whileLocked && !(failure.domain == NSOSStatusErrorDomain && failure.code == Int(errAETimeout)) {
                session.withLock { $0.refuseStart(expires: expires) }
            }
            throw error
        }
    }

    private nonisolated static func sendEvent(eventClass: UInt32, id: UInt32, object: NSAppleEventDescriptor,
                                             before deadline: DispatchTime) throws -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(bundleIdentifier: systemEventsID)
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: id, targetDescriptor: target,
                                           returnID: -1, transactionID: 0)
        event.setParam(object, forKeyword: keyDirectObject)
        let now = DispatchTime.now()
        guard now < deadline else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAETimeout)) }
        let timeout = min(5.0, Double(deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000_000)
        let quiet = NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent))
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, quiet], timeout: timeout)
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return reply
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
