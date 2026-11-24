import AppKit
import Combine
import CoreGraphics
import IOKit.pwr_mgt
import SwiftUI

private final class LyricPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct OverlayContent: View {
    @ObservedObject var engine: Engine
    @ObservedObject var prefs: Preferences

    var body: some View {
        LyricScene(frame: engine.frame, style: prefs.style, size: CGFloat(prefs.textSize),
                   fontName: prefs.fontName, accent: prefs.effectiveAccent)
            .environment(\.lyricPrimary, Color(hex: prefs.primaryHex))
            .environment(\.lyricSecondary, Color(hex: prefs.secondaryHex))
            .preferredColorScheme(.dark)
            .shadow(color: .black.opacity(0.65), radius: 4, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@MainActor
final class OverlayManager {
    private let engine: Engine
    private let prefs: Preferences
    private let lockLyrics: LockLyrics
    private var panels: [CGDirectDisplayID: LyricPanel] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var locked = false
    private var screensAsleep = false
    private var assertion: IOPMAssertionID?

    init(engine: Engine, prefs: Preferences, lockLyrics: LockLyrics) {
        self.engine = engine
        self.prefs = prefs
        self.lockLyrics = lockLyrics
    }

    func start() {
        guard subscriptions.isEmpty else { return }

        // Frame updates are frequent. Window management only needs to run at
        // the beginning/end of lyrics, on playback changes and on configuration.
        let hasLyrics = engine.$frame.map { $0.lines.indices.contains($0.lineIndex) }.removeDuplicates()
        let playback = Publishers.CombineLatest(hasLyrics, engine.$playing.removeDuplicates()).map { _ in () }
        let visibility = Publishers.CombineLatest4(prefs.$enabled, prefs.$showUnlocked,
                                                   prefs.$displayID, prefs.$keepAwake).map { _ in () }
        playback.merge(with: visibility).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }.store(in: &subscriptions)

        engine.$frame.map(Self.currentLine).removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshNotification() }.store(in: &subscriptions)
        prefs.$lockNotifications.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled { self?.lockLyrics.authorize() }
                self?.refreshNotification()
            }.store(in: &subscriptions)

        let distributed = DistributedNotificationCenter.default()
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributed.publisher(for: Notification.Name(name)).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.locked = value
                    self?.refresh()
                }.store(in: &subscriptions)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.screensAsleep = true
                self?.refresh()
            }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.screensAsleep = false
                self?.resync()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        // Recover if the session changes during launch or a notification is
        // missed over system sleep. The key is present only while locked.
        Timer.publish(every: 8, tolerance: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.resync() }.store(in: &subscriptions)
        resync()
    }

    func stop() {
        subscriptions.removeAll()
        lockLyrics.stop()
        for panel in panels.values { panel.close() }
        panels.removeAll()
        updatePowerAssertion(needed: false)
    }

    private func resync() {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
        refresh()
    }

    private static func currentLine(_ frame: LyricFrame) -> LockLine? {
        guard frame.lines.indices.contains(frame.lineIndex) else { return nil }
        let text = frame.lines[frame.lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return LockLine(title: frame.title, artist: frame.artist, index: frame.lineIndex, text: text)
    }

    private func refreshNotification() {
        let visible = locked && !screensAsleep && prefs.enabled && prefs.lockNotifications && engine.playing
        lockLyrics.update(visible ? Self.currentLine(engine.frame) : nil)
    }

    private func refresh() {
        refreshNotification()
        updatePowerAssertion(needed: prefs.keepAwake && engine.playing)
        let frame = engine.frame
        let shouldShow = prefs.enabled && engine.playing && !locked && prefs.showUnlocked
            && !screensAsleep && frame.lines.indices.contains(frame.lineIndex)
        let selected = Set(prefs.displayID.split(separator: ",").compactMap { UInt32($0) })
        var required = Set<CGDirectDisplayID>()
        if shouldShow {
            for screen in NSScreen.screens {
                guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                      prefs.displayID == "all" || selected.contains(id)
                        || (prefs.displayID == "main" && id == CGMainDisplayID()) else { continue }
                required.insert(id)
                show(on: screen, displayID: id)
            }
        }
        for id in Set(panels.keys).subtracting(required) {
            panels.removeValue(forKey: id)?.close()
        }
    }

    private func show(on screen: NSScreen, displayID: CGDirectDisplayID) {
        let bounds = screen.frame
        let width = min(bounds.width * 0.88, 1200)
        let height = bounds.height * 0.54
        let rect = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                          width: width, height: height).integral
        let panel: LyricPanel
        if let existing = panels[displayID] {
            panel = existing
        } else {
            panel = LyricPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: OverlayContent(engine: engine, prefs: prefs))
            panels[displayID] = panel
        }

        let level = NSWindow.Level.floating
        let needsOrdering = !panel.isVisible || panel.level != level
        if panel.level != level { panel.level = level }
        if panel.frame != rect { panel.setFrame(rect, display: true) }
        if needsOrdering { panel.orderFrontRegardless() }
    }

    private func updatePowerAssertion(needed: Bool) {
        if needed, assertion == nil {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Showing lyrics during music playback" as CFString, &id)
            if result == kIOReturnSuccess { assertion = id }
        } else if !needed, let id = assertion {
            IOPMAssertionRelease(id)
            assertion = nil
        }
    }
}
