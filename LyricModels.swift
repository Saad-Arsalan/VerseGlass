import SwiftUI

struct LyricFrame {
    var title: String
    var artist: String
    var lines: [String]
    var lineIndex: Int
    var wordIndex: Int
    var progress: Double
    // The screen saver receives a window of lines from the full song.
    var firstLineNumber: Int = 0
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
        ["Words drift across a wall of type.", "Three words bend through a lens.", "A symbol lights up beside the words.", "A lens brings each word and symbol into focus.", "The line types itself beneath a blinking cursor.", "Live type with a symbol for each matching word.", "Each word opens a branch.", "A strand for every word in the line.", "Trace each phrase in stars as the sung word comes into focus.", "A message thread, one bubble for every line.", "Each line lands as a new payment.", "Follow the words from pin to pin.", "Lyric lines arrive as a stack of notifications."][index]
    }
}

extension Color {
    init(hex: String) {
        let rgb = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xffffff
        self.init(.sRGB, red: Double(rgb >> 16 & 255)/255, green: Double(rgb >> 8 & 255)/255, blue: Double(rgb & 255)/255)
    }
}
private struct PrimaryInk: EnvironmentKey { static let defaultValue = Color.white }
private struct SecondaryInk: EnvironmentKey { static let defaultValue = Color(hex: "A6B2C5") }
extension EnvironmentValues {
    var lyricPrimary: Color { get { self[PrimaryInk.self] } set { self[PrimaryInk.self] = newValue } }
    var lyricSecondary: Color { get { self[SecondaryInk.self] } set { self[SecondaryInk.self] = newValue } }
}
