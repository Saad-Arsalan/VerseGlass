import AppKit
import SwiftUI
import Combine

@MainActor final class RimPanels {
    private var panels: [String:NSPanel] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var locked = false
    func start() {
        let light = RoomLighting.shared
        if let session = CGSessionCopyCurrentDictionary() as? [String:Any] { locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false }
        Publishers.CombineLatest3(light.$enabled, light.$isRunning, light.$displayID).receive(on:DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }.store(in:&subscriptions)
        for (name,state) in [("com.apple.screenIsLocked",true),("com.apple.screenIsUnlocked",false)] {
            DistributedNotificationCenter.default().publisher(for:.init(name)).receive(on:DispatchQueue.main)
                .sink { [weak self] _ in self?.locked=state; self?.sync() }.store(in:&subscriptions)
        }
        NotificationCenter.default.publisher(for:NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.sync() }.store(in:&subscriptions)
    }
    func stop() {
        subscriptions.removeAll()
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }
    private func sync() {
        let light=RoomLighting.shared
        var desired=Set<String>()
        if light.enabled && light.isRunning && !locked {
            for screen in NSScreen.screens where light.displayID=="all" || light.displayID==screen.verseID {
                let id=screen.verseID
                desired.insert(id)
                if let panel=panels[id] { panel.setFrame(screen.frame,display:false); continue }
                let panel=NSPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                panel.isReleasedWhenClosed=false
                panel.backgroundColor = .clear
                panel.isOpaque=false
                panel.hasShadow=false
                panel.ignoresMouseEvents=true
                panel.hidesOnDeactivate=false
                panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
                panel.level = .floating
                panel.contentView=NSHostingView(rootView:RimGlow().allowsHitTesting(false).accessibilityHidden(true))
                panel.setFrame(screen.frame,display:false)
                panels[id]=panel
                panel.orderFrontRegardless()
            }
        }
        for id in Set(panels.keys).subtracting(desired) { panels.removeValue(forKey:id)?.close() }
    }
}
