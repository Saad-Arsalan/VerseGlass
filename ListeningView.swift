import AppKit
import SwiftUI

@MainActor
struct ListeningView: View {
    private enum Content: String { case lyrics, cover }

    @ObservedObject var engine: Engine
    @ObservedObject var prefs: Preferences
    let close: () -> Void
    @AppStorage("listeningContent") private var content: Content = .lyrics

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if prefs.style == .constellation && content == .lyrics {
                    ConstellationBackdrop(showsClock: false)
                } else {
                    Color(white: 0.065)
                }
                if engine.frame.title.isEmpty {
                    message(engine.status)
                } else if content == .cover {
                    if let cover = prefs.listeningCover {
                        Image(nsImage: cover).resizable().interpolation(.high).scaledToFit()
                            .padding(30)
                            .accessibilityLabel("Album cover for " + engine.frame.title)
                    } else {
                        message("Album artwork unavailable")
                    }
                } else if engine.frame.lines.indices.contains(engine.frame.lineIndex) {
                    LyricScene(frame: engine.frame, style: prefs.style, size: CGFloat(prefs.textSize),
                               fontName: prefs.fontName, accent: prefs.effectiveAccent)
                        .environment(\.lyricPrimary, Color(hex: prefs.primaryHex))
                        .environment(\.lyricSecondary, Color(hex: prefs.secondaryHex))
                        .padding(.horizontal, 16)
                } else if !engine.hasTimedLyrics {
                    message(engine.status)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                if !engine.frame.title.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.frame.title).font(.headline)
                        if !engine.frame.artist.isEmpty {
                            Text(engine.frame.artist).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    if !engine.playing {
                        Image(systemName: "pause.fill").foregroundStyle(.secondary)
                            .accessibilityLabel("Paused").help("Paused")
                    }
                }
                Spacer(minLength: 8)
                Picker("Display", selection: $content) {
                    Text("Lyrics").tag(Content.lyrics)
                    Text("Album Cover").tag(Content.cover)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 22)
            .frame(height: 62)
            .background(Color(white: 0.085))
        }
        .preferredColorScheme(.dark)
        .onExitCommand(perform: close)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.title3).foregroundStyle(.white.opacity(0.84))
            .multilineTextAlignment(.center).frame(maxWidth: 420).padding(24)
    }
}
