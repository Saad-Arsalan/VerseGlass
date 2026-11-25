import AVFoundation
import XCTest
@testable import VerseGlass

final class PadPlaybackTests: XCTestCase {
    @MainActor
    func testLocalAudioDrivesImportedLyricsAndRestoresThemOnReopen() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent(UUID().uuidString + ".caf")
        try writeSilence(to: audio)
        let lrc = folder.appendingPathComponent("fixture.lrc")
        try "[00:00.00]After dark\n[00:02.00]<00:02.00>Quiet <00:03.00>streets\n"
            .write(to: lrc, atomically: true, encoding: .utf8)

        let player = PadPlayer()
        defer { player.playDemo() }
        await player.openAudio(audio)
        XCTAssertEqual(player.source, .file)
        XCTAssertEqual(player.duration, 6, accuracy: 0.05)
        let song = try XCTUnwrap(player.lyricTarget)
        let cache = try LyricsStore().file(for: song)
        defer { try? FileManager.default.removeItem(at: cache) }

        player.importLyrics(lrc, for: song)
        XCTAssertEqual(player.frame.lines, ["After dark", "Quiet streets"])
        // Sample AVPlayer's real clock, independent of the animation timer.
        let deadline = Date().addingTimeInterval(5)
        repeat {
            try await Task.sleep(for: .milliseconds(100))
            player.tick()
        } while player.position < 0.15 && Date() < deadline
        XCTAssertGreaterThan(player.position, 0.1)
        XCTAssertTrue(player.isPlaying)
        player.togglePlayback()
        XCTAssertFalse(player.isPlaying)
        player.seek(to: 3.25)
        XCTAssertEqual(player.frame.lineIndex, 1)
        XCTAssertEqual(player.frame.wordIndex, 1)

        player.playDemo()
        await player.openAudio(audio)
        XCTAssertEqual(player.frame.lines.first, "After dark")
        XCTAssertNil(player.errorMessage)
    }

    private func writeSilence(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let frames: AVAudioFrameCount = 48_000
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData)
        samples[0].update(repeating: 0, count: Int(frames))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
