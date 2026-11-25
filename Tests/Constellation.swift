import Foundation

@main struct ConstellationTests {
    static func main() {
        let lines = ["first line", "second line", "third line", "fourth line", "follow the light", "until the stars align"]
        func phrase(_ lines: [String], _ line: Int, _ word: Int, offset: Int = 0) -> ConstellationPhrase? {
            ConstellationPhrase(frame: LyricFrame(title: "Test", artist: "VerseGlass", lines: lines,
                lineIndex: line, wordIndex: word, progress: 0.5, firstLineNumber: offset))
        }

        let desktop = phrase(lines, 5, 2)!
        let saver = phrase(Array(lines.suffix(4)), 3, 2, offset: 2)!
        precondition(desktop.words == ["follow", "the", "light", "until", "the", "stars"])
        precondition(desktop.words == saver.words && desktop.seed == saver.seed)
        for i in desktop.words.indices { precondition(desktop.point(at: i) == saver.point(at: i)) }
        let earlier = phrase(lines, 5, 0)!
        precondition(earlier.seed == desktop.seed && earlier.words == Array(desktop.words.prefix(4)))
        precondition(phrase(lines, 4, 0)!.words == ["follow"])
        let long = (1...36).map(String.init).joined(separator: " ")
        precondition(phrase([long], 0, 12)!.words == ["13"])
        precondition(phrase([long, "next phrase"], 1, 0)!.words == ["next"])
        precondition(phrase(["", "fresh words"], 1, 0)!.words == ["fresh"])
        precondition(phrase([], -1, -1) == nil)
        precondition(phrase([""], 0, 1) == nil)
        print("Constellation timing, seeks and saver continuity passed")
    }
}
