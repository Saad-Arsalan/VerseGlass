import SwiftUI

/// A transparent artboard. A thumbnail and a full-screen overlay use the same composition.
struct LyricScene: View {
    let frame: LyricFrame
    let style: Style
    let size: CGFloat
    let fontName: String
    let accent: Color

    @Environment(\.self) private var environment
    @Environment(\.lyricPrimary) private var primary
    @Environment(\.lyricSecondary) private var secondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var line: String {
        frame.lines.indices.contains(frame.lineIndex) ? frame.lines[frame.lineIndex] : ""
    }

    private var words: [String] { line.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var active: Int { min(words.count - 1, max(-1, frame.wordIndex)) }

    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / 600, geometry.size.height / 320)
            Group {
                if !line.isEmpty {
                    switch style {
                    case .ship, .fisheye, .visual, .fisheyeVisual:
                        kineticWords
                    case .codestyle, .codestyleVisual:
                        codeScene
                    case .constellation:
                        ConstellationScene(frame: frame, fontName: fontName, accent: accent)
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
            .frame(width: 600, height: 320)
            .scaleEffect(fit * max(0.25, size / 40))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
    }

    private func type(_ points: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        switch fontName {
        case "SF Pro", "": return .system(size: points, weight: weight)
        case "SF Rounded": return .system(size: points, weight: weight, design: .rounded)
        case "New York": return .system(size: points, weight: weight, design: .serif)
        default: return .custom(fontName, fixedSize: points).weight(weight)
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
                    .offset(x: geometry.x, y: geometry.y)
                    .zIndex(Double(index))
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .offset(y: 9).combined(with: .scale(scale: 0.88)).combined(with: .opacity),
                        removal: .offset(y: -16).combined(with: .opacity)))
            }
        }
        .frame(width: 550, height: 285)
        .id(frame.lineIndex)
        .rotation3DEffect(.degrees(wall ? (reduceMotion ? -11 : -13 + 9 * frame.progress) : 0),
                          axis: (0, 1, 0), perspective: 0.65)
        .rotationEffect(.degrees(wall ? -3 : 0))
        .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
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
            .font(.system(size: 47, weight: .semibold))
            .foregroundStyle(accent)
            .fixedSize()
        return HStack(spacing: 10) {
            if symbol != nil && !trailingIcon { icon }
            Text(verbatim: word)
                .font(type(83, age == 1 ? .heavy : .semibold))
                .tracking(-3.8)
                .lineLimit(1)
                .minimumScaleFactor(0.20)
                .foregroundStyle(ink)
                .padding(.horizontal, isNew ? 7 : 0)
                .background {
                    if isNew {
                        LyricMarker().fill(accent)
                            .padding(.vertical, 5)
                    }
                }
            if symbol != nil && trailingIcon { icon }
        }
        .frame(maxWidth: 515)
        .scaleEffect(scale)
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
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(frame.title).foregroundStyle(secondary).lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            HStack(alignment: .top, spacing: 14) {
                Text(String(format: "%02d", frame.lineIndex + 1))
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("lyric {")
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                    TimelineView(.periodic(from: .now, by: 0.55)) { tick in
                        let visible = reduceMotion || Int(tick.date.timeIntervalSinceReferenceDate / 0.55).isMultiple(of: 2)
                        (displayed + Text(" ▌").foregroundColor(visible ? .red : .clear))
                            .lineLimit(4)
                            .minimumScaleFactor(0.55)
                    }
                    .font(fontName == "SF Pro" ? .system(size: 32, weight: .semibold, design: .monospaced) : type(32, .semibold))
                    .padding(.leading, 16)
                    Text("}").foregroundStyle(accent)
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                }
            }
        }
        .frame(width: 420, alignment: .leading)
        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
    }

    private var graphScene: some View {
        let isWeb = style == .web
        let isBranch = style == .branches
        let limit = isWeb ? 8 : 5
        let first = max(0, active) / limit * limit
        let indices = Array(first..<min(words.count, first + limit))
        let points: [CGPoint] = indices.indices.map { i in
            if isWeb {
                let angle = Double(i) / Double(max(3, indices.count)) * 2 * .pi - .pi / 2
                return CGPoint(x: 300 + 206 * cos(angle), y: 160 + 111 * sin(angle))
            }
            let x = 300 + (CGFloat(i) - CGFloat(indices.count - 1) / 2) * 105
            let heights = [110, 193, 93, 184, 104]
            return CGPoint(x: x, y: CGFloat(heights[i]))
        }
        return ZStack {
            Canvas { context, canvas in
                let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                if isWeb {
                    for ring in 1...4 {
                        let fraction = CGFloat(ring) / 4
                        var path = Path()
                        for (i, point) in points.enumerated() {
                            let end = CGPoint(x: center.x + (point.x - center.x) * fraction, y: center.y + (point.y - center.y) * fraction)
                            if i == 0 { path.move(to: end) } else { path.addLine(to: end) }
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(secondary.opacity(0.3)), lineWidth: 0.9)
                    }
                }
                if isBranch, let first = points.first, let last = points.last {
                    var stem = Path()
                    stem.move(to: CGPoint(x: first.x - 40, y: 157))
                    stem.addQuadCurve(to: CGPoint(x: last.x + 34, y: 148), control: CGPoint(x: 300, y: 173))
                    context.stroke(stem, with: .color(secondary.opacity(0.75)), lineWidth: 2)
                }
                for (i, point) in points.enumerated() {
                    let lit = indices[i] <= active
                    var path = Path()
                    if isWeb {
                        path.move(to: center)
                        path.addLine(to: point)
                    } else if isBranch {
                        path.move(to: CGPoint(x: point.x - 29, y: 159))
                        path.addQuadCurve(to: point, control: CGPoint(x: point.x, y: 155))
                    }
                    context.stroke(path, with: .color(lit ? accent : secondary.opacity(0.43)), lineWidth: lit ? 2 : 1)
                    let radius: CGFloat = indices[i] == active ? 5 : 3
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(lit ? accent : secondary))
                    if indices[i] == active {
                        let halo = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
                        context.stroke(Path(ellipseIn: halo), with: .color(accent.opacity(0.6)), lineWidth: 1)
                    }
                }
            }
            ForEach(Array(indices.enumerated()), id: \.element) { local, index in
                let point = points[local]
                let lit = index == active
                Text(words[index])
                    .font(type(lit ? 25 : 18, lit ? .heavy : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
                    .frame(width: isWeb ? 123 : 105)
                    .foregroundStyle(lit ? accent : index < active ? primary : secondary)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .position(x: point.x, y: point.y + (point.y >= 158 ? 21 : -20))
            }
        }
        .frame(width: 600, height: 320)
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
        VStack(spacing: 9) {
            ForEach(visibleLines, id: \.self) { index in
                let outgoing = index.isMultiple(of: 2)
                nativeLine(index)
                    .font(type(index == frame.lineIndex ? 23 : 19, .medium))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(outgoing ? Color(red: 0.05, green: 0.45, blue: 1) : Color(white: 0.17), in: BubbleShape(outgoing: outgoing))
                    .frame(maxWidth: 360, alignment: outgoing ? .trailing : .leading)
                    .frame(width: 404, alignment: outgoing ? .trailing : .leading)
                    .opacity(index == frame.lineIndex ? 1 : 0.75)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: frame.lineIndex)
    }

    private var payments: some View {
        let visible = Array(visibleLines.suffix(2))
        return VStack(alignment: .trailing, spacing: 12) {
            ForEach(visible, id: \.self) { index in
                HStack(spacing: 15) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 41, height: 41)
                        .background(.white, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(frame.artist.isEmpty ? frame.title : frame.artist)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.73))
                            .lineLimit(1)
                        nativeLine(index)
                            .font(type(24, .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.68, green: 0.98, blue: 0.78))
                }
                .padding(17)
                .frame(width: 360)
                .background {
                    RoundedRectangle(cornerRadius: 21)
                        .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.24, blue: 0.18), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay { RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.16)) }
                }
                .opacity(index == frame.lineIndex ? 1 : 0.68)
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 6, y: 4)
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                CityMap(lineIndex: frame.lineIndex, progress: frame.progress)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 38, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 3)
                    .offset(y: -12)
                Text("San Francisco")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 127)
            VStack(alignment: .leading, spacing: 6) {
                nativeLine(frame.lineIndex)
                    .font(type(22, .semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                Label(frame.artist.isEmpty ? frame.title : frame.artist, systemImage: "location.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.11))
        }
        .foregroundStyle(.white)
        .frame(width: 345)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
    }

    private var notifications: some View {
        VStack(spacing: -9) {
            ForEach(visibleLines, id: \.self) { index in
                let age = frame.lineIndex - index
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: "music.note")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(frame.artist.isEmpty ? frame.title : frame.artist)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "waveform").font(.system(size: 11))
                        }
                        nativeLine(index)
                            .font(type(19, .medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                    }
                }
                .padding(14)
                .foregroundStyle(.white)
                .frame(width: 360 - CGFloat(age) * 15)
                .background(RoundedRectangle(cornerRadius: 19).fill(Color(white: 0.19).opacity(0.94)))
                .overlay { RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.16)) }
                .opacity(1 - Double(age) * 0.2)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: frame.lineIndex)
    }
}

private struct BubbleShape: Shape {
    let outgoing: Bool
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = min(17, min(w, h) / 2)
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - 11))
        path.addQuadCurve(to: CGPoint(x: w + 4, y: h), control: CGPoint(x: w, y: h - 3))
        path.addQuadCurve(to: CGPoint(x: w - 9, y: h - 4), control: CGPoint(x: w - 4, y: h))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w - 12, y: h))
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
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(red: 0.17, green: 0.24, blue: 0.27)))
            // Pan between lyric lines; keep the pin and the route in the same coordinate space.
            var map = context
            map.translateBy(x: size.width / 2, y: size.height / 2)
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
    func path(in rect: CGRect) -> Path {
        let inset = min(5, rect.width * 0.045)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - 1))
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
