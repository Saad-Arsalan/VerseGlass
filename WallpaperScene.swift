import SwiftUI

/// One visible word and the nearby lines that the selected style needs.
/// Changing playback progress within the same word does not produce a new image.
struct WallpaperStyleFrame: Equatable {
    let title: String
    let artist: String
    let lines: [String]
    let firstLineNumber: Int
    let lineIndex: Int
    private let firstWordNumber: Int
    private(set) var wordIndex: Int
    let style: Style
    let fontName: String
    let textSize: Double
    let primary: String
    let secondary: String
    let accent: String
    private let wordCount: Int

    init?(frame: LyricFrame, style: Style, fontName: String, textSize: Double,
          primary: String, secondary: String, accent: String) {
        guard frame.lines.indices.contains(frame.lineIndex), frame.wordIndex >= 0 else { return nil }
        let words = frame.lines[frame.lineIndex].split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        // Keep the active word even for a long, single-line LRC cue. This page
        // size accommodates the five-, eight- and twelve-word graph layouts.
        let pageSize = 120
        let active = min(frame.wordIndex, words.count - 1)
        firstWordNumber = active / pageSize * pageSize
        wordIndex = active - firstWordNumber
        wordCount = words.count
        let first = max(0, frame.lineIndex - 3)
        firstLineNumber = frame.firstLineNumber + first
        lineIndex = frame.lineIndex - first
        var context = frame.lines[first..<frame.lineIndex].map { line in
            line.split(whereSeparator: \.isWhitespace).suffix(pageSize)
                .map { $0.prefix(200) }.joined(separator: " ")
        }
        context.append(words.dropFirst(firstWordNumber).prefix(pageSize)
            .map { $0.prefix(200) }.joined(separator: " "))
        lines = context
        title = String(frame.title.prefix(200))
        artist = String(frame.artist.prefix(200))
        self.style = style
        self.fontName = fontName
        self.textSize = textSize
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
    }

    func canFollow(_ earlier: Self) -> Bool {
        // A couple of sung words may land during encoding. A seek farther
        // ahead should replace the pending image with the new lyric position.
        guard (0...2).contains(wordIndex - earlier.wordIndex) else { return false }
        var matchedWord = self
        matchedWord.wordIndex = earlier.wordIndex
        return matchedWord == earlier
    }

    /// The destination uses Quartz's lower-left origin. Keep the complete lyric
    /// artboard between the system clock above and the sign-in controls below.
    @MainActor func foreground(for pixelSize: CGSize, scale: CGFloat) -> (image: CGImage, rect: CGRect)? {
        guard pixelSize.width > 0, pixelSize.height > 0, scale.isFinite, scale > 0 else { return nil }
        // The star labels occupy only the inner part of the artboard. Give
        // that style more space to keep its smaller trail words legible.
        let normalHeight = style == .constellation ? 0.60 : 0.47
        let maximumHeight = style == .constellation ? 0.65 : 0.56
        let normalFit = min(pixelSize.width * 0.86 / 600, pixelSize.height * normalHeight / 320)
        let safeFit = min(pixelSize.width * 0.94 / 600, pixelSize.height * maximumHeight / 320)
        let fit = min(safeFit, normalFit * max(0.25, textSize / 40))
        let width = max(1, (600 * fit).rounded())
        let height = max(1, (320 * fit).rounded())
        let rect = CGRect(x: ((pixelSize.width - width) / 2).rounded(),
                          y: (pixelSize.height * 0.475 - height / 2).rounded(), width: width, height: height)
        let logical = CGSize(width: width / scale, height: height / scale)
        let playback = LyricFrame(title: title, artist: artist, lines: lines, lineIndex: lineIndex,
                                  wordIndex: wordIndex, progress: Double(firstWordNumber + wordIndex) / Double(wordCount),
                                  firstLineNumber: firstLineNumber)
        let scene = LyricScene(frame: playback, style: style, size: 40, fontName: fontName, accent: Color(hex: accent))
            .environment(\.lyricPrimary, Color(hex: primary))
            .environment(\.lyricSecondary, Color(hex: secondary))
            .environment(\.colorScheme, .dark)
            .environment(\.displayScale, scale)
            .frame(width: logical.width, height: logical.height)
        let renderer = ImageRenderer(content: scene)
        renderer.proposedSize = ProposedViewSize(logical)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return (image, rect)
    }
}
