import SwiftUI
import UniformTypeIdentifiers

private struct Backdrop: View {
    let style: Style
    private var hue: Double { [0.57,0.86,0.43,0.94,0.59,0.44,0.22,0.81,0.66,0.60,0.40,0.53,0.72][style.index] }
    var body: some View {
        if style == .constellation {
            ConstellationBackdrop(showsClock: false)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        } else {
            coloredBackdrop
        }
    }
    private var coloredBackdrop: some View {
        GeometryReader { g in
            ZStack {
                Color(hue:hue,saturation:0.68,brightness:0.16)
                EllipticalGradient(colors:[Color(hue:hue,saturation:0.65,brightness:0.66),.clear],center:UnitPoint(x:0.86,y:0.38),startRadiusFraction:0,endRadiusFraction:0.76)
                EllipticalGradient(colors:[Color(hue:(hue+0.94).truncatingRemainder(dividingBy:1),saturation:0.40,brightness:0.82).opacity(0.70),.clear],center:UnitPoint(x:1,y:0.46),endRadiusFraction:0.44)
                LinearGradient(stops:[.init(color:.clear,location:0.36),.init(color:.black.opacity(0.4),location:0.69),.init(color:.black,location:1)],startPoint:.top,endPoint:.bottom)
            }.frame(width:g.size.width,height:g.size.height)
        }.accessibilityHidden(true)
    }
}

@MainActor private final class BrowserState: ObservableObject {
    @Published var browsing: Style
    @Published var panel: String?
    @Published var screens = NSScreen.screens
    let origin = Date().addingTimeInterval(-7.0)
    init(style: Style) { browsing = style }
}

struct Studio: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var engine: Engine
    @ObservedObject var lockLyrics: LockLyrics
    @StateObject private var browser: BrowserState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(prefs: Preferences, engine: Engine, lockLyrics: LockLyrics) {
        self.prefs = prefs
        self.engine = engine
        self.lockLyrics = lockLyrics
        _browser = StateObject(wrappedValue: BrowserState(style:prefs.style))
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment:.top) {
                Color.black
                ScrollViewReader { scroll in
                    ScrollView(.vertical) {
                        VStack(spacing:0) {
                            hero(height:max(390, geo.size.height*0.72)).id("preview")
                            gallery { item in
                                browser.browsing=item
                                withAnimation(reduceMotion ? nil : .easeOut(duration:0.22)) { scroll.scrollTo("preview",anchor:.top) }
                            }
                        }
                    }
                }
                toolbar.padding(.top,10)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth:720,minHeight:520)
        .onChange(of:prefs.style) { _, value in browser.browsing = value }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didChangeScreenParametersNotification)) { _ in browser.screens = NSScreen.screens }
    }
    private func scene(_ frame: LyricFrame, _ style: Style, _ size: CGFloat) -> some View {
        LyricScene(frame:frame, style:style, size:size, fontName:prefs.fontName, accent:prefs.effectiveAccent)
            .environment(\.lyricPrimary, Color(hex:prefs.primaryHex))
            .environment(\.lyricSecondary, Color(hex:prefs.secondaryHex))
    }
    private func step(_ amount:Int) {
        browser.browsing = Style.allCases[(browser.browsing.index + Style.allCases.count + amount) % Style.allCases.count]
    }
    private func hero(height:CGFloat) -> some View {
        ZStack(alignment:.bottomLeading) {
            Backdrop(style:browser.browsing)
            VStack(spacing:0) {
                TimelineView(.periodic(from:browser.origin,by:reduceMotion ? 1 : 0.16)) { clock in
                    scene(.demo(at:clock.date.timeIntervalSince(browser.origin)),browser.browsing,min(48,prefs.textSize*0.83))
                }.padding(.horizontal,80).padding(.top,62)
                Spacer().frame(height:138)
            }
            HStack {
                arrow("chevron.left","Previous style",-1)
                Spacer()
                arrow("chevron.right","Next style",1)
            }.padding(.horizontal,22).frame(maxHeight:.infinity)
            VStack(alignment:.leading,spacing:7) {
                Text(browser.browsing.family).font(.caption).foregroundStyle(.white.opacity(0.72))
                Text(browser.browsing.rawValue).font(.system(size:36,weight:.semibold,design:.serif))
                Text(browser.browsing.caption).font(.callout).foregroundStyle(.white.opacity(0.82))
                HStack(spacing:8) {
                    Button(prefs.style == browser.browsing ? "Selected" : "Select") { prefs.style = browser.browsing }
                        .buttonStyle(PillButton())
                    Button { prefs.pin(browser.browsing) } label: {
                        Image(systemName:prefs.pins.contains(browser.browsing.rawValue) ? "pin.fill" : "pin").frame(width:13)
                    }.buttonStyle(PillButton()).help(prefs.pins.contains(browser.browsing.rawValue) ? "Unpin from menu bar" : "Pin to menu bar")
                }.padding(.top,6)
            }.padding(.leading,42).padding(.bottom,34)
            HStack(spacing:7) {
                ForEach(Style.allCases) { s in
                    Button { browser.browsing = s } label:{ Circle().fill(s == browser.browsing ? .white : .white.opacity(0.28)).frame(width:5,height:5) }
                        .buttonStyle(.plain).accessibilityLabel(s.rawValue)
                }
            }.frame(maxWidth:.infinity).padding(.bottom,12)
        }.frame(height:height)
    }
    private func arrow(_ icon:String,_ label:String,_ d:Int) -> some View {
        Button { step(d) } label:{ Image(systemName:icon).font(.system(size:24, weight:.light)).padding(8) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private func gallery(select: @escaping (Style) -> Void) -> some View {
        VStack(alignment:.leading,spacing:15) {
            Text("All styles").font(.title3.bold())
            LazyVGrid(columns:[GridItem(.adaptive(minimum:172),spacing:15)],spacing:19) {
                ForEach(Style.allCases) { item in
                    Button { select(item) } label:{
                        VStack(alignment:.leading,spacing:6) {
                            ZStack(alignment:.topLeading) {
                                Backdrop(style:item)
                                scene(.demo(at:7.6),item,41)
                                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                                if prefs.pins.contains(item.rawValue) {
                                    Image(systemName:"pin.fill").font(.system(size:10)).foregroundStyle(.black).padding(5).background(.white,in:Circle()).padding(7)
                                }
                            }.frame(height:104).clipShape(RoundedRectangle(cornerRadius:13))
                                .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(.white.opacity(browser.browsing == item ? 0.84 : 0.14),lineWidth:browser.browsing == item ? 2 : 1))
                            Text(item.rawValue).font(.subheadline.weight(.medium))
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal,36).padding(.vertical,22).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var toolbar: some View {
        ZStack {
            HStack(spacing:0) {
                ForEach(["Size","Font","Lock Screen","Aesthetics","Lighting"],id:\.self) { name in
                    control(name) { Text(name).font(.system(size:12,weight:.medium)) }
                }
            }.background(.thinMaterial,in:Capsule())
            HStack(spacing:0) {
                VerseglassMark().fill(.white).frame(width:18,height:18).padding(.leading,80)
                Spacer()
                HStack(spacing:0) {
                    control("Spotify") { indicator("waveform.circle.fill",engine.spotifyStatus,"Spotify") }
                    control("Apple Music") { indicator("music.note",engine.musicStatus,"Apple Music") }
                }.background(.thinMaterial,in:Capsule())
            }.padding(.trailing,14)
        }
    }
    private func indicator(_ icon:String,_ status:String,_ name:String) -> some View {
        HStack(spacing:3) {
            Image(systemName:icon).foregroundStyle(name == "Spotify" ? Color.green : Color.pink)
            Circle().fill(status.lowercased().contains("playing") && !status.lowercased().contains("not") ? .green : .gray).frame(width:5,height:5)
        }.accessibilityLabel(name)
    }
    private func control<L:View>(_ name:String,@ViewBuilder label:()->L) -> some View {
        Button { browser.panel = name } label:{ label().padding(.horizontal,11).frame(height:32).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(name)
            .popover(isPresented:Binding(get:{browser.panel == name},set:{if !$0 && browser.panel == name {browser.panel=nil}}),arrowEdge:.bottom) {
                settings(name).padding(18).frame(width:298).preferredColorScheme(.dark)
            }
    }
    @ViewBuilder private func settings(_ name:String) -> some View {
        VStack(alignment:.leading,spacing:13) {
            Text(name).font(.headline)
            switch name {
            case "Size":
                HStack { Slider(value:$prefs.textSize,in:20...80); Text("\(Int(prefs.textSize/40*100))%").monospacedDigit() }
                Button("Reset size") { prefs.textSize=40 }
            case "Font":
                ForEach(["SF Pro","SF Rounded","New York","Helvetica Neue","Avenir Next","Futura","Didot"],id:\.self) { font in
                    Button { prefs.fontName=font } label:{
                        HStack { Text(font); Spacer(); if prefs.fontName==font {Image(systemName:"checkmark")} }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            case "Lighting":
                RoomLightingView()
            case "Lock Screen":
                Button("Choose Verseglass screen saver…") {
                    NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
                }
                Toggle("Show lyrics",isOn:$prefs.enabled)
                Toggle("Start screen saver on lock during playback", isOn:$prefs.startSaverOnLock)
                if prefs.startSaverOnLock { Text(prefs.saverMessage).font(.caption).fixedSize(horizontal:false,vertical:true) }
                Toggle("Start lyrics first on ⌃⌘Q", isOn: $prefs.saverFirstShortcut)
                if prefs.saverFirstShortcut {
                    Text(prefs.shortcutAvailable ? "Ready during music playback." : "The shortcut is inactive. It needs permission to handle keypresses across apps. The menu can start the lyric saver with this access off.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    if !prefs.shortcutAvailable {
                        Button("View permission in System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Toggle("Lyric notification banners",isOn:$prefs.lockNotifications)
                if prefs.lockNotifications {
                    Text(lockLyrics.permissionHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false, vertical:true)
                    Button("Notification settings…") {
                        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
                Toggle("Show lyrics while unlocked",isOn:$prefs.showUnlocked)
                Toggle("Keep screen awake during playback",isOn:$prefs.keepAwake)
                Divider()
                Text("Desktop displays").font(.caption).foregroundStyle(.secondary)
                ForEach(browser.screens,id:\.verseID) { screen in
                    Toggle(screen.localizedName,isOn:Binding(get:{prefs.includesScreen(screen.verseID)},set:{_ in prefs.toggleScreen(screen.verseID)}))
                }
            case "Aesthetics":
                Toggle("Match album accent",isOn:$prefs.matchArtwork)
                ink("Lyric text",$prefs.primaryHex)
                ink("Highlight",$prefs.colorHex)
                ink("Secondary text",$prefs.secondaryHex)
                Button("Reset colors") { prefs.primaryHex="FFFFFF"; prefs.colorHex="94DDFF"; prefs.secondaryHex="A6B2C5"; prefs.matchArtwork=false }
            default:
                Text(name == "Spotify" ? engine.spotifyStatus : engine.musicStatus)
                if engine.activeSource?.rawValue == name {
                    Text([engine.frame.title,engine.frame.artist].filter{!$0.isEmpty}.joined(separator:" · ")).bold()
                    Text(engine.status).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Stepper("Timing shift  \(Int(engine.timingOffset)) s",value:$engine.timingOffset,in:-30...30)
                    Button("Import LRC for this track…") { importFile() }
                } else {
                    Text("Play a song in \(name) to see its lyrics here.").foregroundStyle(.secondary)
                    let bundleID = (name == "Spotify" ? MusicSource.spotify : .music).bundleID
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundleID) {
                        Button("Open \(name)") { NSWorkspace.shared.openApplication(at:url,configuration:.init()) }
                    }
                }
                Divider()
                Toggle("Look up lyrics online",isOn:$engine.onlineLookup)
                Button("Open Automation permissions") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
            }
        }
    }
    private func ink(_ label:String,_ hex:Binding<String>) -> some View {
        ColorPicker(label,selection:Binding(get:{Color(hex:hex.wrappedValue)},set:{hex.wrappedValue=$0.rgbHex}),supportsOpacity:false)
    }
    private func importFile() {
        let open = NSOpenPanel()
        open.allowedContentTypes=[UTType(filenameExtension:"lrc") ?? .plainText,.plainText]
        open.allowsMultipleSelection=false
        if open.runModal() == .OK, let url=open.url { engine.importLyrics(url) }
    }
}
private struct PillButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:13,weight:.semibold)).foregroundStyle(.black)
            .padding(.horizontal,15).frame(height:34).background(.white.opacity(configuration.isPressed ? 0.75 : 1),in:Capsule())
    }
}
