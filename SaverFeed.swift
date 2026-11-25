import AppKit
import Combine

@MainActor final class SaverFeed {
    private var listener: AnyCancellable?
    private var timer: AnyCancellable?
    private var requestedUntil = Date.distantPast
    init(engine: Engine, prefs: Preferences) {
        let center = DistributedNotificationCenter.default()
        listener = center.publisher(for: SaverPacket.request).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.requestedUntil = Date().addingTimeInterval(3) }
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] now in
            guard let self, now < requestedUntil else { return }
            let f = engine.frame
            let valid = prefs.enabled && engine.playing && f.lines.indices.contains(f.lineIndex)
            let first = valid ? max(0, f.lineIndex - 3) : 0
            let lines = valid ? f.lines[first...min(f.lines.count - 1, f.lineIndex + 1)].map { String($0.prefix(200)) } : []
            let backdrop = prefs.enabled && engine.playing && prefs.style == .constellation && !f.title.isEmpty
            var packet = SaverPacket(date: now, title: String(f.title.prefix(100)), artist: String(f.artist.prefix(100)),
                lines:lines, lineIndex:valid ? f.lineIndex - first : -1, wordIndex:f.wordIndex, progress:f.progress,
                style:prefs.style.rawValue, size:prefs.textSize, font:prefs.fontName, accent:prefs.effectiveAccent.rgbHex,
                primary:prefs.primaryHex, secondary:prefs.secondaryHex, display:prefs.displayID, rim:RoomLighting.shared.saverRim,
                firstLineNumber:first, artwork:backdrop ? prefs.artworkThumbnail : nil,
                showsConstellationBackdrop:backdrop)
            let encoder = PropertyListEncoder()
            guard var data = try? encoder.encode(packet) else { return }
            if data.count > SaverPacket.maximumBytes {
                packet.artwork = nil
                guard let lyricsOnly = try? encoder.encode(packet), lyricsOnly.count <= SaverPacket.maximumBytes else { return }
                data = lyricsOnly
            }
            center.postNotificationName(SaverPacket.response, object:nil, userInfo:["frame":data],options:[.deliverImmediately])
        }
    }
}
