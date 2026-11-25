import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct VerseGlassPadApp: App {
    var body: some Scene {
        WindowGroup { PadStage() }
    }
}

private struct PadStage: View {
    @StateObject private var player = PadPlayer()
    @AppStorage("padStyle") private var styleName = Style.constellation.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fullScreen = false
    @State private var importing = false
    @State private var attachingTo: PlaybackTrack?
    @State private var seeking: Double?
    @State private var confirmLookup = false

    private let accent = Color(hex: "F2AA98")
    private var style: Style { Style(rawValue: styleName) ?? .constellation }

    var body: some View {
        let frame = player.frame
        ZStack {
            background
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                if !fullScreen { header }
                GeometryReader { geometry in
                    ZStack {
                        if player.status.isEmpty {
                            LyricScene(frame: frame, style: style, size: 40, fontName: "SF Pro", accent: accent)
                        } else {
                            VStack(spacing: 16) {
                                Text(player.status)
                                    .font(.title3.weight(.medium))
                                    .multilineTextAlignment(.center)
                                if player.canImportLyrics {
                                    Button("Import Synced Lyrics") { selectFile(for: player.lyricTarget) }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(24)
                        }
                    }
                    .frame(width: min(geometry.size.width, 870), height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                if !fullScreen { transport }
            }
            if style == .constellation {
                PadEdgeLight(line: frame.lineIndex, word: frame.wordIndex, playing: player.isPlaying)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if fullScreen {
                Button { fullScreen = false } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .accessibilityLabel("Exit full screen")
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .preferredColorScheme(.dark)
        .tint(accent)
        .statusBarHidden(fullScreen)
        .fileImporter(isPresented: $importing, allowedContentTypes: attachingTo == nil ? [.audio] : [.item]) { result in
            do {
                let url = try result.get()
                if let attachingTo { player.importLyrics(url, for: attachingTo) }
                else { Task { await player.openAudio(url) } }
            } catch {
                if (error as NSError).code != NSUserCancelledError { player.errorMessage = error.localizedDescription }
            }
        }
        .alert("VerseGlass", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK") { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
        .confirmationDialog("Look up Apple Music lyrics online?", isPresented: $confirmLookup, titleVisibility: .visible) {
            Button("Enable Online Lookup") { player.onlineLyrics = true }
        } message: {
            Text("VerseGlass uses the song title, artist, album and duration to find synced lyrics through Apple, AMLL and LRCLIB.")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                player.tick()
                try? await Task.sleep(for: .milliseconds(player.isPlaying ? 80 : 250))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { player.backgrounded() }
            UIApplication.shared.isIdleTimerDisabled = phase == .active && player.isPlaying
        }
        .onChange(of: player.isPlaying, initial: true) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && playing
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder private var background: some View {
        if style == .constellation {
            ConstellationBackdrop(artwork: player.artwork, showsClock: fullScreen)
        } else {
            LinearGradient(colors: [Color(hex: "262124"), Color(hex: "111115"), Color(hex: "16151A")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("VerseGlass")
                .font(.title3.weight(.semibold))
                .tracking(-0.6)
            Spacer()
            Menu {
                Button("Open Audio File", systemImage: "folder") { selectFile(for: nil) }
                Button("Follow Apple Music", systemImage: "music.note") { Task { await player.followMusic() } }
                Button("Play Demo", systemImage: "sparkles") { player.playDemo() }
                Divider()
                Button("Import Synced Lyrics", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    selectFile(for: player.lyricTarget)
                }
                .disabled(!player.canImportLyrics)
                Button {
                    if player.onlineLyrics { player.onlineLyrics = false } else { confirmLookup = true }
                } label: {
                    Label(player.onlineLyrics ? "Disable Online Lookup" : "Enable Online Lookup",
                          systemImage: player.onlineLyrics ? "checkmark.icloud" : "icloud")
                }
            } label: { toolIcon("music.note.list", title: "Music") }
            .accessibilityLabel("Music source")
            Menu {
                Picker("Lyric style", selection: $styleName) {
                    ForEach(Style.allCases) { item in Text(item.rawValue).tag(item.rawValue) }
                }
            } label: { toolIcon("paintpalette", title: "Style") }
            .accessibilityLabel("Lyric style")
            Button { fullScreen = true } label: { toolIcon("arrow.up.left.and.arrow.down.right") }
                .accessibilityLabel("Enter full screen")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func toolIcon(_ symbol: String, title: String? = nil) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            if sizeClass == .regular, let title { Text(title) }
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 6)
        .frame(minWidth: 44, minHeight: 44)
    }

    private var transport: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).font(.headline).lineLimit(1)
                    if !player.artist.isEmpty {
                        Text(player.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.black)
                        .background(.white, in: .circle)
                }
                .disabled(player.source == .music && !player.canImportLyrics)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            HStack(spacing: 12) {
                Text(timeString(seeking ?? player.position))
                Slider(value: Binding(get: { seeking ?? player.position }, set: { seeking = $0 }),
                       in: 0...max(0.01, player.duration), onEditingChanged: { editing in
                    if !editing, let target = seeking { player.seek(to: target); seeking = nil }
                })
                .disabled(player.duration <= 0)
                .accessibilityLabel("Playback position")
                .accessibilityValue(timeString(seeking ?? player.position))
                .accessibilityAdjustableAction { direction in
                    player.seek(to: player.position + (direction == .increment ? 5 : -5))
                }
                Text(timeString(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 650)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func selectFile(for song: PlaybackTrack?) {
        attachingTo = song
        importing = true
    }

    private func timeString(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// The iPad can follow lyric timestamps for both local files and Apple Music.
private struct PadEdgeLight: View {
    var line: Int
    var word: Int
    var playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if playing {
            if reduceMotion {
                rim(level: 0.35)
            } else {
                Color.clear.keyframeAnimator(initialValue: 0.0, trigger: [line, word]) { _, pulse in
                    rim(level: pulse)
                } keyframes: { _ in
                    LinearKeyframe(0.85, duration: 0.08)
                    CubicKeyframe(0, duration: 0.45)
                }
            }
        }
    }

    private func rim(level: Double) -> some View {
        SaverGlow(rim: SaverRim(enabled: true, level: level, primary: "CEAAF8", secondary: "FFE9CA",
                                 thickness: 0.9, glow: 0.43))
    }
}
