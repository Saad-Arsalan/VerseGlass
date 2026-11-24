import AppKit
import Combine
import OSLog

@MainActor final class SaverLauncher {
    private let log = Logger(subsystem:"local.verseglass.app", category:"screen-saver")
    private var subscriptions = Set<AnyCancellable>()
    private var pending: Task<Void,Never>?
    private var command: Process?
    private static let query = "get running of screen saver preferences"
    private static let launch = "if not (running of screen saver preferences) then start screen saver preferences"

    init(engine: Engine, prefs: Preferences) {
        prefs.$startSaverOnLock.removeDuplicates().sink { [weak self] enabled in
            guard let self else { return }
            pending?.cancel()
            if enabled && !Self.isLocked { run(Self.query, prefs:prefs) }
        }.store(in:&subscriptions)
        let notifications = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked",true),("com.apple.screenIsUnlocked",false)] {
            notifications.publisher(for:.init(name)).receive(on:DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                pending?.cancel()
                guard locked, prefs.startSaverOnLock, prefs.enabled, engine.playing else { return }
                pending = Task {
                    try? await Task.sleep(for:.milliseconds(400))
                    guard !Task.isCancelled, Self.isLocked, engine.playing, prefs.startSaverOnLock, prefs.enabled else { return }
                    guard prefs.saverAutomationReady else { self.log.notice("Skipped screen saver start while Automation permission is pending"); return }
                    self.run(Self.launch, prefs:prefs)
                }
            }.store(in:&subscriptions)
        }
    }
    func startFromDesktop(prefs:Preferences) {
        guard !Self.isLocked else { return }
        run(Self.launch, prefs:prefs)
    }

    private static var isLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String:Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
    private func run(_ action:String, prefs:Preferences) {
        guard command?.isRunning != true else { return }
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/osascript")
        process.arguments = ["-e","tell application id \"com.apple.systemevents\"\nwith timeout of 5 seconds\n\(action)\nend timeout\nend tell"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.terminationHandler = { [weak self] task in
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            Task { @MainActor in
                guard let self else { return }
                if task.terminationStatus == 0 {
                    prefs.saverAutomationReady = true
                    prefs.saverMessage = action == Self.query ? "System Events is ready." : "Start request sent to macOS."
                    self.log.info("System Events command completed: \(action, privacy:.public)")
                } else {
                    prefs.saverMessage = message
                    if action == Self.query || message.contains("-1743") { prefs.saverAutomationReady = false }
                    self.log.error("Screen saver command failed: \(message, privacy:.public)")
                }
            }
        }
        do { try process.run(); command=process }
        catch { prefs.saverMessage=error.localizedDescription }
    }
}
