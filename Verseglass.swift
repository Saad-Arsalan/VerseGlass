import SwiftUI
import AppKit
import OSLog
import CoreImage
import ImageIO
import Combine

@main
@MainActor struct Verseglass {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let prefs = Preferences()
    private let engine = Engine()
    private let lockLyrics = LockLyrics()
    private let rims = RimPanels()
    private var feed: SaverFeed?
    private var audioState: AnyCancellable?
    private let lockShortcut = LockShortcut()
    private var shortcutState: AnyCancellable?
    private var saverLauncher: SaverLauncher?
    private var overlay: OverlayManager!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var listeningWindow: NSWindow?
    private var artworkSubscription: AnyCancellable?
    private var artworkTask: Task<Void,Never>?
    func applicationDidFinishLaunching(_ notification:Notification) {
        appMenu()
        overlay = OverlayManager(engine:engine,prefs:prefs,lockLyrics:lockLyrics)
        overlay.start()
        rims.start()
        feed = SaverFeed(engine:engine,prefs:prefs)
        audioState = engine.$playing.removeDuplicates().sink { RoomLighting.shared.setPlaying($0) }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        let image = VerseglassMark.menuBarImage()
        statusItem.button?.image=image
        statusItem.button?.toolTip="Verseglass lyrics"
        let menu = NSMenu()
        menu.delegate=self
        statusItem.menu=menu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:690),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="Verseglass"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent=true
        window.isMovableByWindowBackground=true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named:.darkAqua)
        window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:Studio(prefs:prefs,engine:engine,lockLyrics:lockLyrics).ignoresSafeArea())
        window.delegate=self
        window.center()
        window.setFrameAutosaveName("VerseglassStudio")
        artworkSubscription = Publishers.CombineLatest3(engine.$artworkURL,prefs.$matchArtwork,engine.$onlineLookup)
            .removeDuplicates { a,b in a.0 == b.0 && a.1 == b.1 && a.2 == b.2 }
            .sink { [weak self] url, _, online in
                self?.loadArtwork((online || url?.isFileURL == true) ? url : nil)
            }
        openWindow()
        saverLauncher = SaverLauncher(engine:engine,prefs:prefs)
        shortcutState = Publishers.CombineLatest3(prefs.$saverFirstShortcut, prefs.$enabled, engine.$playing)
            .removeDuplicates { a, b in a.0 == b.0 && a.1 == b.1 && a.2 == b.2 }
            .sink { [weak self] enabled, lyricsEnabled, playing in
                guard let self else { return }
                let available = lockShortcut.configure(enabled: enabled, playbackActive: lyricsEnabled && playing)
                prefs.shortcutAvailable = available
                if enabled {
                    Logger(subsystem: "local.verseglass.app", category: "lock-shortcut")
                        .notice("Saver-first shortcut available: \(available, privacy: .public)")
                }
            }
        engine.start()
    }
    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        prefs.listeningCover=nil
        prefs.artworkAccent=nil
        prefs.artworkThumbnail=nil
        RoomLighting.shared.clearPalette()
        guard let url else { return }
        artworkTask=Task {
            do {
                let data:Data
                if url.isFileURL { data = try Data(contentsOf:url) }
                else { data = try await URLSession.shared.data(from:url).0 }
                try Task.checkCancellation()
                guard let art=CIImage(data:data) else { return }
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    func thumbnail(maxPixels: Int) -> CGImage? {
                        CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixels
                        ] as CFDictionary)
                    }
                    if let cover = thumbnail(maxPixels: 1024) {
                        prefs.listeningCover = NSImage(cgImage: cover, size: .zero)
                    }
                    if let small = thumbnail(maxPixels: 96) {
                        prefs.artworkThumbnail = NSBitmapImageRep(cgImage: small)
                            .representation(using: .jpeg, properties: [.compressionFactor: 0.65])
                    }
                }
                let mean=art.applyingFilter("CIAreaAverage",parameters:[kCIInputExtentKey:CIVector(cgRect:art.extent)]).cropped(to:CGRect(x:0,y:0,width:1,height:1))
                var pixel=[UInt8](repeating:0,count:4)
                CIContext().render(mean,toBitmap:&pixel,rowBytes:4,bounds:mean.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
                let c=NSColor(srgbRed:CGFloat(pixel[0])/255,green:CGFloat(pixel[1])/255,blue:CGFloat(pixel[2])/255,alpha:1)
                let sampled = Color(hue:c.hueComponent,saturation:max(0.28,c.saturationComponent),brightness:max(0.82,c.brightnessComponent))
                prefs.artworkAccent=sampled
                RoomLighting.shared.setPalette(sampled)
            } catch { }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { overlay?.stop(); rims.stop(); RoomLighting.shared.stop() }
    private func appMenu() {
        let menu=NSMenu()
        let root=menu.addItem(withTitle:"Verseglass",action:nil,keyEquivalent:"")
        let app=NSMenu()
        app.addItem(withTitle:"Hide Verseglass",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        app.addItem(withTitle:"Quit Verseglass",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        root.submenu=app
        let windowMenu=menu.addItem(withTitle:"Window",action:nil,keyEquivalent:"")
        let commands=NSMenu()
        commands.addItem(withTitle:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        windowMenu.submenu=commands
        NSApp.mainMenu=menu
    }
    @objc private func openWindow() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { openWindow(); return true }
    @objc private func openListeningView() {
        let listening: NSWindow
        if let existing = listeningWindow {
            listening = existing
        } else {
            listening = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
            listening.title = "Listening View"
            listening.appearance = NSAppearance(named: .darkAqua)
            listening.collectionBehavior = [.fullScreenPrimary]
            listening.contentMinSize = NSSize(width: 430, height: 290)
            listening.isReleasedWhenClosed = false
            listening.contentView = NSHostingView(rootView: ListeningView(engine: engine, prefs: prefs) { [weak listening] in
                listening?.performClose(nil)
            })
            listening.delegate = self
            listening.center()
            listening.setFrameAutosaveName("VerseGlassListening")
            listeningWindow = listening
        }
        NSApp.setActivationPolicy(.regular)
        if listening.isMiniaturized { listening.deminiaturize(nil) }
        listening.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateListeningDisplay()
    }

    private func updateListeningDisplay() {
        let listening = listeningWindow
        let visible = listening?.occlusionState.contains(.visible) == true && listening?.isMiniaturized == false
        overlay.setListeningDisplay(visible ? listening?.screen?.verseID : nil)
    }

    func windowDidChangeScreen(_ notification: Notification) { updateListeningDisplay() }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateListeningDisplay() }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow else { return }
        if closed === listeningWindow {
            listeningWindow = nil
            overlay.setListeningDisplay(nil)
        }
        if ![window, listeningWindow].contains(where: { $0 !== closed && ($0?.isVisible == true || $0?.isMiniaturized == true) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.removeAllItems()
        func item(_ title:String,_ action:Selector,_ state:Bool?=nil,_ value:Any?=nil,in dest:NSMenu?=nil) {
            let i=(dest ?? menu).addItem(withTitle:title,action:action,keyEquivalent:"")
            i.target=self
            i.representedObject=value
            if let state { i.state=state ? .on : .off }
        }
        item("Open Verseglass…",#selector(openWindow))
        item("Open Listening View", #selector(openListeningView))
        item("Start Lyric Screen Saver",#selector(startLyricSaver))
        menu.addItem(.separator())
        for s in Style.allCases where prefs.pins.contains(s.rawValue) {
            item(s.rawValue,#selector(chooseStyle(_:)),prefs.style==s,s.rawValue)
        }
        if !prefs.pins.isEmpty { menu.addItem(.separator()) }
        item("Show lyrics",#selector(enable),prefs.enabled)
        item("Show while unlocked",#selector(unlocked),prefs.showUnlocked)
        item("Keep screen awake",#selector(awake),prefs.keepAwake)
        let sizes=NSMenu()
        for size in [24,32,40,52,64,80] {
            item("\(size*100/40)%",#selector(setSize(_:)),prefs.textSize == Double(size),size,in:sizes)
        }
        menu.addItem(withTitle:"Text size",action:nil,keyEquivalent:"").submenu=sizes
        let displays=NSMenu()
        item("All displays",#selector(allScreens),prefs.displayID=="all",in:displays)
        for screen in NSScreen.screens { item(screen.localizedName,#selector(toggleDisplay(_:)),prefs.includesScreen(screen.verseID),screen.verseID,in:displays) }
        menu.addItem(withTitle:"Display",action:nil,keyEquivalent:"").submenu=displays
        menu.addItem(.separator())
        menu.addItem(withTitle:"Quit Verseglass",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
    }
    @objc private func startLyricSaver() { saverLauncher?.startFromDesktop(prefs:prefs) }
    @objc private func enable() { prefs.enabled.toggle() }
    @objc private func unlocked() { prefs.showUnlocked.toggle() }
    @objc private func awake() { prefs.keepAwake.toggle() }
    @objc private func allScreens() { prefs.displayID="all" }
    @objc private func toggleDisplay(_ sender:NSMenuItem) { if let id=sender.representedObject as? String { prefs.toggleScreen(id) } }
    @objc private func setSize(_ sender:NSMenuItem) { if let n=sender.representedObject as? Int { prefs.textSize=Double(n) } }
    @objc private func chooseStyle(_ sender:NSMenuItem) {
        if let name=sender.representedObject as? String, let s=Style(rawValue:name) { prefs.style=s }
    }
}
