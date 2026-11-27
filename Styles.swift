import SwiftUI

/// A transparent artboard. A thumbnail and a full-screen overlay use the same composition.
struct LyricScene: View {
    let frame: LyricFrame
    let style: Style
    let size: CGFloat
    let fontName: String
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / 600, geometry.size.height / 320)
            let scale = fit * max(0.25, size / 40)
            if scale > 0 {
                LyricArtboard(frame: frame, style: style, fontName: fontName, accent: accent,
                             layoutScale: scale)
                    .frame(width: 600 * scale, height: 320 * scale)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .clipped()
    }
}

// Measure the composition in output points so glyphs are shaped at their displayed size.
private struct LyricArtboard: View {
    let frame: LyricFrame
    let style: Style
    let fontName: String
    let accent: Color
    let layoutScale: CGFloat

    @Environment(\.self) private var environment
    @Environment(\.lyricPrimary) private var primary
    @Environment(\.lyricSecondary) private var secondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var line: String {
        frame.lines.indices.contains(frame.lineIndex) ? frame.lines[frame.lineIndex] : ""
    }

    private var words: [String] { line.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var active: Int { min(words.count - 1, max(-1, frame.wordIndex)) }
    private var songLineNumber: Int { frame.firstLineNumber + frame.lineIndex }

    var body: some View {
        Group {
            if !line.isEmpty {
                switch style {
                case .ship, .fisheye, .visual, .fisheyeVisual:
                    kineticWords
                case .codestyle, .codestyleVisual:
                    codeScene
                case .constellation:
                    ConstellationScene(frame: frame, fontName: fontName, accent: accent, layoutScale: layoutScale)
                case .branches, .web:
                    graphScene
                case .nativeDesign:
                    messages
                case .money:
                    payments
                case .map:
                    mapCard
                case .notifications:
                    notifications
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
    }

    private func points(_ designLength: CGFloat) -> CGFloat { designLength * layoutScale }

    private func type(_ designSize: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let size = points(designSize)
        switch fontName {
        case "SF Pro", "": return .system(size: size, weight: weight)
        case "SF Rounded": return .system(size: size, weight: weight, design: .rounded)
        case "New York": return .system(size: size, weight: weight, design: .serif)
        default: return .custom(fontName, fixedSize: size).weight(weight)
        }
    }

    /// Use the lyric timestamp as the reveal cue. A new line starts with one
    /// word; as the next words land, earlier words move into the foreground.
    private var kineticWords: some View {
        let wall = style == .ship
        let lens = style == .fisheye || style == .fisheyeVisual
        let end = max(0, active + 1)
        let start = max(0, end - (wall ? 5 : 3))
        let tokens = words
        return ZStack {
            ForEach(start..<end, id: \.self) { index in
                let age = active - index
                let word = tokens[index]
                let geometry = wordPose(age: age, count: end - start, wall: wall, lens: lens)
                kineticToken(word, index: index, age: age, scale: geometry.scale)
                    .rotation3DEffect(.degrees(geometry.pitch), axis: (1, 0, 0), perspective: 0.65)
                    .opacity(geometry.opacity)
                    .offset(x: points(geometry.x), y: points(geometry.y))
                    .zIndex(Double(index))
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .offset(y: points(9)).combined(with: .scale(scale: 0.88)).combined(with: .opacity),
                        removal: .offset(y: points(-16)).combined(with: .opacity)))
            }
        }
        .frame(width: points(550), height: points(285))
        .id(songLineNumber)
        .rotation3DEffect(.degrees(wall ? (reduceMotion ? -11 : -13 + 9 * frame.progress) : 0),
                          axis: (0, 1, 0), perspective: 0.65)
        .rotationEffect(.degrees(wall ? -3 : 0))
        .shadow(color: .black.opacity(0.24), radius: points(3), y: points(2))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: active)
    }

    private typealias WordPose = (scale: CGFloat, x: CGFloat, y: CGFloat, pitch: Double, opacity: Double)

    private func wordPose(age: Int, count: Int, wall: Bool, lens: Bool) -> WordPose {
        if wall {
            let scale: [CGFloat] = [0.79, 1.02, 0.71, 0.51, 0.37]
            let positions: [CGFloat] = [79, 10, -56, -101, -134]
            let center = (positions[0] + positions[count - 1]) / 2
            return (scale[age], CGFloat(age) * -8, positions[age] - center, Double(age) * 4, 1 - Double(age) * 0.14)
        }
        if count == 1 { return (1.04, 0, 0, 0, 1) }
        // On the convex stack the middle word faces the viewer. The newest
        // word sits on the lower lip, with a sliver of the upper word visible.
        let ys: [CGFloat] = count == 2 ? [43, -32] : [76, 0, -69]
        let scales: [CGFloat] = [lens ? 0.57 : 0.64, lens ? 1.20 : 1.05, lens ? 0.54 : 0.62]
        let pitches: [Double] = [lens ? -23 : -9, 0, lens ? 32 : 17]
        return (scales[age], 0, ys[age], pitches[age], age == 2 ? 0.82 : 1)
    }

    private func kineticToken(_ word: String, index: Int, age: Int, scale: CGFloat) -> some View {
        let isNew = age == 0
        let symbol = style == .visual || style == .fisheyeVisual ? wordSymbol(word) : nil
        let trailingIcon = !index.isMultiple(of: 2)
        let ink = isNew ? highlightedInk : (age == 1 ? primary : secondary)
        let icon = Image(systemName: symbol ?? "circle")
            .font(.system(size: points(47 * scale), weight: .semibold))
            .foregroundStyle(accent)
            .fixedSize()
        return HStack(spacing: points(10 * scale)) {
            if symbol != nil && !trailingIcon { icon }
            Text(verbatim: word)
                .font(type(83 * scale, age == 1 ? .heavy : .semibold))
                .tracking(points(-3.8 * scale))
                .lineLimit(1)
                .minimumScaleFactor(0.20)
                .foregroundStyle(ink)
                .padding(.horizontal, isNew ? points(7 * scale) : 0)
                .background {
                    if isNew {
                        LyricMarker(scale: layoutScale * scale).fill(accent)
                            .padding(.vertical, points(5 * scale))
                    }
                }
            if symbol != nil && trailingIcon { icon }
        }
        .frame(width: points(515 * scale))
    }

    private var highlightedInk: Color {
        // Keep a user-selected text colour if it reads against the highlight.
        func luminance(_ color: Color) -> Double {
            let rgb = color.resolve(in: environment)
            return 0.2126 * Double(rgb.linearRed) + 0.7152 * Double(rgb.linearGreen) + 0.0722 * Double(rgb.linearBlue)
        }
        let fill = luminance(accent)
        let ink = luminance(primary)
        let contrast = (max(fill, ink) + 0.05) / (min(fill, ink) + 0.05)
        return contrast >= 3 ? primary : (fill > 0.18 ? Color(white: 0.055) : .white)
    }

    // Keep code plain and readable, even when the input has quotation marks.
    private var codeScene: some View {
        let visibleWords = words.prefix(max(0, active + 1))
        let displayed = visibleWords.enumerated().reduce(Text("")) { result, entry in
            let (index, word) = entry
            var segment = Text((index == 0 ? "" : " ") + word).foregroundColor(primary)
            if style == .codestyleVisual, let icon = wordSymbol(word) {
                segment = segment + Text(" ") + Text(Image(systemName: icon)).foregroundColor(accent)
            }
            return result + segment
        }
        return VStack(alignment: .leading, spacing: points(15)) {
            HStack(spacing: points(8)) {
                Circle().fill(accent).frame(width: points(8), height: points(8))
                Text(frame.title).foregroundStyle(secondary).lineLimit(1)
            }
            .font(.system(size: points(13), weight: .semibold, design: .monospaced))
            HStack(alignment: .top, spacing: points(14)) {
                Text(String(format: "%02d", songLineNumber + 1))
                    .font(.system(size: points(18), weight: .medium, design: .monospaced))
                    .foregroundStyle(secondary)
                VStack(alignment: .leading, spacing: points(8)) {
                    Text("lyric {")
                        .font(.system(size: points(21), weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                    TimelineView(.periodic(from: .now, by: 0.55)) { tick in
                        let visible = reduceMotion || Int(tick.date.timeIntervalSinceReferenceDate / 0.55).isMultiple(of: 2)
                        (displayed + Text(" ▌").foregroundColor(visible ? .red : .clear))
                            .lineLimit(4)
                            .minimumScaleFactor(0.55)
                    }
                    .font(fontName == "SF Pro" ? .system(size: points(32), weight: .semibold, design: .monospaced) : type(32, .semibold))
                    .padding(.leading, points(16))
                    Text("}").foregroundStyle(accent)
                        .font(.system(size: points(21), weight: .semibold, design: .monospaced))
                }
            }
        }
        .frame(width: points(420), alignment: .leading)
        .shadow(color: .black.opacity(0.4), radius: points(5), y: points(2))
    }

    private var graphScene: some View {
        let isWeb = style == .web
        let isBranch = style == .branches
        let limit = isWeb ? 8 : 5
        let first = max(0, active) / limit * limit
        let indices = Array(first..<min(words.count, first + limit))
        let nodes: [CGPoint] = indices.indices.map { i in
            if isWeb {
                let angle = Double(i) / Double(max(3, indices.count)) * 2 * .pi - .pi / 2
                return CGPoint(x: 300 + 206 * cos(angle), y: 160 + 111 * sin(angle))
            }
            let x = 300 + (CGFloat(i) - CGFloat(indices.count - 1) / 2) * 105
            let heights = [110, 193, 93, 184, 104]
            return CGPoint(x: x, y: CGFloat(heights[i]))
        }
        return ZStack {
            Canvas { context, _ in
                var drawing = context
                drawing.scaleBy(x: layoutScale, y: layoutScale)
                let center = CGPoint(x: 300, y: 160)
                if isWeb {
                    for ring in 1...4 {
                        let fraction = CGFloat(ring) / 4
                        var path = Path()
                        for (i, point) in nodes.enumerated() {
                            let end = CGPoint(x: center.x + (point.x - center.x) * fraction, y: center.y + (point.y - center.y) * fraction)
                            if i == 0 { path.move(to: end) } else { path.addLine(to: end) }
                        }
                        path.closeSubpath()
                        drawing.stroke(path, with: .color(secondary.opacity(0.3)), lineWidth: 0.9)
                    }
                }
                if isBranch, let first = nodes.first, let last = nodes.last {
                    var stem = Path()
                    stem.move(to: CGPoint(x: first.x - 40, y: 157))
                    stem.addQuadCurve(to: CGPoint(x: last.x + 34, y: 148), control: CGPoint(x: 300, y: 173))
                    drawing.stroke(stem, with: .color(secondary.opacity(0.75)), lineWidth: 2)
                }
                for (i, point) in nodes.enumerated() {
                    let lit = indices[i] <= active
                    var path = Path()
                    if isWeb {
                        path.move(to: center)
                        path.addLine(to: point)
                    } else if isBranch {
                        path.move(to: CGPoint(x: point.x - 29, y: 159))
                        path.addQuadCurve(to: point, control: CGPoint(x: point.x, y: 155))
                    }
                    drawing.stroke(path, with: .color(lit ? accent : secondary.opacity(0.43)), lineWidth: lit ? 2 : 1)
                    let radius: CGFloat = indices[i] == active ? 5 : 3
                    drawing.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(lit ? accent : secondary))
                    if indices[i] == active {
                        let halo = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
                        drawing.stroke(Path(ellipseIn: halo), with: .color(accent.opacity(0.6)), lineWidth: 1)
                    }
                }
            }
            ForEach(Array(indices.enumerated()), id: \.element) { local, index in
                let point = nodes[local]
                let lit = index == active
                Text(words[index])
                    .font(type(lit ? 25 : 18, lit ? .heavy : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
                    .frame(width: points(isWeb ? 123 : 105))
                    .foregroundStyle(lit ? accent : index < active ? primary : secondary)
                    .shadow(color: .black.opacity(0.6), radius: points(2), y: points(1))
                    .position(x: points(point.x), y: points(point.y + (point.y >= 158 ? 21 : -20)))
            }
        }
        .frame(width: points(600), height: points(320))
    }

    private var visibleLines: [Int] {
        guard frame.lines.indices.contains(frame.lineIndex) else { return [] }
        return Array((max(0, frame.lineIndex - 2)...frame.lineIndex).filter { !frame.lines[$0].isEmpty })
    }

    /// Native scenes keep their own palette. The active word still tracks playback.
    private func nativeLine(_ index: Int, bright: Color = .white, dim: Color = .white.opacity(0.67)) -> Text {
        var string = AttributedString("")
        for (i, word) in frame.lines[index].split(whereSeparator: \.isWhitespace).enumerated() {
            var span = AttributedString((i == 0 ? "" : " ") + word)
            span.foregroundColor = index != frame.lineIndex || i <= active ? bright : dim
            if index == frame.lineIndex && i == active {
                span.inlinePresentationIntent = .stronglyEmphasized
            }
            string.append(span)
        }
        return Text(string)
    }

    private var messages: some View {
        VStack(spacing: points(9)) {
            ForEach(visibleLines, id: \.self) { index in
                let outgoing = (frame.firstLineNumber + index).isMultiple(of: 2)
                nativeLine(index)
                    .font(type(index == frame.lineIndex ? 23 : 19, .medium))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, points(16))
                    .padding(.vertical, points(10))
                    .background(outgoing ? Color(red: 0.05, green: 0.45, blue: 1) : Color(white: 0.17), in: BubbleShape(outgoing: outgoing, scale: layoutScale))
                    .frame(maxWidth: points(360), alignment: outgoing ? .trailing : .leading)
                    .frame(width: points(404), alignment: outgoing ? .trailing : .leading)
                    .opacity(index == frame.lineIndex ? 1 : 0.75)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: points(5), y: points(4))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: songLineNumber)
    }

    private var payments: some View {
        let visible = Array(visibleLines.suffix(2))
        return VStack(alignment: .trailing, spacing: points(12)) {
            ForEach(visible, id: \.self) { index in
                HStack(spacing: points(15)) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: points(20), weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: points(41), height: points(41))
                        .background(.white, in: Circle())
                    VStack(alignment: .leading, spacing: points(3)) {
                        Text(frame.artist.isEmpty ? frame.title : frame.artist)
                            .font(.system(size: points(13), weight: .medium))
                            .foregroundStyle(.white.opacity(0.73))
                            .lineLimit(1)
                        nativeLine(index)
                            .font(type(24, .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: points(17)))
                        .foregroundStyle(Color(red: 0.68, green: 0.98, blue: 0.78))
                }
                .padding(points(17))
                .frame(width: points(360))
                .background {
                    RoundedRectangle(cornerRadius: points(21))
                        .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.24, blue: 0.18), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay { RoundedRectangle(cornerRadius: points(21)).stroke(.white.opacity(0.16), lineWidth: points(1)) }
                }
                .opacity(index == frame.lineIndex ? 1 : 0.68)
            }
        }
        .shadow(color: .black.opacity(0.24), radius: points(6), y: points(4))
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                CityMap(lineIndex: songLineNumber, progress: frame.progress, scale: layoutScale)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: points(38), weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(color: .black.opacity(0.45), radius: points(4), y: points(3))
                    .offset(y: points(-12))
                Text("San Francisco")
                    .font(.system(size: points(13), weight: .semibold))
                    .padding(points(9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: points(127))
            VStack(alignment: .leading, spacing: points(6)) {
                nativeLine(frame.lineIndex)
                    .font(type(22, .semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                Label(frame.artist.isEmpty ? frame.title : frame.artist, systemImage: "location.fill")
                    .font(.system(size: points(13), weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(points(13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.11))
        }
        .foregroundStyle(.white)
        .frame(width: points(345))
        .clipShape(RoundedRectangle(cornerRadius: points(19)))
        .shadow(color: .black.opacity(0.28), radius: points(7), y: points(4))
    }

    private var notifications: some View {
        VStack(spacing: points(-9)) {
            ForEach(visibleLines, id: \.self) { index in
                let age = frame.lineIndex - index
                HStack(alignment: .center, spacing: points(11)) {
                    Image(systemName: "music.note")
                        .font(.system(size: points(17), weight: .bold))
                        .frame(width: points(34), height: points(34))
                        .background(LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: points(9)))
                    VStack(alignment: .leading, spacing: points(4)) {
                        HStack(alignment: .lastTextBaseline, spacing: points(8)) {
                            Text(frame.artist.isEmpty ? frame.title : frame.artist)
                                .font(.system(size: points(15), weight: .bold))
                                .lineLimit(1)
                            Spacer(minLength: points(8))
                            Image(systemName: "waveform").font(.system(size: points(11)))
                        }
                        nativeLine(index)
                            .font(type(19, .medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                    }
                }
                .padding(points(14))
                .foregroundStyle(.white)
                .frame(width: points(360 - CGFloat(age) * 15))
                .background(RoundedRectangle(cornerRadius: points(19)).fill(Color(white: 0.19).opacity(0.94)))
                .overlay { RoundedRectangle(cornerRadius: points(19)).stroke(.white.opacity(0.16), lineWidth: points(1)) }
                .opacity(1 - Double(age) * 0.2)
                .shadow(color: .black.opacity(0.2), radius: points(4), y: points(2))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: songLineNumber)
    }
}

private struct BubbleShape: Shape {
    let outgoing: Bool
    let scale: CGFloat
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = min(17 * scale, min(w, h) / 2)
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - 11 * scale))
        path.addQuadCurve(to: CGPoint(x: w + 4 * scale, y: h), control: CGPoint(x: w, y: h - 3 * scale))
        path.addQuadCurve(to: CGPoint(x: w - 9 * scale, y: h - 4 * scale), control: CGPoint(x: w - 4 * scale, y: h))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w - 12 * scale, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        return outgoing ? path : path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
    }
}

private struct CityMap: View {
    let lineIndex: Int
    let progress: Double
    let scale: CGFloat
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(red: 0.17, green: 0.24, blue: 0.27)))
            // Pan between lyric lines; keep the pin and the route in the same coordinate space.
            var map = context
            map.translateBy(x: size.width / 2, y: size.height / 2)
            map.scaleBy(x: scale, y: scale)
            map.rotate(by: .degrees(-19))
            map.translateBy(x: -CGFloat(lineIndex % 8) * 12 - progress * 9, y: 0)
            for column in -7...8 {
                for row in -5...5 {
                    let block = CGRect(x: CGFloat(column * 38 + 3), y: CGFloat(row * 29 + 3), width: 32, height: 23)
                    let park = abs(column * 13 + row * 7).isMultiple(of: 9)
                    let shade = Color(white: 0.21 + Double(abs(column + row) % 4) * 0.025)
                    map.fill(Path(roundedRect: block, cornerRadius: 3), with: .color(park ? Color(red: 0.21, green: 0.37, blue: 0.27) : shade))
                }
            }
            var coast = Path()
            coast.move(to: CGPoint(x: 90, y: -190))
            coast.addQuadCurve(to: CGPoint(x: 187, y: 70), control: CGPoint(x: 72, y: -20))
            coast.addLine(to: CGPoint(x: 360, y: 170))
            coast.addLine(to: CGPoint(x: 360, y: -190))
            coast.closeSubpath()
            map.fill(coast, with: .color(Color(red: 0.12, green: 0.33, blue: 0.45)))
            var route = Path()
            route.move(to: CGPoint(x: -260, y: 59))
            route.addLine(to: CGPoint(x: -76, y: 59))
            route.addLine(to: CGPoint(x: -76, y: 0))
            route.addLine(to: CGPoint(x: 115, y: 0))
            route.addLine(to: CGPoint(x: 115, y: -59))
            map.stroke(route, with: .color(Color(red: 0.39, green: 0.74, blue: 1)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct LyricMarker: Shape {
    let scale: CGFloat
    func path(in rect: CGRect) -> Path {
        let inset = min(5 * scale, rect.width * 0.045)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + scale))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - scale))
        p.closeSubpath()
        return p
    }
}

private let lyricIcons: [String: String] = {
    var icons: [String: String] = [:]
    let groups = [
        ("sun.max.fill", "sun sunny sunshine daylight day dawn morning bright"),
        ("moon.stars.fill", "moon midnight night dream dreams asleep sleep"),
        ("star.fill", "star stars starlight sparkle shine shining"),
        ("cloud.rain.fill", "rain storm crying tears raining cloud clouds"),
        ("flame.fill", "fire flaming burn burning heat hot"),
        ("heart.fill", "love loved lover lovers heart hearts kiss"),
        ("wind", "air breath breathe wind breeze fly flying"),
        ("water.waves", "water wave waves sea seas ocean oceans river tide blue"),
        ("clock.fill", "time clock late minute minutes hour hours second seconds"),
        ("hourglass", "wait waiting patience"),
        ("questionmark.circle.fill", "ask asking question questions wondering"),
        ("brain.fill", "know knew knowing think thinking thought"),
        ("person.fill", "you your yours myself somebody someone"),
        ("bandage.fill", "hurt hurting heal healing"),
        ("house.fill", "home house hometown door"),
        ("bolt.fill", "lightning electric thunder flash"),
        ("speaker.wave.2.fill", "sound loud louder echo echoes noise"),
        ("music.note", "song music sing singing sang dance dancing rhythm melody beat"),
        ("leaf.fill", "tree trees leaves leaf green grow growing"),
        ("road.lanes", "road highway roads mile miles drive driving corner"),
        ("arrow.turn.up.right", "follow following turn turning lead leads"),
        ("tree.fill", "park forest woods trees"),
        ("rectangle.split.2x2", "window windows"),
        ("building.2.crop.circle.fill", "skyline rooftops towers"),
        ("eye.fill", "see saw look looking eyes eye light lights"),
        ("hand.raised.fill", "hand hands touch hold stop"),
        ("globe.americas.fill", "world earth around everywhere"),
        ("sparkles", "gold golden silver magic"),
        ("cloud.fill", "sky skies heaven heavens"),
        ("figure.walk", "walk walking run running feet step steps"),
        ("building.2.fill", "city town skyline buildings streets street"),
        ("bird.fill", "bird birds wings free freedom"),
        ("drop.fill", "drop drops falling fall"),
        ("snowflake", "snow ice cold frozen winter"),
        ("phone.fill", "phone telephone call calling")
    ]
    for (symbol, words) in groups {
        for word in words.split(separator: " ") { icons[String(word)] = symbol }
    }
    return icons
}()

private func wordSymbol(_ word: String) -> String? {
    lyricIcons[word.trimmingCharacters(in: .punctuationCharacters).lowercased()]
}
