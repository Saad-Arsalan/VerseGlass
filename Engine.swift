import AppKit
import Combine

@MainActor
final class Engine: ObservableObject {
    @Published private(set) var frame: LyricFrame = .empty
    @Published private(set) var status = "Play a song in Spotify or Apple Music."
    @Published private(set) var spotifyStatus = "Not running"
    @Published private(set) var musicStatus = "Not running"
    @Published private(set) var playing = false
    @Published private(set) var activeSource: MusicSource?
    @Published private(set) var artworkURL: URL?
    @Published var timingOffset = 0.0 { didSet { render() } }
    @Published var onlineLookup: Bool = (UserDefaults.standard.object(forKey: "onlineLyricsLookup") as? Bool) ?? true {
        didSet {
            guard onlineLookup != oldValue else { return }
            UserDefaults.standard.set(onlineLookup, forKey: "onlineLyricsLookup")
            if let track = current.track { load(track) }
        }
    }

    private let spotify = PlayerProbe(.spotify)
    private let music = PlayerProbe(.music)
    private let store = LyricsStore()
    private var current = PlayerReading()
    private var lyrics: TimedLyrics?
    var hasTimedLyrics: Bool { lyrics != nil }
    private var monitor: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var fetch: Task<Void, Never>?
    private var previousPlayers: Set<MusicSource> = []
    private var retryAfter: Date?

    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                let animating = self?.playing == true && self?.lyrics != nil
                if animating { self?.render() }
                try? await Task.sleep(for: .milliseconds(animating ? 80 : 600))
            }
        }
    }

    deinit { monitor?.cancel(); clock?.cancel(); fetch?.cancel() }

    private func poll() async {
        func pid(_ source: MusicSource) -> pid_t? {
            NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first(where: { !$0.isTerminated })?.processIdentifier
        }
        let spotifyPID = pid(.spotify), musicPID = pid(.music)
        async let s = spotify.read(spotifyPID)
        async let m = music.read(musicPID)
        let (sResult, mResult) = await (s, m)
        if spotifyStatus != sResult.status { spotifyStatus = sResult.status }
        if musicStatus != mResult.status { musicStatus = mResult.status }
        let players = [sResult, mResult].filter { $0.track != nil }
        let active = players.filter(\.playing)
        let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let next = active.first(where: { !previousPlayers.contains($0.track!.source) && $0.track!.source.bundleID == foreground })
            ?? active.first(where: { !previousPlayers.contains($0.track!.source) })
            ?? active.first(where: { $0.track?.source == current.track?.source })
            ?? active.first ?? players.first(where: { $0.track?.source == current.track?.source }) ?? players.first
        previousPlayers = Set(active.compactMap { $0.track?.source })
        let changed = current.track != next?.track
        current = next ?? PlayerReading()
        if activeSource != current.track?.source { activeSource = current.track?.source }
        if current.playing != playing { playing = current.playing }
        if changed {
            lyrics = nil
            timingOffset = 0
            if let track = current.track { load(track) }
            else { fetch?.cancel(); retryAfter = nil; artworkURL = nil; frame = .empty }
        } else if let retryAfter, retryAfter <= Date(), let track = current.track {
            load(track)
        }
        if current.track == nil {
            let message = [sResult, mResult].contains(where: { $0.status.hasPrefix("Allow") })
                ? "Allow this app to control your music player in System Settings → Privacy & Security → Automation."
                : "Play a song in Spotify or Apple Music."
            if status != message { status = message }
        } else { render() }
    }

    private func load(_ track: PlaybackTrack) {
        fetch?.cancel()
        retryAfter = nil
        artworkURL = onlineLookup ? track.artwork : nil
        if let saved = store.cached(track), apply(saved) { return }
        guard onlineLookup else {
            lyrics = nil
            status = "Offline. Import an LRC or enable online lookup for this song."
            render()
            return
        }
        status = "Looking up lyrics…"
        fetch = Task { [weak self, store] in
            do {
                let result = try await store.lookup(track)
                guard !Task.isCancelled, let self, current.track == track else { return }
                if apply(result) {
                    do { try store.save(result, for: track) }
                    catch { status += " · Couldn’t save the offline copy." }
                }
            } catch {
                guard !Task.isCancelled, let self, current.track == track else { return }
                let failure = error as? LookupError ?? .network
                status = failure.localizedDescription
                switch failure {
                case .network, .limited: retryAfter = Date().addingTimeInterval(60)
                default: break
                }
            }
        }
    }

    @discardableResult
    private func apply(_ record: SavedLyrics) -> Bool {
        guard let timed = TimedLyrics(record.content) else { return false }
        lyrics = timed
        retryAfter = nil
        artworkURL = onlineLookup ? record.artwork ?? current.track?.artwork : nil
        status = record.source + (timed.hasWordTiming ? " · Word timestamps" : " · Line timestamps, estimated words")
        render()
        return true
    }

    func importLyrics(_ url: URL) {
        guard let track = current.track else { status = "Play or pause the song you want to attach this file to first."; return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000 else { status = "This lyric file exceeds 2 MB."; return }
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            let record = SavedLyrics(content: text, source: "Imported LRC", artwork: artworkURL)
            guard apply(record) else { status = "This file has no timestamped lyrics. Choose a synced LRC file."; return }
            fetch?.cancel()
            try store.save(record, for: track)
        } catch { status = "Lyric file error · " + error.localizedDescription }
    }

    private func render() {
        guard let track = current.track else { return }
        let drift = current.playing ? max(0, ProcessInfo.processInfo.systemUptime - current.sampled) : 0
        let position = current.position + drift + timingOffset
        let next = lyrics?.frame(at: position, duration: track.duration, title: track.title, artist: track.artist)
            ?? LyricFrame(title: track.title, artist: track.artist, lines: [], lineIndex: 0, wordIndex: 0, progress: 0)
        if frame.title != next.title || frame.artist != next.artist || frame.lineIndex != next.lineIndex
            || frame.wordIndex != next.wordIndex || frame.progress != next.progress || frame.lines != next.lines {
            frame = next
        }
    }
}
