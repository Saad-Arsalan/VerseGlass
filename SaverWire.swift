import Foundation

// A selected screen saver asks the menu-bar app for the current frame.
// Only the recent lines needed for drawing are sent, and only in this session.
struct SaverPacket: Codable {
    static let maximumBytes = 16_384
    static let request = Notification.Name("local.verseglass.saver.request")
    static let response = Notification.Name("local.verseglass.saver.frame")
    let date: Date
    let title: String
    let artist: String
    let lines: [String]
    let lineIndex: Int
    let wordIndex: Int
    let progress: Double
    let style: String
    let size: Double
    let font: String
    let accent: String
    let primary: String
    let secondary: String
    let display: String
    let rim: SaverRim
    var firstLineNumber: Int?
    var artwork: Data?
    var showsConstellationBackdrop: Bool?
}
struct SaverRim: Codable {
    var enabled = false
    var level = 0.0
    var primary = "EB9852"
    var secondary = "CA405D"
    var thickness = 1.0
    var glow = 1.0
    var display = "all"
}
