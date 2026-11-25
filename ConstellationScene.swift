import SwiftUI

/// Two lyric lines share a sheet of stars. Its layout depends on the song and
/// lyric position so that seeking, or joining playback in the saver, is exact.
struct ConstellationPhrase {
    static let capacity = 12
    let words: [String]
    let firstLine: Int
    let page: Int
    let seed: UInt32
    let isLineEnding: Bool

    init?(frame: LyricFrame) {
        guard frame.lines.indices.contains(frame.lineIndex), frame.wordIndex >= 0 else { return nil }
        let current = frame.lines[frame.lineIndex].split(whereSeparator: \.isWhitespace)
        guard !current.isEmpty else { return nil }
        let end = min(frame.wordIndex, current.count - 1)
        let line = frame.firstLineNumber + frame.lineIndex
        let continues = !line.isMultiple(of: 2) && frame.lineIndex > 0 && !frame.lines[frame.lineIndex - 1].isEmpty
        let start = frame.lineIndex - (continues ? 1 : 0)
        firstLine = frame.firstLineNumber + start
        let previous = continues ? frame.lines[start].split(whereSeparator: \.isWhitespace) : []
        let count = previous.count + end + 1
        page = (count - 1) / Self.capacity
        let offset = page * Self.capacity
        words = (previous.dropFirst(offset) + current.prefix(end + 1).dropFirst(max(0, offset - previous.count))).map(String.init)
        let key = "\(frame.title)\u{1f}\(frame.artist)\u{1f}\(firstLine)\u{1f}\(page)"
        seed = key.utf8.reduce(2_166_136_261) { ($0 ^ UInt32($1)) &* 16_777_619 }
        isLineEnding = end == current.count - 1
    }

    // The route crosses itself while leaving room underneath each point for
    // a label. Each phrase picks a starting point, direction and reflection.
    private static let anchors: [CGPoint] = [
        .init(x: 110, y: 78), .init(x: 435, y: 201), .init(x: 282, y: 117),
        .init(x: 495, y: 58), .init(x: 189, y: 225), .init(x: 83, y: 147),
        .init(x: 390, y: 85), .init(x: 268, y: 209), .init(x: 505, y: 160),
        .init(x: 196, y: 108), .init(x: 351, y: 164), .init(x: 313, y: 52)
    ]

    func point(at index: Int) -> CGPoint {
        let direction = seed & 1 == 0 ? 1 : -1
        let first = Int((seed >> 4) % UInt32(Self.capacity))
        let point = Self.anchors[(first + direction * index + Self.capacity) % Self.capacity]
        return CGPoint(x: seed & 2 == 0 ? point.x : 600 - point.x,
                       y: seed & 4 == 0 ? point.y : 280 - point.y)
    }
}

struct ConstellationScene: View {
    let frame: LyricFrame
    let fontName: String
    let accent: Color
    @Environment(\.self) private var environment
    @Environment(\.lyricPrimary) private var primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let phrase = ConstellationPhrase(frame: frame) {
            field(phrase).id(phrase.seed)
        }
    }

    private func field(_ phrase: ConstellationPhrase) -> some View {
        let last = phrase.words.count - 1
        let ivory = blend(primary, with: Color(hex: "FFF0CE"), amount: 0.46)
        let light = blend(ivory, with: accent, amount: 0.15)
        return ZStack(alignment: .topLeading) {
            ForEach(phrase.words.indices.dropFirst(), id: \.self) { i in
                StarLink(start: phrase.point(at: i - 1), end: phrase.point(at: i))
                    .stroke(light.opacity(i == last ? 0.83 : 0.56), lineWidth: i == last ? 0.75 : 0.52)
                    .transition(.opacity)
            }
            ForEach(phrase.words.indices, id: \.self) { i in
                let current = i == last
                let word = phrase.words[i]
                let prominent = current && (phrase.isLineEnding || (word.count >= 4 && i % 3 != 1))
                let point = phrase.point(at: i)
                let radius: CGFloat = current ? 13 : 2.2
                ZStack {
                    if current {
                        Circle().stroke(ivory.opacity(0.84), lineWidth: 0.8)
                            .frame(width: 2 * radius, height: 2 * radius)
                    }
                    StarPoint().fill(ivory)
                        .frame(width: current ? 11 : 4.4, height: current ? 13 : 5.4)
                }
                .position(point)
                Text(verbatim: word)
                    .font(type(prominent ? 41 : current ? 22 : 9, current: current, prominent: prominent))
                    .tracking(prominent ? -1.5 : 0)
                    .foregroundStyle(current ? ivory : ivory.opacity(0.83))
                    .lineLimit(1)
                    .minimumScaleFactor(0.32)
                    .frame(width: min(current ? 242 : 98, 2 * min(point.x - 4, 596 - point.x)))
                    .position(x: point.x, y: point.y + (prominent ? 37 : current ? 28 : 10))
                    .zIndex(current ? 2 : 1)
            }
        }
        .frame(width: 600, height: 320)
        .shadow(color: .black.opacity(0.59), radius: 2, y: 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: last)
    }

    private func blend(_ base: Color, with tint: Color, amount: Float) -> Color {
        let a = base.resolve(in: environment), b = tint.resolve(in: environment)
        func mix(_ x: Float, _ y: Float) -> Double { Double(x + (y - x) * amount) }
        return Color(.sRGB, red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue))
    }

    private func type(_ size: CGFloat, current: Bool, prominent: Bool) -> Font {
        let weight: Font.Weight = prominent ? .heavy : current ? .semibold : .medium
        let font: Font
        switch fontName {
        case "SF Pro", "": font = .system(size: size, weight: weight).width(prominent ? .condensed : .standard)
        case "SF Rounded": font = .system(size: size, weight: weight, design: .rounded)
        case "New York": font = .system(size: size, weight: weight, design: .serif)
        default: font = .custom(fontName, fixedSize: size).weight(weight)
        }
        return prominent ? font.italic() : font
    }
}

private struct StarLink: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
    }
}

private struct StarPoint: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.midX, y = rect.midY
        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            for corner in [CGPoint(x: rect.maxX, y: y), CGPoint(x: x, y: rect.maxY),
                           CGPoint(x: 0, y: y), CGPoint(x: x, y: 0)] {
                path.addQuadCurve(to: corner, control: CGPoint(x: x, y: y))
            }
            path.closeSubpath()
        }
    }
}
