import AppKit
import Combine
import ImageIO

// Exercise ownership, recovery and the real renderer without changing a desktop.
final class Engine {
    @Published var frame = LyricFrame.empty
    @Published var playing = false
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

        try await checkStyles(over: baseline)
        let scaled = WallpaperRenderer.size(for: CGSize(width: 7680, height: 4320))
        precondition(scaled.width == 3456 && scaled.height == 1944)
    }

    private static func snapshot(_ frame: LyricFrame, style: Style = .constellation,
                                 accent: String = "94DDFF") -> WallpaperStyleFrame? {
        WallpaperStyleFrame(frame: frame, style: style, fontName: "SF Pro", textSize: 40,
                            primary: "FFFFFF", secondary: "A6B2C5", accent: accent)
    }

    @MainActor private static func checkStyles(over baseline: URL) async throws {
        _ = NSApplication.shared
        let renderer = WallpaperRenderer()
        let size = CGSize(width: 900, height: 600)
        var lyric = LyricFrame(title: "Blue Hour", artist: "VerseGlass", lines: LyricFrame.sample,
                               lineIndex: 1, wordIndex: 1, progress: 0.3)
        let early = snapshot(lyric)!
        lyric.progress += 0.01
        precondition(snapshot(lyric) == early, "Playback ticks within one word should reuse its picture")
        lyric.wordIndex = 3
        let later = snapshot(lyric)!
        precondition(early != later && later.canFollow(early) && !early.canFollow(later))
        var jump = lyric
        jump.wordIndex = 4
        precondition(!snapshot(jump)!.canFollow(early), "Drop a render when playback jumps several words")
        var seek = lyric
        seek.lineIndex = 2
        precondition(!snapshot(seek)!.canFollow(early))
        seek = lyric
        seek.title = "Second recording"
        precondition(!snapshot(seek)!.canFollow(early))
        precondition(snapshot(.empty) == nil)

        func render(_ frame: WallpaperStyleFrame) async throws -> [UInt8] {
            guard let (image, rect) = frame.foreground(for: size, scale: 2) else {
                preconditionFailure("Could not draw " + frame.style.rawValue)
            }
            let safeArea = CGRect(x: 0, y: size.height * 0.15, width: size.width, height: size.height * 0.7)
            precondition(safeArea.contains(rect), "The lyric artboard must leave room for the clock and sign-in controls")
            let picture = try await renderer.composite(image, in: rect, over: baseline, size: size,
                                                       constellation: frame.style == .constellation)
            guard let source = CGImageSourceCreateWithData(picture as CFData, nil),
                  let output = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                preconditionFailure("Invalid wallpaper JPEG")
            }
            precondition(output.width == Int(size.width) && output.height == Int(size.height))
            var pixels = [UInt8](repeating: 0, count: output.width * output.height)
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: output.width, height: output.height,
                                        bitsPerComponent: 8, bytesPerRow: output.width,
                                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                context.draw(output, in: CGRect(origin: .zero, size: size))
            }
            return pixels
        }

        var constellation: [UInt8] = []
        for style in Style.allCases {
            var earlierWord = lyric
            earlierWord.wordIndex = 1
            let first = try await render(snapshot(earlierWord, style: style)!)
            let next = try await render(snapshot(lyric, style: style)!)
            let bright = next.indices.filter { next[$0] > 160 }
            precondition(bright.count > 100, "Missing visible lyric scene in " + style.rawValue)
            let margins = Int(size.width * size.height * 0.15)
            precondition(first.prefix(margins) == next.prefix(margins) && first.suffix(margins) == next.suffix(margins),
                         "Lyric updates overlap system clock or login area in " + style.rawValue)
            precondition(visiblyDifferent(first, next), "Active word is frozen in " + style.rawValue)
            if style == .constellation { constellation = next }
            if style == .nativeDesign {
                precondition(visiblyDifferent(constellation, next), "The selected style must change the composition")
            }
        }
        var repeated = LyricFrame(title: "Blue Hour", artist: "VerseGlass", lines: ["Again", "Again", "Again"],
                                  lineIndex: 2, wordIndex: 0, progress: 0)
        let outgoing = try await render(snapshot(repeated, style: .nativeDesign)!)
        repeated.firstLineNumber += 1
        let incoming = try await render(snapshot(repeated, style: .nativeDesign)!)
        precondition(visiblyDifferent(outgoing, incoming), "Repeated lines must keep their original bubble side")
        let blue = try await render(snapshot(lyric, style: .fisheye, accent: "407CFA")!)
        let yellow = try await render(snapshot(lyric, style: .fisheye, accent: "F8D24F")!)
        precondition(visiblyDifferent(blue, yellow), "The lock-screen highlight should use the selected accent")
        print("Passed word timing, styled pictures, and clock and sign-in clearance in all 13 styles")
    }

    private static func visiblyDifferent(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        precondition(a.count == b.count)
        var count = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > 24 {
            count += 1
            if count >= 30 { return true }
        }
        return false
    }
}
