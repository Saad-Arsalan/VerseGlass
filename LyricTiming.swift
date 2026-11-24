import Foundation

struct TimedLyrics {
    struct Line {
        var start: Double
        var end: Double?
        var words: [String]
        var starts: [Double]?
    }

    let cues: [Line]
    let texts: [String]
    var hasWordTiming: Bool { cues.contains { $0.starts != nil && !$0.words.isEmpty } }

    // Supports ordinary LRC, repeated timestamps, enhanced LRC, and AMLL's ESLRC.
    private static let stamp = try! NSRegularExpression(pattern: #"[\[<](\d{1,4}):([0-5]?\d)(?:[\.:](\d{1,3}))?[\]>]"#)
    private static let offset = try! NSRegularExpression(pattern: #"(?i)\[offset\s*:\s*([+-]?\d+)\s*\]"#)

    init?(_ content: String) {
        let entire = NSRange(content.startIndex..., in: content)
        let offset = Self.offset.firstMatch(in: content, range: entire)
            .flatMap { Range($0.range(at: 1), in: content) }
            .flatMap { Double(content[$0]) } ?? 0
        var result: [Line] = []
        for source in content.components(separatedBy: .newlines) {
            let text = source as NSString
            let matches = Self.stamp.matches(in: source, range: NSRange(location: 0, length: text.length))
            guard let first = matches.first, text.substring(to: first.range.location)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))).isEmpty else { continue }
            var pieces: [(time: Double, text: String)] = []
            for (index, match) in matches.enumerated() {
                let minute = Double(text.substring(with: match.range(at: 1))) ?? 0
                let second = Double(text.substring(with: match.range(at: 2))) ?? 0
                let decimalRange = match.range(at: 3)
                let fraction = decimalRange.location == NSNotFound ? 0 : Double("0." + text.substring(with: decimalRange)) ?? 0
                let end = matches.indices.contains(index + 1) ? matches[index + 1].range.location : text.length
                let start = NSMaxRange(match.range)
                pieces.append((minute * 60 + second + fraction - offset / 1000,
                               text.substring(with: NSRange(location: start, length: end - start))))
            }

            let repeated = matches.count > 1 && pieces.dropLast().allSatisfy { $0.text.isEmpty }
                && matches.allSatisfy { text.substring(with: $0.range).hasPrefix("[") }
            if matches.count == 1 || repeated {
                let words = pieces.last!.text.split(whereSeparator: \.isWhitespace).map(String.init)
                for piece in pieces { result.append(Line(start: piece.time, words: words, starts: nil)) }
                continue
            }

            // A timestamp can fall inside a syllabified word. Keep that word intact.
            var words: [String] = [], times: [Double] = []
            var pending = ""
            var pendingTime: Double = 0
            func flush() {
                guard !pending.isEmpty else { return }
                words.append(pending)
                times.append(max(times.last ?? pieces[0].time, pendingTime))
                pending = ""
            }
            for piece in pieces {
                for character in piece.text {
                    if character.isWhitespace {
                        flush()
                    } else if character.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) || (0x3040...0x30ff).contains($0.value) }) {
                        flush()
                        pending = String(character)
                        pendingTime = piece.time
                        flush()
                    } else {
                        if pending.isEmpty { pendingTime = piece.time }
                        pending.append(character)
                    }
                }
            }
            flush()
            let end = pieces.last!.text.trimmingCharacters(in: .whitespaces).isEmpty ? pieces.last!.time : nil
            result.append(Line(start: pieces[0].time, end: end, words: words, starts: times))
        }
        guard result.contains(where: { !$0.words.isEmpty }) else { return nil }
        // Some files include parallel translations at the same timestamp. Prefer
        // the first vocal line over a blank marker or a secondary translation.
        let ordered = result.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
        var unique: [Line] = []
        for (_, cue) in ordered {
            if cue.start == unique.last?.start {
                if unique.last?.words.isEmpty == true { unique[unique.count - 1] = cue }
            } else {
                unique.append(cue)
            }
        }
        cues = unique
        texts = unique.map { $0.words.joined(separator: " ") }
    }

    func frame(at position: Double, duration: Double, title: String, artist: String) -> LyricFrame {
        let idle = LyricFrame(title: title, artist: artist, lines: [], lineIndex: 0, wordIndex: 0, progress: 0)
        guard let index = latest(cues, at: position, time: { $0.start }) else { return idle }
        let cue = cues[index]
        let nextStart = cues.indices.contains(index + 1) ? cues[index + 1].start : (duration > cue.start ? duration : cue.start + 5)
        let end = min(cue.end ?? nextStart, nextStart)
        guard position < end, !cue.words.isEmpty else { return idle }
        let progress = min(1, max(0, (position - cue.start) / max(0.001, end - cue.start)))
        let word: Int
        if let starts = cue.starts {
            guard let active = latest(starts, at: position, time: { $0 }) else { return idle }
            word = active
        } else {
            word = min(cue.words.count - 1, Int(progress * Double(cue.words.count)))
        }
        return LyricFrame(title: title, artist: artist, lines: texts, lineIndex: index, wordIndex: word, progress: progress)
    }

    private func latest<T>(_ values: [T], at position: Double, time: (T) -> Double) -> Int? {
        var low = 0, high = values.count
        while low < high {
            let mid = (low + high) / 2
            if time(values[mid]) <= position { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }
}
