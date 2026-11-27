import AppKit
import Combine
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// NSWorkspace changes the current Space's desktop picture. Only replace pictures
/// selected through setup or written by this app, even after a crash or Space change.
struct WallpaperFiles {
    let directory: URL
    static let retainedFrameCount = 4
    func picture(_ slot: Int) -> URL { directory.appendingPathComponent("Picture-\(slot).jpg") }
    // Earlier releases installed these two names as desktop pictures.
    func frame(_ slot: Int) -> URL { directory.appendingPathComponent("Line-\(slot).jpg") }

    private func inDirectory(_ url: URL?) -> Bool {
        guard let url, url.isFileURL, url.host.map({ $0.isEmpty || $0 == "localhost" }) ?? true,
              !url.pathComponents.contains("..") else { return false }
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        let expected = directory.standardizedFileURL
        if parent.path == expected.path { return true }
        // APFS may enumerate an existing folder using its original capitalization.
        // Confirm both spellings name the same directory, including on case-sensitive volumes.
        guard parent.path.caseInsensitiveCompare(expected.path) == .orderedSame,
              let parentID = try? parent.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject,
              let expectedID = try? expected.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
        else { return false }
        return parentID.isEqual(expectedID)
    }

    func isFrame(_ url: URL?) -> Bool {
        guard let url, inDirectory(url) else { return false }
        let name = url.lastPathComponent
        if name != "Line-0.jpg" && name != "Line-1.jpg" {
            guard name.hasPrefix("Frame-"), name.hasSuffix(".jpg") else { return false }
            let id = String(name.dropFirst(6).dropLast(4))
            guard UUID(uuidString: id)?.uuidString == id else { return false }
        }
        // A retired frame can be selected on an inactive Space. Recognize its
        // name even after pruning, but never follow or remove a symlink or directory.
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isSymbolicLink != true && values?.isRegularFile != false
    }

    func isPicture(_ url: URL?, slot: Int) -> Bool {
        guard let url, inDirectory(url) else { return false }
        return url.lastPathComponent == picture(slot).lastPathComponent
    }

    func owns(_ url: URL?, pictureSlot: Int) -> Bool {
        isPicture(url, slot: pictureSlot) || isFrame(url)
    }

    private func generatedFrames() throws -> [URL] {
        let keys = [URLResourceKey.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        // Only scan this app-owned directory, on submission, startup and cleanup.
        let generated = try contents.compactMap { url -> (URL, Date)? in
            guard url.lastPathComponent.hasPrefix("Frame-"), isFrame(url) else { return nil }
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (url, modified ?? .distantPast)
        }
        return generated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    func containsFrames() throws -> Bool {
        if (0...1).contains(where: { FileManager.default.fileExists(atPath: frame($0).path) && isFrame(frame($0)) }) {
            return true
        }
        return try !generatedFrames().isEmpty
    }

    private func unlinkFrame(_ url: URL) throws {
        // Never recursively remove an entry if it changed type since enumeration.
        if unlink(url.path) != 0 && errno != ENOENT { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    func writeFrame(_ data: Data, after current: URL?, pictureSlot: Int) throws -> URL? {
        guard owns(current, pictureSlot: pictureSlot) else { return nil }
        // The wallpaper service caches image layers by URL. Give each submission
        // a new path, retaining several predecessors so in-flight loads can finish.
        let existing = try generatedFrames()
        let selectedName = isFrame(current) ? current?.lastPathComponent : nil
        let unselected = existing.filter { $0.lastPathComponent != selectedName }
        let pinnedCount = existing.count - unselected.count
        for old in unselected.dropFirst(Self.retainedFrameCount - 1 - pinnedCount) {
            try unlinkFrame(old)
        }
        let url = directory.appendingPathComponent("Frame-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    func restorePicture(_ pictureSlot: Int, current: () -> URL?, apply: (URL) throws -> Void) throws -> Bool {
        guard let original = current() else { return false }
        guard isFrame(original) else { return true }
        try apply(picture(pictureSlot))
        // A successful request can precede the wallpaper service switching files.
        guard let after = current() else { return false }
        return !isFrame(after)
    }

    func clearLyrics(using pictureSlot: Int, keeping current: URL? = nil) throws {
        let baseline = picture(pictureSlot)
        let manager = FileManager.default
        let generated = try generatedFrames()
        let newest = generated.first
        let selectedName = isFrame(current) ? current?.lastPathComponent : nil
        let legacy = (0...1).map { frame($0) }.filter { manager.fileExists(atPath: $0.path) && isFrame($0) }
        for url in generated + legacy {
            if url == newest || url.lastPathComponent == selectedName || legacy.contains(url) {
                // Preserve a neutral picture for a late system load or a legacy Space.
                // Replacing the directory entry leaves the baseline's bytes untouched.
                let temp = directory.appendingPathComponent(".restore-\(UUID().uuidString)")
                try manager.linkItem(at: baseline, to: temp)
                defer { _ = unlink(temp.path) }
                guard rename(temp.path, url.path) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            } else {
                try unlinkFrame(url)
            }
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

/// Prepare the fixed background once, then composite and encode each word off the main thread.
actor WallpaperRenderer {
    private struct Background: Equatable {
        let url: URL
        let size: CGSize
        let constellation: Bool
    }
    private var cachedBackground: (key: Background, image: CGImage)?

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

    private nonisolated static func jpeg(_ image: CGImage, quality: Double = 0.91) throws -> Data {
        let bytes = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw WallpaperError.render }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
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

    private func background(_ key: Background) throws -> CGImage {
        if let cachedBackground, cachedBackground.key == key { return cachedBackground.image }
        let context = try Self.bitmap(key.size)
        let bounds = CGRect(origin: .zero, size: key.size)
        let maxEdge = Int(max(key.size.width, key.size.height))
        func fill(with image: CGImage) {
            let scale = max(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let width = CGFloat(image.width) * scale
            let height = CGFloat(image.height) * scale
            context.draw(image, in: CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                                            width: width, height: height))
        }
        context.interpolationQuality = .high
        fill(with: try Self.image(at: key.url, maxEdge: min(1920, maxEdge)))
        context.setFillColor(CGColor(gray: 0, alpha: 0.60))
        context.fill(bounds)
        if key.constellation, let url = Bundle.main.url(forResource: "ConstellationInk", withExtension: "jpg"),
           let ink = try? Self.image(at: url, maxEdge: min(640, maxEdge)) {
            context.setBlendMode(.screen)
            context.setAlpha(0.84)
            fill(with: ink)
        }
        guard let backdrop = context.makeImage() else { throw WallpaperError.render }
        cachedBackground = (key, backdrop)
        return backdrop
    }

    func composite(_ foreground: CGImage, in rect: CGRect, over baseline: URL,
                   size: CGSize, constellation: Bool = false) throws -> Data {
        try Task.checkCancellation()
        let backdrop = try background(Background(url: baseline, size: size, constellation: constellation))
        let context = try Self.bitmap(size)
        context.draw(backdrop, in: CGRect(origin: .zero, size: size))
        context.draw(foreground, in: rect)
        try Task.checkCancellation()
        guard let rendered = context.makeImage() else { throw WallpaperError.render }
        // Keep the foreground at display resolution. Soften only the background
        // and use a smaller JPEG for these short-lived wallpaper submissions.
        return try Self.jpeg(rendered, quality: 0.68)
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
    private struct Scene: Equatable {
        let content: WallpaperStyleFrame
        let size: CGSize
        let scale: CGFloat
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
    private var activeDelay: TimeInterval = 0
    private var job: Task<Void, Never>?
    private var submission = WallpaperSubmission()
    private var activity: NSObjectProtocol?
    private var hasFrames = false
    private var needsFileCleanup = false
    private var nextRestoreAttempt = ContinuousClock.now
    private var lastFrame: Scene?
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
            hasFrames = (try? files.containsFrames()) ?? true
            needsFileCleanup = hasFrames
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
        lastFrame = nil
        monitor()
    }

    func disable() {
        guard var saved = configuration else { return }
        saved.enabled = false
        do { try save(saved) }
        catch { status = "Couldn’t save the wallpaper setting. Try turning it off again."; return }
        configuration = saved
        enabled = false
        activeDelay = 0
        status = ""
        restore()
        monitor()
    }

    func stop() {
        subscriptions.removeAll()
        timer = nil
        playback = nil
        activeDelay = 0
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
        if enabled, let engine, let prefs, playback == nil {
            // Sample through instrumental gaps too. A delayed word can start or
            // finish while the unshifted view stays idle.
            let frames = engine.timingTick.map { [weak self] () -> LyricFrame in
                guard let self, let engine = self.engine else { return .empty }
                return activeDelay == 0 ? engine.frame : engine.playbackFrame(delay: activeDelay)
            }
            let words = frames.removeDuplicates { (lhs: LyricFrame, rhs: LyricFrame) -> Bool in
                lhs.wordIndex == rhs.wordIndex && lhs.lineIndex == rhs.lineIndex &&
                    lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.lines == rhs.lines &&
                    lhs.firstLineNumber == rhs.firstLineNumber
            }.map { _ in () }
            playback = words.merge(with: engine.$playing.removeDuplicates().map { _ in () }, prefs.objectWillChange)
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        } else if !enabled { playback = nil }
        guard enabled || hasFrames || verifyUntil != nil else { timer = nil; return }
        guard timer == nil else { return }
        timer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func resyncDesktop() {
        // A returning Space can still refer to a retired frame by name.
        if let screen, files.isFrame(NSWorkspace.shared.desktopImageURL(for: screen)) { hasFrames = true }
        monitor()
        refresh()
    }

    private func currentScene() -> Scene? {
        guard SaverLauncher.isLocked, enabled, !saverActive(), let screen, allowed(screen),
              let id = displayID(screen), CGDisplayIsAsleep(id) == 0, let engine, engine.playing, let prefs else {
            activeDelay = 0
            return nil
        }
        activeDelay = prefs.touchIDLyricDelay
        let frame = activeDelay == 0 ? engine.frame : engine.playbackFrame(delay: activeDelay)
        guard let content = WallpaperStyleFrame(frame: frame, style: prefs.style, fontName: prefs.fontName,
                  textSize: prefs.textSize, primary: prefs.primaryHex, secondary: prefs.secondaryHex,
                  accent: prefs.effectiveAccent.rgbHex) else { return nil }
        let display = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                             height: screen.frame.height * screen.backingScaleFactor)
        let size = WallpaperRenderer.size(for: display)
        return Scene(content: content, size: size, scale: size.width / max(1, screen.frame.width))
    }

    private func refresh() {
        guard enabled || hasFrames || verifyUntil != nil else { return }
        guard let scene = currentScene() else { restore(); return }
        guard let configuration, let screen else { return }
        let current = NSWorkspace.shared.desktopImageURL(for: screen)
        guard files.owns(current, pictureSlot: configuration.pictureSlot) else {
            activeDelay = 0
            restore()
            status = "Turn off Touch ID lyrics, then choose a picture again to use this desktop."
            return
        }
        guard job == nil, scene != lastFrame || !files.isFrame(current) else { return }
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Updating lyrics on the lock-screen wallpaper")
        }
        let token = submission.generation
        job = Task {
            var catchUp = false
            defer {
                if token == submission.generation {
                    job = nil
                    if catchUp { refresh() }
                }
            }
            do {
                // Only one pending render. When fast words arrive during the interval,
                // sample the newest state at its end instead of queuing old pictures.
                try await Task.sleep(until: nextAttempt, clock: .continuous)
                try Task.checkCancellation()
                guard let requested = currentScene() else { catchUp = true; return }
                guard let layer = requested.content.foreground(for: requested.size, scale: requested.scale)
                else { throw WallpaperError.render }
                let data = try await renderer.composite(layer.image, in: layer.rect,
                    over: files.picture(configuration.pictureSlot), size: requested.size,
                    constellation: requested.content.style == .constellation)
                let live = currentScene()
                catchUp = live != requested
                guard !Task.isCancelled,
                      submission.isCurrent(token, requested: requested, live: live),
                      let target = self.screen, uuid(target) == configuration.displayUUID else { return }
                let active = NSWorkspace.shared.desktopImageURL(for: target)
                guard let url = try files.writeFrame(data, after: active, pictureSlot: configuration.pictureSlot)
                else { return }
                hasFrames = true
                needsFileCleanup = true
                try apply(url, on: target)
                lastFrame = requested
                // Give the system time to finish loading and transitioning to this
                // picture before sampling the next sung word.
                nextAttempt = .now + .seconds(max(0.50, Double(data.count) / 900_000))
                status = ""
                log.info("Submitted a new lock-screen lyric picture")
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
        let firstRestore = lastFrame != nil
        lastFrame = nil
        let now = ContinuousClock.now
        if firstRestore {
            renderer = WallpaperRenderer()
            nextAttempt = now
            nextRestoreAttempt = now
            verifyUntil = now + .seconds(5)
        }
        if let until = verifyUntil, now >= until { verifyUntil = nil }
        guard enabled || hasFrames || verifyUntil != nil else { timer = nil; return }
        guard hasFrames || verifyUntil != nil || now >= nextDesktopCheck else { return }
        nextDesktopCheck = now + .seconds(8)
        guard let configuration else { return }
        let target = screen
        let workspace = NSWorkspace.shared
        let current = target.flatMap { workspace.desktopImageURL(for: $0) }
        if files.isFrame(current) { hasFrames = true }
        guard hasFrames else { return }

        var restored = false
        do {
            if let target, let current, now >= nextRestoreAttempt {
                nextRestoreAttempt = now + .seconds(1)
                // The getter can still report our baseline immediately after a frame
                // submission. Queue the baseline again if the lock just ended.
                if firstRestore && files.isPicture(current, slot: configuration.pictureSlot) {
                    try apply(files.picture(configuration.pictureSlot), on: target)
                }
                restored = try files.restorePicture(configuration.pictureSlot, current: {
                    workspace.desktopImageURL(for: target)
                }, apply: { picture in
                    try self.apply(picture, on: target)
                    log.info("Restored selected desktop picture")
                })
            }
        } catch {
            status = "Couldn’t restore your picture. VerseGlass will retry when the display is available."
        }
        // Erase lyric bytes even when the display is disconnected or macOS still
        // reports the previous URL. Only the desktop selection itself needs a retry.
        do {
            if needsFileCleanup {
                try files.clearLyrics(using: configuration.pictureSlot, keeping: current)
                needsFileCleanup = false
            }
            hasFrames = !restored
        } catch {
            status = "Couldn’t clear the last lyric pictures. VerseGlass will retry."
        }
    }
}
