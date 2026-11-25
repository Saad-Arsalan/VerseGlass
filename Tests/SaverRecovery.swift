import Combine
import Foundation

// The tests drive the recovery sequence directly. No saver, keyboard shortcut,
// Apple event or lock notification is used.
final class Preferences {
    @Published var startSaverOnLock = false
    @Published var saverFirstShortcut = false
    let enabled = true
    var saverAutomationReady = false
    var saverMessage = ""
}

final class Engine { let playing = true }
enum SaverPacket { static let hostActive = Notification.Name("test.saver.heartbeat") }

@main struct TestSaverRecovery {
    @MainActor static func main() async {
        var session = SaverLauncher.Session()
        let first = DispatchTime.now() + .seconds(2)
        let second = first + .seconds(1)
        let oldGeneration = session.generation
        precondition(session.recordStart(generation: oldGeneration, expires: first))
        precondition(session.hasShortcutStart(at: .now()) && !session.hasShortcutStart(at: first))
        session.refuseStart(expires: first)
        precondition(!session.hasShortcutStart(at: .now()))
        session.unlock()
        precondition(!session.recordStart(generation: oldGeneration, expires: first))
        precondition(session.recordStart(generation: session.generation, expires: second))
        session.refuseStart(expires: first)
        precondition(session.hasShortcutStart(at: .now()))
        session.unlock()
        precondition(!session.hasShortcutStart(at: .now()))

        await check("shortcut host starts cold", shortcut: true, reports: [true],
                    actions: ["query"], checksAt: [.milliseconds(400), .seconds(3), .seconds(6)])
        await check("shortcut heartbeat arrives during startup", shortcut: true, reports: [], endAtWait: 2,
                    actions: [], checksAt: [.milliseconds(400), .seconds(3)])
        await check("shortcut with no heartbeat and unreadable status", shortcut: true, reports: [nil],
                    actions: ["query", "engine"], checksAt: [.milliseconds(400), .seconds(3), .seconds(6)])
        await check("shortcut refusal arrives during cold start", shortcut: true, reports: [false, true], refusedDuringGrace: true,
                    actions: ["query", "start", "query"], checksAt: [.milliseconds(400), .seconds(3), .seconds(6)])
        await check("external lock with an active saver", shortcut: false, reports: [true, true],
                    actions: ["query", "query"], checksAt: [.milliseconds(400), .seconds(3)])
        await check("external saver exits before its first heartbeat", shortcut: false, reports: [true, false],
                    actions: ["query", "query", "engine"], checksAt: [.milliseconds(400), .seconds(3)])
        await check("external lock or refused shortcut starts the saver", shortcut: false, reports: [false, true],
                    actions: ["query", "start", "query"], checksAt: [.milliseconds(400), .seconds(3)])
        await check("external lock still gets one fallback", shortcut: false, reports: [nil, false],
                    actions: ["query", "start", "query", "engine"], checksAt: [.milliseconds(400), .seconds(3)])
        await check("unlock during initial query", shortcut: false, reports: [false], endAtQuery: 1,
                    actions: ["query"], checksAt: [.milliseconds(400)])
        await check("unlock during fallback query", shortcut: true, reports: [nil], endAtQuery: 1,
                    actions: ["query"], checksAt: [.milliseconds(400), .seconds(3), .seconds(6)])
    }

    @MainActor private static func check(_ name: String, shortcut: Bool, reports: [Bool?],
                                         refusedDuringGrace: Bool = false,
                                         endAtWait: Int? = nil, endAtQuery: Int? = nil,
                                         actions expected: [String], checksAt: [Duration]) async {
        var current = true
        var waits: [Duration] = []
        var actions: [String] = []
        var queries = 0
        await SaverLauncher.recover(shortcutStarted: { shortcut && !(refusedDuringGrace && waits.count > 1) },
                                    isCurrent: { current }, waitUntil: { delay in
            waits.append(delay)
            if waits.count == endAtWait { throw CancellationError() }
        }, running: {
            precondition(queries < reports.count, name)
            let report = reports[queries]
            queries += 1
            actions.append("query")
            if queries == endAtQuery { current = false }
            return report
        }, start: { actions.append("start") }, openEngine: { actions.append("engine") })
        precondition(waits == checksAt && actions == expected && queries == reports.count, name)
        print("Passed", name)
    }
}
