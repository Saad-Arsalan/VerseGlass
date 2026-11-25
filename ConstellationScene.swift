import SwiftUI

/// Two lyric lines share a sheet of stars. Its layout depends on the song and
/// lyric position so that seeking, or joining playback in the saver, is exact.
struct ConstellationPhrase: Equatable {
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
    private let phrase: ConstellationPhrase?
    let fontName: String
    let accent: Color
    let layoutScale: CGFloat
    @Environment(\.pixelLength) private var pixel
    @Environment(\.self) private var environment
    @Environment(\.lyricPrimary) private var primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(frame: LyricFrame, fontName: String, accent: Color, layoutScale: CGFloat) {
        phrase = ConstellationPhrase(frame: frame)
        self.fontName = fontName
        self.accent = accent
        self.layoutScale = layoutScale
    }

    var body: some View {
        if layoutScale > 0, let phrase {
            field(phrase).id(phrase.seed)
        }
    }

    private func field(_ phrase: ConstellationPhrase) -> some View {
        let last = phrase.words.count - 1
        let points = phrase.words.indices.map { index in
            let point = phrase.point(at: index)
            return CGPoint(x: point.x * layoutScale, y: point.y * layoutScale)
        }
        let ivory = blend(primary, with: Color(hex: "FFF0CE"), amount: 0.46)
        let light = blend(ivory, with: accent, amount: 0.15)
        return ZStack(alignment: .topLeading) {
            ForEach(phrase.words.indices, id: \.self) { i in
                let current = i == last
                ZStack {
                    if current {
                        Circle().stroke(ivory.opacity(0.84), lineWidth: 0.8 * layoutScale)
                            .frame(width: 26 * layoutScale, height: 26 * layoutScale)
                    }
                    StarPoint().fill(ivory)
                        .frame(width: (current ? 11 : 4.4) * layoutScale, height: (current ? 13 : 5.4) * layoutScale)
                }
                .position(points[i])
            }
            ConstellationLabels(points: points, scale: layoutScale, pixel: pixel) {
                ForEach(phrase.words.indices, id: \.self) { i in
                    let current = i == last
                    let word = phrase.words[i]
                    let prominent = current && (phrase.isLineEnding || (word.count >= 4 && i % 3 != 1))
                    Text(verbatim: word)
                        .font(type((prominent ? 41 : current ? 23 : 11.5) * layoutScale, current: current, prominent: prominent))
                        .tracking((prominent ? -1.05 : current ? 0 : 0.08) * layoutScale)
                        .foregroundStyle(current ? ivory : ivory.opacity(0.91))
                        .lineLimit(current && word.count > 24 ? 2 : 1)
                        .minimumScaleFactor(0.4)
                        .multilineTextAlignment(.center)
                        .anchorPreference(key: ConstellationWordBounds.self, value: .bounds) { [$0] }
                        .shadow(color: .black.opacity(0.50), radius: 0.8 * layoutScale, y: 0.8 * layoutScale)
                        .zIndex(current ? 1 : 0)
                }
            }
        }
        .frame(width: 600 * layoutScale, height: 320 * layoutScale)
        .backgroundPreferenceValue(ConstellationWordBounds.self) { anchors in
            GeometryReader { geometry in
                let letters = Path { path in
                    for anchor in anchors {
                        path.addRect(geometry[anchor].insetBy(dx: -3 * layoutScale, dy: -layoutScale))
                    }
                }
                ForEach(points.indices.dropFirst(), id: \.self) { i in
                    StarLink(start: points[i - 1], end: points[i], excluding: letters)
                        .stroke(light.opacity(i == last ? 0.83 : 0.56), lineWidth: (i == last ? 0.75 : 0.52) * layoutScale)
                        .transition(.opacity)
                }
            }
        }
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

// Place the sung word first. Trail labels can tuck above or beside a star
// when the usual position below it is occupied. Measure the actual chosen font.
private struct ConstellationLabels: Layout {
    let points: [CGPoint]
    let scale: CGFloat
    let pixel: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 600 * scale, height: 320 * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard points.count == subviews.count else { return }
        let field = bounds.insetBy(dx: 5 * scale, dy: 4 * scale)
        let last = points.count - 1
        var occupied = points.indices.map { i in
            let radius = (i == last ? 13 : 3) * scale
            return CGRect(x: bounds.minX + points[i].x - radius, y: bounds.minY + points[i].y - radius,
                          width: 2 * radius, height: 2 * radius)
        }

        for i in subviews.indices.reversed() {
            let width = min(field.width, (i == last ? 360 : 110) * scale)
            let fit = ProposedViewSize(width: width, height: nil)
            let size = subviews[i].sizeThatFits(fit)
            let gap = (i == last ? 16 : 5) * scale
            let x = bounds.minX + points[i].x
            let y = bounds.minY + points[i].y
            let origins = [
                CGPoint(x: x - size.width / 2, y: y + gap),
                CGPoint(x: x - size.width / 2, y: y - gap - size.height),
                CGPoint(x: x + gap, y: y - size.height / 2),
                CGPoint(x: x - gap - size.width, y: y - size.height / 2)
            ]
            var best = CGRect.zero
            var leastOverlap = CGFloat.infinity
            for origin in origins {
                let left = min(max(origin.x, field.minX), field.maxX - size.width)
                let top = min(max(origin.y, field.minY), field.maxY - size.height)
                let rect = CGRect(x: (left / pixel).rounded() * pixel, y: (top / pixel).rounded() * pixel,
                                  width: size.width, height: size.height)
                let overlap = occupied.reduce(CGFloat.zero) { total, other in
                    let intersection = rect.intersection(other)
                    return total + intersection.width * intersection.height
                }
                if overlap < leastOverlap {
                    best = rect
                    leastOverlap = overlap
                    if overlap == 0 { break }
                }
            }
            subviews[i].place(at: best.origin, anchor: .topLeading, proposal: fit)
            occupied.append(best.insetBy(dx: -2 * scale, dy: -1.5 * scale))
        }
    }
}

private struct ConstellationWordBounds: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct StarLink: Shape {
    let start: CGPoint
    let end: CGPoint
    let excluding: Path
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }.lineSubtraction(excluding)
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
