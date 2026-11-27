import SwiftUI
import AppKit

extension Color {
    var rgbHex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "%02X%02X%02X", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255))
    }
}

@MainActor final class Preferences: ObservableObject {
    private static let d = UserDefaults.standard
    @Published var style = Style(rawValue: d.string(forKey:"style") ?? "") ?? .constellation { didSet { Self.d.set(style.rawValue, forKey:"style") } }
    @Published var textSize = (d.object(forKey:"size") as? Double) ?? 40 { didSet { Self.d.set(textSize, forKey:"size") } }
    @Published var fontName = d.string(forKey:"font") ?? "SF Pro" { didSet { Self.d.set(fontName, forKey:"font") } }
    @Published var colorHex = d.string(forKey:"accent") ?? "94DDFF" { didSet { Self.d.set(colorHex, forKey:"accent") } }
    @Published var primaryHex = d.string(forKey:"primary") ?? "FFFFFF" { didSet { Self.d.set(primaryHex, forKey:"primary") } }
    @Published var secondaryHex = d.string(forKey:"secondary") ?? "A6B2C5" { didSet { Self.d.set(secondaryHex, forKey:"secondary") } }
    @Published var matchArtwork = d.bool(forKey:"matchArtwork") { didSet { Self.d.set(matchArtwork, forKey:"matchArtwork") } }
    @Published var artworkAccent: Color?
    @Published var listeningCover: NSImage?
    var artworkThumbnail: Data?
    var effectiveAccent: Color { (matchArtwork ? artworkAccent : nil) ?? Color(hex:colorHex) }
    @Published var startSaverOnLock = d.bool(forKey:"startSaverOnLock") { didSet { Self.d.set(startSaverOnLock, forKey:"startSaverOnLock") } }
    @Published var touchIDLyricDelay = min(3.0, max(-3.0, d.double(forKey: "touchIDLyricDelay"))) {
        didSet { Self.d.set(touchIDLyricDelay, forKey: "touchIDLyricDelay") }
    }
    @Published var saverFirstShortcut = d.bool(forKey: "saverFirstShortcut") {
        didSet { Self.d.set(saverFirstShortcut, forKey: "saverFirstShortcut") }
    }
    @Published var shortcutAvailable = false
    @Published var saverAutomationReady = false
    @Published var saverMessage = "Checking System Events access…"
    @Published var lockNotifications = d.bool(forKey:"lockNotifications") {
        didSet { Self.d.set(lockNotifications, forKey:"lockNotifications") }
    }
    @Published var showUnlocked = d.bool(forKey:"unlocked") { didSet { Self.d.set(showUnlocked, forKey:"unlocked") } }
    @Published var enabled = (d.object(forKey:"enabled") as? Bool) ?? true { didSet { Self.d.set(enabled, forKey:"enabled") } }
    @Published var keepAwake = (d.object(forKey:"awake") as? Bool) ?? true { didSet { Self.d.set(keepAwake, forKey:"awake") } }
    @Published var displayID = d.string(forKey:"display") ?? "all" { didSet { Self.d.set(displayID, forKey:"display") } }
    @Published var pins = d.stringArray(forKey:"pins") ?? [Style.constellation.rawValue, Style.nativeDesign.rawValue] { didSet { Self.d.set(pins, forKey:"pins") } }
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
