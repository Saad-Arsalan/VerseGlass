import AppKit
import Combine
import CoreText
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// NSWorkspace changes the current Space's desktop picture. Only replace pictures
/// selected through setup or written by this app, even after a crash or Space change.
struct WallpaperFiles {
    let directory: URL
    func picture(_ slot: Int) -> URL { directory.appendingPathComponent("Picture-\(slot).jpg") }
    func frame(_ slot: Int) -> URL { directory.appendingPathComponent("Line-\(slot).jpg") }
    func frameSlot(_ url: URL?) -> Int? {
        (0...1).first { url?.standardizedFileURL == frame($0).standardizedFileURL }
    }
    func owns(_ url: URL?, pictureSlot: Int) -> Bool {
        url?.standardizedFileURL == picture(pictureSlot).standardizedFileURL || frameSlot(url) != nil
    }
    func nextFrame(after current: URL?, pictureSlot: Int) -> Int? {
        guard owns(current, pictureSlot: pictureSlot) else { return nil }
        return frameSlot(current) == 0 ? 1 : 0
    }
    func restorePicture(_ pictureSlot: Int, current: () -> URL?, apply: (URL) throws -> Void) throws -> Bool {
        guard let original = current() else { return false }
        guard frameSlot(original) != nil else { return true }
        try apply(picture(pictureSlot))
        // A successful request can precede the wallpaper service switching files.
        guard let after = current() else { return false }
        return frameSlot(after) == nil
    }
    // Another Space may still point to a slot. Give that URL neutral pixels
    // instead of deleting a picture the public API cannot enumerate.
    func clearLyrics(using pictureSlot: Int) throws {
        let baseline = picture(pictureSlot)
        let manager = FileManager.default
        let temp = directory.appendingPathComponent(".restoring")
        defer { try? manager.removeItem(at: temp) }
        for slot in 0...1 where manager.fileExists(atPath: frame(slot).path) {
            try? manager.removeItem(at: temp)
            // A hard link shares the baseline's storage. New lyric frames are
            // always written by atomic replacement, leaving the baseline intact.
            try manager.linkItem(at: baseline, to: temp)
            guard rename(temp.path, frame(slot).path) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        }
    }
}

struct WallpaperSubmission {
    // A completed render must still match the lock generation and the latest line.
    private(set) var generation = 0
    mutating func invalidate() { generation &+= 1 }
    func isCurrent<T: Equatable>(_ token: Int, requested: T, live: T?) -> Bool {
        token == generation && requested == live
    }
}

private enum WallpaperError: String, LocalizedError {
    case screen = "A display must be connected before choosing a lock-screen picture."
    case locked = "Unlock your Mac before choosing a desktop picture."
    case image = "Choose a readable static picture."
    case render = "VerseGlass couldn’t draw the lock-screen picture."
    var errorDescription: String? { rawValue }
}

/// Rasterize off the main thread. The baseline is decoded once per display size;
/// the clock and sign-in controls remain entirely macOS's.
actor WallpaperRenderer {
    private var cachedURL: URL?
    private var cachedEdge = 0
    private var cachedImage: CGImage?

    nonisolated static func size(for display: CGSize) -> CGSize {
        let scale = min(1, 3456 / max(1, max(display.width, display.height)))
        return CGSize(width: max(1, (display.width * scale).rounded()),
                      height: max(1, (display.height * scale).rounded()))
    }

    private nonisolated static func bitmap(_ size: CGSize) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw WallpaperError.render }
        return context
    }

    private nonisolated static func image(at url: URL, maxEdge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxEdge
              ] as CFDictionary) else { throw WallpaperError.image }
        return image
    }

    private nonisolated static func jpeg(_ image: CGImage) throws -> Data {
        let bytes = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw WallpaperError.render }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.91] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw WallpaperError.render }
        return bytes as Data
    }

    nonisolated static func baseline(from url: URL?) throws -> Data {
        if let url { return try jpeg(image(at: url, maxEdge: 6144)) }
        let context = try bitmap(CGSize(width: 32, height: 32))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        guard let black = context.makeImage() else { throw WallpaperError.render }
        return try jpeg(black)
    }

    func line(_ text: String, over baseline: URL, size: CGSize) throws -> Data {
        let edge = Int(max(size.width, size.height))
        if cachedURL != baseline || cachedEdge != edge || cachedImage == nil {
            cachedImage = try Self.image(at: baseline, maxEdge: edge)
            cachedEdge = edge
            cachedURL = baseline
        }
        guard let image = cachedImage else { throw WallpaperError.image }
        try Task.checkCancellation()
        let context = try Self.bitmap(size)
        let bounds = CGRect(origin: .zero, size: size)
        let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                        width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 0.60))
        context.fill(bounds)

        let area = CGRect(x: size.width * 0.085, y: size.height * 0.33,
                          width: size.width * 0.78, height: size.height * 0.30)
        var pointSize = min(size.width * 0.054, size.height * 0.10)
        var layout: CTFramesetter
        var measured: CGSize
        repeat {
            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, pointSize, nil)
                ?? CTFontCreateWithName("Helvetica-Bold" as CFString, pointSize, nil)
            let attributed = NSAttributedString(string: String(text.prefix(300)), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
            ])
            layout = CTFramesetterCreateWithAttributedString(attributed)
            measured = CTFramesetterSuggestFrameSizeWithConstraints(layout, CFRange(),
                nil, CGSize(width: area.width, height: .greatestFiniteMagnitude), nil)
            if measured.height <= area.height || pointSize <= 14 { break }
            pointSize *= 0.85
        } while true
        let usedHeight = min(area.height, ceil(measured.height) + 2)
        let rect = CGRect(x: area.minX, y: area.midY - usedHeight / 2, width: area.width, height: usedHeight)
        let frame = CTFramesetterCreateFrame(layout, CFRange(), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
        try Task.checkCancellation()
        guard let rendered = context.makeImage() else { throw WallpaperError.render }
        return try Self.jpeg(rendered)
    }
}

@MainActor final class LyricWallpaper: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = ""

    private struct Configuration: Codable {
        var enabled: Bool
        let displayUUID: String
        let pictureSlot: Int
    }
    private struct Line: Equatable {
        let text: String
        let size: CGSize
    }

    private let files: WallpaperFiles
    private let log = Logger(subsystem: "local.verseglass.app", category: "lyric-wallpaper")
    private var renderer = WallpaperRenderer()
    private var configuration: Configuration?
    private var engine: Engine?
    private var prefs: Preferences?
    private var saverActive: () -> Bool = { false }
    private var subscriptions = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var playback: AnyCancellable?
    private var job: Task<Void, Never>?
    private var submission = WallpaperSubmission()
    private var activity: NSObjectProtocol?
    private var hasFrames = false
    private var lastLine: Line?
    private var nextAttempt = ContinuousClock.now
    private var verifyUntil: ContinuousClock.Instant?
    private var nextDesktopCheck = ContinuousClock.now
    private var configFile: URL { files.directory.appendingPathComponent("Settings.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        files = WallpaperFiles(directory: support.appendingPathComponent("VerseGlass/Lock Wallpaper", isDirectory: true))
        if let data = try? Data(contentsOf: configFile),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data),
           (0...1).contains(saved.pictureSlot) {
            configuration = saved
            enabled = saved.enabled
            hasFrames = (0...1).contains { FileManager.default.fileExists(atPath: files.frame($0).path) }
        }
    }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func uuid(_ screen: NSScreen) -> String? {
        guard let id = displayID(screen), let uuid = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private var screen: NSScreen? {
        guard let configuration else { return nil }
        return NSScreen.screens.first { uuid($0) == configuration.displayUUID }
    }

    private func allowed(_ screen: NSScreen) -> Bool {
        guard let prefs, let id = displayID(screen), prefs.enabled else { return false }
        return prefs.includesScreen(String(id)) || (prefs.displayID == "main" && id == CGMainDisplayID())
    }

    var canHandleLock: Bool {
        guard enabled, let configuration, let screen, allowed(screen),
              FileManager.default.isReadableFile(atPath: files.picture(configuration.pictureSlot).path) else { return false }
        return files.owns(NSWorkspace.shared.desktopImageURL(for: screen), pictureSlot: configuration.pictureSlot)
    }

    func start(engine: Engine, prefs: Preferences, saverActive: @escaping () -> Bool) {
        guard subscriptions.isEmpty else { return }
        self.engine = engine
        self.prefs = prefs
        self.saverActive = saverActive
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            center.publisher(for: Notification.Name(name)).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didWakeNotification),
                   NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification))
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resyncDesktop() }.store(in: &subscriptions)
        resyncDesktop()
    }

    func enable(with imageURL: URL?) throws {
        guard !SaverLauncher.isLocked else { throw WallpaperError.locked }
        let target = NSScreen.screens.first { displayID($0).map { CGDisplayIsBuiltin($0) != 0 } == true }
            ?? NSScreen.screens.first
        guard let target, let display = uuid(target) else { throw WallpaperError.screen }
        // A previously disconnected display may still be showing our last frame.
        restore()
        guard !hasFrames else { throw WallpaperError.screen }
        let data = try WallpaperRenderer.baseline(from: imageURL)
        var directory = files.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        let slot = configuration?.pictureSlot == 0 ? 1 : 0
        let picture = files.picture(slot)
        try data.write(to: picture, options: .atomic)
        let next = Configuration(enabled: true, displayUUID: display, pictureSlot: slot)
        // Save restoration information before asking the OS to change anything.
        let previous = configuration
        try save(next)
        do {
            try apply(picture, on: target)
        } catch {
            if let previous { try save(previous) } else { try? FileManager.default.removeItem(at: configFile) }
            throw error
        }
        configuration = next
        enabled = true
        status = ""
        renderer = WallpaperRenderer()
        lastLine = nil
        monitor()
    }

    func disable() {
        guard var saved = configuration else { return }
        saved.enabled = false
        do { try save(saved) }
        catch { status = "Couldn’t save the wallpaper setting. Try turning it off again."; return }
        configuration = saved
        enabled = false
        status = ""
        restore()
        monitor()
    }

    func stop() {
        subscriptions.removeAll()
        timer = nil
        playback = nil
        restore()
    }

    private func save(_ settings: Configuration) throws {
        try JSONEncoder().encode(settings).write(to: configFile, options: .atomic)
    }

    private func apply(_ image: URL, on screen: NSScreen) throws {
        try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: true
        ])
    }

    private func monitor() {
        if enabled, let engine, playback == nil {
            let line = engine.$frame.map { frame -> String? in
                guard frame.lines.indices.contains(frame.lineIndex) else { return nil }
                return frame.lines[frame.lineIndex]
            }.removeDuplicates()
            playback = Publishers.CombineLatest(line, engine.$playing.removeDuplicates())
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        } else if !enabled { playback = nil }
        guard enabled || hasFrames || verifyUntil != nil else { timer = nil; return }
        guard timer == nil else { return }
        timer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func resyncDesktop() {
        // An inactive Space may still reference one of the slots when it returns.
        if let screen, files.frameSlot(NSWorkspace.shared.desktopImageURL(for: screen)) != nil { hasFrames = true }
        monitor()
        refresh()
    }

    private func currentLine() -> Line? {
        guard SaverLauncher.isLocked, enabled, !saverActive(), let screen, allowed(screen),
              let id = displayID(screen), CGDisplayIsAsleep(id) == 0, let engine, engine.playing else { return nil }
        let frame = engine.frame
        guard frame.lines.indices.contains(frame.lineIndex) else { return nil }
        let text = String(frame.lines[frame.lineIndex].prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let size = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                          height: screen.frame.height * screen.backingScaleFactor)
        return Line(text: text, size: WallpaperRenderer.size(for: size))
    }

    private func refresh() {
        guard enabled || hasFrames || verifyUntil != nil else { return }
        guard let line = currentLine() else { restore(); return }
        guard let configuration, let screen else { return }
        let current = NSWorkspace.shared.desktopImageURL(for: screen)
        guard files.owns(current, pictureSlot: configuration.pictureSlot) else {
            restore()
            status = "Turn off Touch ID lyrics, then choose a picture again to use this desktop."
            return
        }
        guard job == nil, ContinuousClock.now >= nextAttempt,
              line != lastLine || files.frameSlot(current) == nil else { return }
        let picture = files.picture(configuration.pictureSlot)
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Updating lyrics on the lock-screen wallpaper")
        }
        let token = submission.generation, renderer = self.renderer
        job = Task {
            defer { if token == submission.generation { job = nil } }
            do {
                let data = try await renderer.line(line.text, over: picture, size: line.size)
                // The Mac may have unlocked, switched Spaces, or advanced to another line.
                guard !Task.isCancelled, submission.isCurrent(token, requested: line, live: currentLine()),
                      let target = self.screen, uuid(target) == configuration.displayUUID else { return }
                let active = NSWorkspace.shared.desktopImageURL(for: target)
                guard let slot = files.nextFrame(after: active, pictureSlot: configuration.pictureSlot) else { return }
                let url = files.frame(slot)
                try data.write(to: url, options: .atomic)
                hasFrames = true
                try apply(url, on: target)
                lastLine = line
                nextAttempt = .now + .milliseconds(850)
                status = ""
                log.info("Submitted lock-screen lyric frame in slot \(slot, privacy: .public)")
            } catch {
                guard token == submission.generation, !Task.isCancelled else { return }
                status = "Couldn’t update the lyric wallpaper. VerseGlass will retry."
                nextAttempt = .now + .seconds(5)
                log.error("Couldn’t update lock-screen lyric wallpaper")
            }
        }
    }

    private func restore() {
        if let job { submission.invalidate(); job.cancel(); self.job = nil }
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        let firstRestore = lastLine != nil
        lastLine = nil
        let now = ContinuousClock.now
        if firstRestore { verifyUntil = now + .seconds(5) }
        if let until = verifyUntil, now >= until { verifyUntil = nil }
        guard enabled || hasFrames || verifyUntil != nil else { timer = nil; return }
        guard hasFrames || verifyUntil != nil || now >= nextDesktopCheck else { return }
        nextDesktopCheck = now + .seconds(8)
        guard let configuration, let screen,
              let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        if files.frameSlot(current) != nil { hasFrames = true }
        guard hasFrames else { return }
        do {
            // When an unlock races a just-submitted frame, macOS can still report
            // the baseline. Queue it again after the frame and verify later.
            if firstRestore && current.standardizedFileURL == files.picture(configuration.pictureSlot).standardizedFileURL {
                try apply(files.picture(configuration.pictureSlot), on: screen)
            }
            let clear = try files.restorePicture(configuration.pictureSlot, current: {
                NSWorkspace.shared.desktopImageURL(for: screen)
            }, apply: { picture in
                try self.apply(picture, on: screen)
                log.info("Restored selected desktop picture")
            })
            guard clear else { return }
        } catch {
            status = "Couldn’t restore your picture. VerseGlass will retry when the display is available."
            return
        }
        // An external wallpaper choice wins; never overwrite it on unlock.
        do {
            try files.clearLyrics(using: configuration.pictureSlot)
            hasFrames = false
        } catch {
            status = "Couldn’t clear the last lyric pictures. VerseGlass will retry."
        }
    }
}
