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
        // Old releases used two fixed URLs. Both can still be selected after an upgrade.
        let legacy = ["Line-0.jpg", "Line-1.jpg"].map { root.appendingPathComponent($0) }
        var pendingRender = WallpaperSubmission()
        let token = pendingRender.generation
        precondition(pendingRender.isCurrent(token, requested: "one", live: "one"))
        precondition(!pendingRender.isCurrent(token, requested: "one", live: "two"))
        precondition(!pendingRender.isCurrent(token, requested: "one", live: nil))
        pendingRender.invalidate()
        precondition(!pendingRender.isCurrent(token, requested: "one", live: "one"))
        for frame in legacy {
            var current: URL? = frame
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
        let pending = try files.restorePicture(0, current: { legacy[1] }, apply: { _ in })
        precondition(!unavailable && !pending, "Keep frame files until restoration can be confirmed")
        print("Passed wallpaper ownership and delayed recovery")

        let black = try WallpaperRenderer.baseline(from: nil)
        try black.write(to: baseline)
        try Data("last lyric".utf8).write(to: legacy[1], options: .atomic)
        try files.clearLyrics(using: 0)
        let neutral = try Data(contentsOf: legacy[1])
        precondition(neutral == black, "A parked Space must now have neutral pixels at the same file path")
        try Data("next lyric".utf8).write(to: legacy[1], options: .atomic)
        let intact = try Data(contentsOf: baseline)
        precondition(intact == black, "Reusing the frame must preserve the baseline")
        try checkNewFrames(in: root, baseline: baseline, black: black, legacy: legacy)
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

    private static func checkNewFrames(in root: URL, baseline: URL, black: Data, legacy: [URL]) throws {
        let manager = FileManager.default
        let files = WallpaperFiles(directory: root)
        let unrelated = root.appendingPathComponent("Keep.jpg")
        let untouched = Data("user picture".utf8)
        try untouched.write(to: unrelated)

        // A pointer outside the private directory or an unrelated entry inside it
        // must survive both pruning and recovery, even if its name resembles a frame.
        let otherDirectory = root.appendingPathComponent("Other", isDirectory: true)
        try manager.createDirectory(at: otherDirectory, withIntermediateDirectories: false)
        let external = otherDirectory.appendingPathComponent("Frame-01234567-89AB-4CDE-8123-0123456789AB.jpg")
        try untouched.write(to: external)
        let traversal = root.appendingPathComponent("..").appendingPathComponent(root.lastPathComponent)
            .appendingPathComponent(external.lastPathComponent)
        let baselineTraversal = traversal.deletingLastPathComponent().appendingPathComponent(baseline.lastPathComponent)
        let link = root.appendingPathComponent("Frame-11111111-1111-4111-8111-111111111111.jpg")
        try manager.createSymbolicLink(at: link, withDestinationURL: external)
        let folder = root.appendingPathComponent("Frame-22222222-2222-4222-8222-222222222222.jpg", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)

        let foundLegacy = try files.containsFrames()
        precondition(foundLegacy, "Find an old lyric picture on startup")
        for url in legacy where manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        let foundUnrelated = try files.containsFrames()
        precondition(!foundUnrelated, "External files should never trigger recovery")
        for url in [unrelated, external, traversal, baselineTraversal, link, folder] {
            precondition(!files.isFrame(url), "Unexpected wallpaper ownership for " + url.lastPathComponent)
            let ignored = try files.writeFrame(Data([0]), after: url, pictureSlot: 0)
            precondition(ignored == nil, "Never take over a desktop after the user selected a different picture")
        }

        var submitted: [URL] = []
        var contents: [URL: Data] = [:]
        // Keep reporting the first frame as selected, like a slow wallpaper host.
        for i in 0..<(WallpaperFiles.retainedFrameCount * 3) {
            let bytes = Data("cue-\(i)".utf8)
            let selected = submitted.first ?? baseline
            guard let new = try files.writeFrame(bytes, after: selected, pictureSlot: 0) else {
                preconditionFailure("An owned selection must accept the next lyric")
            }
            precondition(!submitted.contains(new), "Repeated picture URLs can redisplay stale cached words")
            submitted.append(new)
            contents[new] = bytes
            let retained = submitted.filter { manager.fileExists(atPath: $0.path) }
            precondition(retained.count <= WallpaperFiles.retainedFrameCount, "Generated pictures must stay bounded")
            precondition(retained.contains(submitted[0]) && retained.contains(new), "Preserve the current and newest images")
            for url in retained {
                let previousBytes = try Data(contentsOf: url)
                precondition(previousBytes == contents[url], "Never mutate an already-submitted lyric image")
            }
        }

        // Recover from disk alone, as when the app restarts after being killed.
        let recovered = WallpaperFiles(directory: root)
        let foundGenerated = try recovered.containsFrames()
        precondition(foundGenerated, "Find generated pictures after an interrupted lock")
        for url in legacy { try Data("legacy cue".utf8).write(to: url) }
        for previous in submitted + legacy {
            var current: URL? = previous
            let restored = try recovered.restorePicture(0, current: { current }, apply: { current = $0 })
            precondition(restored && current == baseline, "Restore generated, pruned, and legacy references")
        }
        try recovered.clearLyrics(using: 0, keeping: submitted[0])
        try recovered.clearLyrics(using: 0, keeping: submitted[0])
        for url in submitted + legacy where manager.fileExists(atPath: url.path) {
            let remaining = try Data(contentsOf: url)
            precondition(remaining == black, "Restored wallpaper files must no longer reveal a lyric")
        }
        precondition(manager.fileExists(atPath: submitted[0].path), "Preserve a baseline fallback at the selected URL")
        for url in [external, unrelated, link] {
            let bytes = try Data(contentsOf: url)
            precondition(bytes == untouched)
        }
        let storedLink = try manager.destinationOfSymbolicLink(atPath: link.path)
        precondition(storedLink == external.path)
        let folderType = try folder.resourceValues(forKeys: [.isDirectoryKey])
        precondition(folderType.isDirectory == true)
        print("Passed immutable submissions, bounded retention, and recovery after restart")
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
