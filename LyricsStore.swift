import Foundation
import CryptoKit

enum MusicSource: String, CaseIterable, Sendable {
    case spotify = "Spotify"
    case music = "Apple Music"
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

struct PlaybackTrack: Equatable, Sendable {
    let source: MusicSource
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artwork: URL?

    var cacheKey: String {
        let fields = [title, artist, album, String(Int(duration.rounded()))]
        return SHA256.hash(data: (try! JSONEncoder().encode(fields))).map { String(format: "%02x", $0) }.joined()
    }
}

struct SavedLyrics: Codable {
    let content: String
    let source: String
    var artwork: URL?
}

enum LookupError: LocalizedError {
    case missing, instrumental, network, limited

    var errorDescription: String? {
        switch self {
        case .missing: "No synced lyrics found. Import an LRC for this song."
        case .instrumental: "This recording is marked instrumental. You can import an LRC."
        case .network: "Lyrics service unavailable. Retrying shortly. You can also import an LRC."
        case .limited: "Lyrics service is busy. Waiting before trying again."
        }
    }
}

actor LyricsStore {
    private var limitedUntil = Date.distantPast
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()

    nonisolated func file(for track: PlaybackTrack) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Verseglass"
        return support.appendingPathComponent(name).appendingPathComponent("Lyrics").appendingPathComponent(track.cacheKey + ".json")
    }

    nonisolated func cached(_ track: PlaybackTrack) -> SavedLyrics? {
        guard let url = try? file(for: track), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedLyrics.self, from: data)
    }

    nonisolated func save(_ entry: SavedLyrics, for track: PlaybackTrack) throws {
        let destination = try file(for: track)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: destination, options: .atomic)
    }

    private func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Verseglass"
        request.setValue("\(name)/1.0 (personal macOS lyrics player)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else { throw LookupError.network }
        return (data, http)
    }

    private struct StoreSearch: Decodable {
        struct Match: Decodable {
            let trackId: Int
            let trackName: String
            let artistName: String
            let trackTimeMillis: Int?
            let artworkUrl100: URL?
        }
        let results: [Match]
    }

    private func appleMatch(_ track: PlaybackTrack) async -> StoreSearch.Match? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: track.title + " " + track.artist),
            URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "15")
        ]
        guard let url = components.url, let (data, http) = try? await fetch(url), http.statusCode == 200,
              let result = try? JSONDecoder().decode(StoreSearch.self, from: data) else { return nil }
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        return result.results.first {
            normalized($0.trackName) == normalized(track.title) && normalized($0.artistName) == normalized(track.artist)
                && $0.trackTimeMillis.map { abs(Double($0) / 1000 - track.duration) <= 3 } == true
        }
    }

    func lookup(_ track: PlaybackTrack) async throws -> SavedLyrics {
        var artwork = track.artwork
        var platformID: String?
        if track.source == .spotify, track.id.hasPrefix("spotify:track:") {
            let id = String(track.id.dropFirst("spotify:track:".count))
            if id.count == 22, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) { platformID = id }
        } else if track.source == .music, let match = await appleMatch(track) {
            platformID = String(match.trackId)
            artwork = match.artworkUrl100
        }
        if let platformID {
            let directory = track.source == .spotify ? "spotify-lyrics" : "am-lyrics"
            let url = URL(string: "https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main/\(directory)/\(platformID).eslrc")!
            if let (data, http) = try? await fetch(url), http.statusCode == 200,
               let content = String(data: data, encoding: .utf8), TimedLyrics(content)?.hasWordTiming == true {
                return SavedLyrics(content: content, source: "AMLL", artwork: artwork)
            }
        }
        guard limitedUntil <= Date() else { throw LookupError.limited }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist)]
        if !track.album.isEmpty { query.append(URLQueryItem(name: "album_name", value: track.album)) }
        if (1...3600).contains(track.duration) { query.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        components.queryItems = query
        guard let url = components.url else { throw LookupError.missing }
        let (data, http) = try await fetch(url)
        if http.statusCode == 429 {
            let delay = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            limitedUntil = Date().addingTimeInterval(max(1, delay) + Double.random(in: 1...4))
            throw LookupError.limited
        }
        if [400, 404].contains(http.statusCode) { throw LookupError.missing }
        guard http.statusCode == 200 else { throw LookupError.network }
        struct Record: Decodable { let syncedLyrics: String?; let instrumental: Bool? }
        let record = try JSONDecoder().decode(Record.self, from: data)
        if record.instrumental == true { throw LookupError.instrumental }
        guard let content = record.syncedLyrics, TimedLyrics(content) != nil else { throw LookupError.missing }
        return SavedLyrics(content: content, source: "LRCLIB", artwork: artwork)
    }
}
