import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class PadPlayer: ObservableObject {
    enum Source { case demo, file, music }

    @Published private(set) var source = Source.demo
    @Published private(set) var title = "Blue Hour"
    @Published private(set) var artist = "VerseGlass · Silent demo"
    @Published private(set) var position: Double = 0
    @Published private(set) var duration = Double(LyricFrame.sample.count) * 3
    @Published private(set) var isPlaying = true
    @Published private(set) var status = ""
    @Published private(set) var timedLyrics: TimedLyrics?
    @Published private(set) var artwork: Data?
    @Published var errorMessage: String?
    @Published var onlineLyrics = UserDefaults.standard.bool(forKey: "padOnlineLyrics") {
        didSet {
            UserDefaults.standard.set(onlineLyrics, forKey: "padOnlineLyrics")
            if source == .music, let track { loadLyrics(for: track) }
        }
    }

    private let store = LyricsStore()
    private var audio: AVPlayer?
    private var scopedAudio: URL?
    private var audioSessionActive = false
    private var music: MPMusicPlayerController?
    private var track: PlaybackTrack?
    private var sourceRequest = UUID()
    private var lookup: Task<Void, Never>?
    private var retryAt: Date?
    private var sampleTime = ProcessInfo.processInfo.systemUptime
    private var samplePosition = 0.0

    deinit {
        lookup?.cancel()
        scopedAudio?.stopAccessingSecurityScopedResource()
    }

    var canImportLyrics: Bool { track != nil }
    var frame: LyricFrame {
        if source == .demo { return .demo(at: position) }
        return timedLyrics?.frame(at: position, duration: duration, title: title, artist: artist) ?? .empty
    }

    func playDemo() {
        sourceRequest = UUID()
        resetSource()
        source = .demo
        title = "Blue Hour"
        artist = "VerseGlass · Silent demo"
        duration = Double(LyricFrame.sample.count) * 3
        isPlaying = true
    }

    func openAudio(_ url: URL) async {
        let request = UUID()
        sourceRequest = request
        let scoped = url.startAccessingSecurityScopedResource()
        var transferScope = false
        defer { if scoped && !transferScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let seconds = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard sourceRequest == request else { return }
            guard playable, seconds.isFinite, seconds > 0, !tracks.isEmpty else {
                errorMessage = "Choose a playable audio file with a known duration."
                return
            }
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            func item(_ key: AVMetadataKey) -> AVMetadataItem? {
                metadata.first { $0.commonKey == key }
            }
            let name = try? await item(.commonKeyTitle)?.load(.stringValue)
            let performer = try? await item(.commonKeyArtist)?.load(.stringValue)
            let album = try? await item(.commonKeyAlbumName)?.load(.stringValue)
            let cover = try? await item(.commonKeyArtwork)?.load(.dataValue)
            guard sourceRequest == request else { return }
            resetSource()
            scopedAudio = scoped ? url : nil
            transferScope = true
            audio = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            source = .file
            duration = seconds
            title = name.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
            artist = performer ?? "Audio file"
            artwork = cover
            let local = PlaybackTrack(source: .music, id: "", title: title, artist: artist,
                                      album: album ?? "", duration: seconds, artwork: nil)
            track = local
            loadLyrics(for: local)
            playFile()
        } catch {
            if sourceRequest == request { errorMessage = "Couldn’t open the audio file. " + error.localizedDescription }
        }
    }

    func followMusic() async {
        let request = UUID()
        sourceRequest = request
        let permission = await MPMediaLibrary.requestAuthorization()
        guard sourceRequest == request else { return }
        guard permission == .authorized else {
            errorMessage = "Allow media library access in Settings to follow Apple Music. You can also open an audio file."
            return
        }
        resetSource()
        source = .music
        title = "Apple Music"
        artist = ""
        status = "Play a song in Music, then return to VerseGlass."
        music = MPMusicPlayerController.systemMusicPlayer
        sampleMusic()
    }

    // The importer captures the displayed song, since Music can change tracks
    // while the user is browsing Files.
    var lyricTarget: PlaybackTrack? { track }

    func importLyrics(_ url: URL, for target: PlaybackTrack) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: 2_000_001) ?? Data()
            guard data.count <= 2_000_000 else { errorMessage = "Choose a lyric file smaller than 2 MB."; return }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            guard let parsed = TimedLyrics(text) else {
                errorMessage = "Choose a synced LRC or enhanced LRC file with timestamps."
                return
            }
            if track == target {
                lookup?.cancel()
                retryAt = nil
                timedLyrics = parsed
                status = ""
            }
            try store.save(SavedLyrics(content: text, source: "Imported LRC", artwork: nil), for: target)
        } catch { errorMessage = error.localizedDescription }
    }

    func togglePlayback() {
        switch source {
        case .demo:
            tick()
            anchor(at: position)
            isPlaying.toggle()
        case .file:
            if isPlaying { audio?.pause(); isPlaying = false }
            else {
                if position >= duration - 0.05 { seek(to: 0) }
                playFile()
            }
        case .music:
            guard track != nil else { return }
            if isPlaying { music?.pause() } else { music?.play() }
            sampleMusic()
        }
    }

    func seek(to seconds: Double) {
        let value = min(max(0, seconds), duration)
        anchor(at: value)
        switch source {
        case .demo: break
        case .file: audio?.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case .music: music?.currentPlaybackTime = value
        }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        switch source {
        case .demo:
            if isPlaying {
                position = (samplePosition + now - sampleTime).truncatingRemainder(dividingBy: duration)
            }
        case .file:
            guard let audio else { return }
            let seconds = audio.currentTime().seconds
            if seconds.isFinite { position = min(duration, max(0, seconds)) }
            if audio.currentItem?.status == .failed {
                let message = audio.currentItem?.error?.localizedDescription ?? "Couldn’t play this audio file."
                if status != message { status = message; errorMessage = message }
            }
            isPlaying = audio.timeControlStatus != .paused
        case .music:
            if now - sampleTime >= 0.45 { sampleMusic() }
            else if isPlaying { position = min(duration, samplePosition + now - sampleTime) }
            if let retryAt, retryAt <= Date(), let track { loadLyrics(for: track) }
        }
    }

    func backgrounded() {
        if source == .file {
            audio?.pause()
            isPlaying = false
            releaseAudioSession()
        }
    }

    private func sampleMusic() {
        guard let music else { return }
        let item = music.nowPlayingItem
        let next: PlaybackTrack? = item.flatMap {
            guard let title = $0.title, !title.isEmpty else { return nil }
            let seconds = $0.playbackDuration
            return PlaybackTrack(source: .music, id: String($0.persistentID), title: title,
                                 artist: $0.artist ?? "", album: $0.albumTitle ?? "",
                                 duration: seconds.isFinite ? max(0, seconds) : 0, artwork: nil)
        }
        if next != track {
            lookup?.cancel()
            retryAt = nil
            track = next
            timedLyrics = nil
            duration = next?.duration ?? 0
            title = next?.title ?? "Apple Music"
            artist = next?.artist ?? ""
            artwork = item?.artwork?.image(at: CGSize(width: 192, height: 192))?.jpegData(compressionQuality: 0.8)
            if let next { loadLyrics(for: next) }
            else { status = "Play a song in Music, then return to VerseGlass." }
        }
        isPlaying = next != nil && music.playbackState == .playing
        let seconds = music.currentPlaybackTime
        anchor(at: seconds.isFinite ? min(duration, max(0, seconds)) : 0)
    }

    private func loadLyrics(for song: PlaybackTrack) {
        lookup?.cancel()
        retryAt = nil
        if let saved = store.cached(song), let parsed = TimedLyrics(saved.content) {
            timedLyrics = parsed
            status = ""
            return
        }
        timedLyrics = nil
        guard source == .music && onlineLyrics else {
            status = source == .file ? "Import synced lyrics for this recording." : "Import synced lyrics or enable online lookup."
            return
        }
        status = "Finding synced lyrics…"
        lookup = Task { [weak self, store] in
            do {
                let result = try await store.lookup(song)
                guard !Task.isCancelled, let self, self.track == song else { return }
                self.timedLyrics = TimedLyrics(result.content)
                self.status = self.timedLyrics == nil ? "Import synced lyrics for this recording." : ""
                try store.save(result, for: song)
            } catch {
                guard !Task.isCancelled, let self, self.track == song else { return }
                if self.timedLyrics != nil { self.errorMessage = "Couldn’t save lyrics for offline playback."; return }
                let failure = error as? LookupError ?? .network
                self.status = failure.localizedDescription
                if failure == .network || failure == .limited { self.retryAt = Date().addingTimeInterval(60) }
            }
        }
    }

    private func anchor(at seconds: Double) {
        position = seconds
        samplePosition = seconds
        sampleTime = ProcessInfo.processInfo.systemUptime
    }

    private func playFile() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            audioSessionActive = true
            audio?.play()
            isPlaying = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func releaseAudioSession() {
        guard audioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionActive = false
    }

    private func resetSource() {
        lookup?.cancel()
        retryAt = nil
        audio?.pause()
        audio = nil
        releaseAudioSession()
        scopedAudio?.stopAccessingSecurityScopedResource()
        scopedAudio = nil
        music = nil
        artwork = nil
        track = nil
        timedLyrics = nil
        duration = 0
        anchor(at: 0)
        isPlaying = false
        status = ""
    }
}
