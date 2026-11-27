import AppKit
import Combine
import ImageIO

// Exercise ownership, recovery and the real renderer without changing a desktop.
struct Frame { var lines: [String] = []; var lineIndex = -1 }
final class Engine { @Published var frame = Frame(); @Published var playing = false }
final class Preferences {
    var enabled = true
    var displayID = "all"
    func includesScreen(_ id: String) -> Bool { displayID == "all" || displayID == id }
}
enum SaverLauncher { static let isLocked = false }

@main enum TestLockWallpaper {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = WallpaperFiles(directory: root)
        let baseline = files.picture(0)
        let elsewhere = root.appendingPathComponent("external").appendingPathComponent("Line-0.jpg")

        precondition(files.owns(baseline, pictureSlot: 0))
        precondition(!files.owns(baseline, pictureSlot: 1))
        precondition(!files.owns(elsewhere, pictureSlot: 0) && !files.owns(nil, pictureSlot: 0))
        precondition(files.nextFrame(after: baseline, pictureSlot: 0) == 0)
        precondition(files.nextFrame(after: files.frame(0), pictureSlot: 0) == 1)
        precondition(files.nextFrame(after: files.frame(1), pictureSlot: 0) == 0)
        precondition(files.nextFrame(after: elsewhere, pictureSlot: 0) == nil)
        var pendingRender = WallpaperSubmission()
        let token = pendingRender.generation
        precondition(pendingRender.isCurrent(token, requested: "one", live: "one"))
        precondition(!pendingRender.isCurrent(token, requested: "one", live: "two"))
        precondition(!pendingRender.isCurrent(token, requested: "one", live: nil))
        pendingRender.invalidate()
        precondition(!pendingRender.isCurrent(token, requested: "one", live: "one"))
        for slot in 0...1 {
            var current: URL? = files.frame(slot)
            let restored = try files.restorePicture(0, current: { current }, apply: { current = $0 })
            precondition(restored && current == baseline)
        }

        for current in [baseline, elsewhere] {
            let restored = try files.restorePicture(0, current: { current }, apply: { _ in
                preconditionFailure("An external or already-restored picture must be left alone")
            })
            precondition(restored)
        }
        let unavailable = try files.restorePicture(0, current: { nil }, apply: { _ in
            preconditionFailure("A missing desktop cannot be changed")
        })
        let pending = try files.restorePicture(0, current: { files.frame(1) }, apply: { _ in })
        precondition(!unavailable && !pending, "Keep frame files until restoration can be confirmed")
        print("Passed wallpaper ownership and delayed recovery")

        let black = try WallpaperRenderer.baseline(from: nil)
        try black.write(to: baseline)
        try Data("last lyric".utf8).write(to: files.frame(1), options: .atomic)
        try files.clearLyrics(using: 0)
        let neutral = try Data(contentsOf: files.frame(1))
        precondition(neutral == black, "A parked Space must now have neutral pixels at the same file path")
        try Data("next lyric".utf8).write(to: files.frame(1), options: .atomic)
        let intact = try Data(contentsOf: baseline)
        precondition(intact == black, "Reusing the frame must preserve the baseline")
        let imported = try WallpaperRenderer.baseline(from: baseline)
        precondition(!imported.isEmpty)
        do {
            _ = try WallpaperRenderer.baseline(from: elsewhere)
            preconditionFailure("Unreadable pictures must fail before setup changes any desktop")
        } catch { }

        let renderer = WallpaperRenderer()
        let size = CGSize(width: 900, height: 600)
        let first = try await renderer.line("A quiet sky", over: baseline, size: size)
        let second = try await renderer.line("Another word", over: baseline, size: size)
        precondition(first != second)
        guard let source = CGImageSourceCreateWithData(first as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { preconditionFailure() }
        precondition(image.width == 900 && image.height == 600)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        let bright = pixels.indices.filter { pixels[$0] > 160 }
        precondition(bright.count > 500, "The rendered picture must contain visible text")
        precondition(bright.allSatisfy { (175..<420).contains($0 / image.width) },
                     "Keep the system clock and sign-in area clear")
        let scaled = WallpaperRenderer.size(for: CGSize(width: 7680, height: 4320))
        precondition(scaled.width == 3456 && scaled.height == 1944)
        print("Passed static picture setup and legible, line-specific rendering")
    }
}
