import SwiftUI
import AppKit
import CoreImage
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
    private var overlay: OverlayManager!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
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
        engine.start()
    }
    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        prefs.artworkAccent=nil
        RoomLighting.shared.clearPalette()
        guard let url else { return }
        artworkTask=Task {
            do {
                let data:Data
                if url.isFileURL { data = try Data(contentsOf:url) }
                else { data = try await URLSession.shared.data(from:url).0 }
                try Task.checkCancellation()
                guard let art=CIImage(data:data) else { return }
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
    func windowWillClose(_ notification:Notification) { NSApp.setActivationPolicy(.accessory) }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.removeAllItems()
        func item(_ title:String,_ action:Selector,_ state:Bool?=nil,_ value:Any?=nil,in dest:NSMenu?=nil) {
            let i=(dest ?? menu).addItem(withTitle:title,action:action,keyEquivalent:"")
            i.target=self
            i.representedObject=value
            if let state { i.state=state ? .on : .off }
        }
        item("Open Verseglass…",#selector(openWindow))
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
