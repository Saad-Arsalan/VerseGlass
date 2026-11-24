import SwiftUI
import AppKit

struct LyricFrame {
    var title: String
    var artist: String
    var lines: [String]
    var lineIndex: Int
    var wordIndex: Int
    var progress: Double
    static let empty = LyricFrame(title: "", artist: "", lines: [], lineIndex: -1, wordIndex: -1, progress: 0)
    static let sample = ["Streetlights stitch the skyline", "Every window holds a star", "We follow the blue hour", "Past the corner of the park", "Let the city hum along", "Till the morning finds us here"]
    static func demo(at seconds: Double) -> Self {
        let beat = max(0, seconds).truncatingRemainder(dividingBy: Double(sample.count) * 3)
        let i = Int(beat / 3)
        let p = beat / 3 - Double(i)
        return Self(title: "Blue Hour", artist: "Verseglass", lines: sample, lineIndex: i, wordIndex: Int(p * Double(sample[i].split(separator: " ").count)), progress: p)
    }
}

enum Style: String, CaseIterable, Identifiable {
    case ship = "Ship", fisheye = "Fisheye", visual = "Visual", fisheyeVisual = "Fisheye Visual"
    case codestyle = "Codestyle", codestyleVisual = "Codestyle Visual", branches = "Branches", web = "Web", constellation = "Constellation"
    case nativeDesign = "Native Design", money = "Native Design Money", map = "Native Design Map", notifications = "Native Design Notifications"
    var id: Self { self }
    var index: Int { Self.allCases.firstIndex(of: self)! }
    var family: String { index < 4 ? "Kinetic type" : index < 9 ? "Motion scenes" : "iPhone screens" }
    var caption: String {
        ["Words drift across a wall of type.", "Three words bend through a lens.", "A symbol lights up beside the words.", "A lens brings each word and symbol into focus.", "The line types itself beneath a blinking cursor.", "Live type with a symbol for each matching word.", "Each word opens a branch.", "A strand for every word in the line.", "Follow the line from star to star.", "A message thread, one bubble for every line.", "Each line lands as a new payment.", "Follow the words from pin to pin.", "Lyric lines arrive as a stack of notifications."][index]
    }
}

extension Color {
    init(hex: String) {
        let rgb = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xffffff
        self.init(.sRGB, red: Double(rgb >> 16 & 255)/255, green: Double(rgb >> 8 & 255)/255, blue: Double(rgb & 255)/255)
    }
    var rgbHex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "%02X%02X%02X", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255))
    }
}
private struct PrimaryInk: EnvironmentKey { static let defaultValue = Color.white }
private struct SecondaryInk: EnvironmentKey { static let defaultValue = Color(hex: "A6B2C5") }
extension EnvironmentValues {
    var lyricPrimary: Color { get { self[PrimaryInk.self] } set { self[PrimaryInk.self] = newValue } }
    var lyricSecondary: Color { get { self[SecondaryInk.self] } set { self[SecondaryInk.self] = newValue } }
}

@MainActor final class Preferences: ObservableObject {
    private static let d = UserDefaults.standard
    @Published var style = Style(rawValue: d.string(forKey:"style") ?? "") ?? .nativeDesign { didSet { Self.d.set(style.rawValue, forKey:"style") } }
    @Published var textSize = (d.object(forKey:"size") as? Double) ?? 40 { didSet { Self.d.set(textSize, forKey:"size") } }
    @Published var fontName = d.string(forKey:"font") ?? "SF Pro" { didSet { Self.d.set(fontName, forKey:"font") } }
    @Published var colorHex = d.string(forKey:"accent") ?? "94DDFF" { didSet { Self.d.set(colorHex, forKey:"accent") } }
    @Published var primaryHex = d.string(forKey:"primary") ?? "FFFFFF" { didSet { Self.d.set(primaryHex, forKey:"primary") } }
    @Published var secondaryHex = d.string(forKey:"secondary") ?? "A6B2C5" { didSet { Self.d.set(secondaryHex, forKey:"secondary") } }
    @Published var matchArtwork = d.bool(forKey:"matchArtwork") { didSet { Self.d.set(matchArtwork, forKey:"matchArtwork") } }
    @Published var artworkAccent: Color?
    var effectiveAccent: Color { (matchArtwork ? artworkAccent : nil) ?? Color(hex:colorHex) }
    @Published var startSaverOnLock = d.bool(forKey:"startSaverOnLock") { didSet { Self.d.set(startSaverOnLock, forKey:"startSaverOnLock") } }
    @Published var saverAutomationReady = false
    @Published var saverMessage = "Checking System Events access…"
    @Published var lockNotifications = d.bool(forKey:"lockNotifications") {
        didSet { Self.d.set(lockNotifications, forKey:"lockNotifications") }
    }
    @Published var showUnlocked = d.bool(forKey:"unlocked") { didSet { Self.d.set(showUnlocked, forKey:"unlocked") } }
    @Published var enabled = (d.object(forKey:"enabled") as? Bool) ?? true { didSet { Self.d.set(enabled, forKey:"enabled") } }
    @Published var keepAwake = (d.object(forKey:"awake") as? Bool) ?? true { didSet { Self.d.set(keepAwake, forKey:"awake") } }
    @Published var displayID = d.string(forKey:"display") ?? "all" { didSet { Self.d.set(displayID, forKey:"display") } }
    @Published var pins = d.stringArray(forKey:"pins") ?? [Style.nativeDesign.rawValue] { didSet { Self.d.set(pins, forKey:"pins") } }
    func pin(_ item: Style) {
        if pins.contains(item.rawValue) { pins.removeAll { $0 == item.rawValue } }
        else { pins.append(item.rawValue) }
    }
    func includesScreen(_ id: String) -> Bool {
        displayID == "all" || displayID.split(separator:",").contains(Substring(id))
    }
    func toggleScreen(_ id: String) {
        var selection = Set(NSScreen.screens.map(\.verseID).filter(includesScreen))
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        displayID = selection.isEmpty ? "none" : selection.sorted().joined(separator:",")
    }
}
extension NSScreen {
    var verseID: String { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "" }
}
