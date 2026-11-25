import Foundation

// Compile with LockShortcut.swift in place of the production lock and saver backends.
// No key is registered, no Apple event is sent, and no session lock is requested.
private final class Simulation {
    enum SaverBehavior { case lock, refuse, hang }

    let behavior: SaverBehavior
    let acceptsLock: Bool
    let releaseSaver = DispatchSemaphore(value: 0)
    let saverFinished = DispatchSemaphore(value: 0)
    let mutex = NSLock()
    var locked: Bool
    var saverCalls = 0
    var lockCalls = 0

    init(behavior: SaverBehavior, locked: Bool, acceptsLock: Bool) {
        self.behavior = behavior
        self.locked = locked
        self.acceptsLock = acceptsLock
    }
}

private var simulation = Simulation(behavior: .refuse, locked: false, acceptsLock: true)

enum SaverLauncher {
    static var isLocked: Bool { simulation.mutex.withLock { simulation.locked } }

    static func sendSelectedSaverRequest(whileLocked: Bool, before: DispatchTime) throws -> Bool {
        let run = simulation
        precondition(!whileLocked)
        run.mutex.withLock {
            run.saverCalls += 1
            if run.behavior == .lock { run.locked = true }
        }
        if run.behavior == .hang { _ = run.releaseSaver.wait(timeout: .now() + .seconds(5)) }
        run.saverFinished.signal()
        return run.behavior == .lock
    }
}

enum NativeSessionLock {
    static var isAvailable: Bool { true }
    static func request() -> Bool {
        simulation.mutex.withLock { simulation.lockCalls += 1 }
        return simulation.acceptsLock
    }
}

@main struct TestLockShortcutFallback {
    static func main() {
        check("saver locked", .lock, outcome: .alreadyLocked, saverCalls: 1, lockCalls: 0)
        check("already locked", .refuse, locked: true, outcome: .alreadyLocked, saverCalls: 0, lockCalls: 0)
        check("saver stalled", .hang, outcome: .requestedLock, saverCalls: 1, lockCalls: 1)
        check("saver refused", .refuse, outcome: .requestedLock, saverCalls: 1, lockCalls: 1)
        check("playback stopped", .refuse, trySaver: false, outcome: .requestedLock, saverCalls: 0, lockCalls: 1)
        check("both refused", .refuse, acceptsLock: false, outcome: .lockRequestFailed, saverCalls: 1, lockCalls: 1)
        check("playback stopped and lock refused", .refuse, trySaver: false, acceptsLock: false,
              outcome: .lockRequestFailed, saverCalls: 1, lockCalls: 1)
    }

    private static func check(_ name: String, _ behavior: Simulation.SaverBehavior, trySaver: Bool = true,
                              locked: Bool = false, acceptsLock: Bool = true, outcome: LockShortcut.Outcome,
                              saverCalls: Int, lockCalls: Int) {
        let run = Simulation(behavior: behavior, locked: locked, acceptsLock: acceptsLock)
        simulation = run
        let begin = DispatchTime.now()
        let result = LockShortcut.finishLock(trySaverFirst: trySaver, deadline: begin + .milliseconds(300))
        let elapsed = DispatchTime.now().uptimeNanoseconds - begin.uptimeNanoseconds
        run.releaseSaver.signal()
        if saverCalls > 0 { precondition(run.saverFinished.wait(timeout: .now() + .seconds(2)) == .success, name) }
        precondition(elapsed < 3_000_000_000, "A blocked saver delayed the fallback: \(name)")
        precondition(result == outcome && run.saverCalls == saverCalls && run.lockCalls == lockCalls, name)
        print("Passed", name)
    }
}
