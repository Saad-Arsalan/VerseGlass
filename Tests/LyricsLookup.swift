import Foundation

private final class CatalogFixture: URLProtocol {
    static var handle: (URL) -> (Int, Data) = { _ in fatalError("Unexpected request") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let (status, body) = Self.handle(url)
        let reply = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main private enum LyricsLookupTests {
    static let track = PlaybackTrack(source: .spotify, id: "", title: "Blue Hour", artist: "Studio", album: "The Collection", duration: 244, artwork: nil)

    static func record(_ lyric: String, title: String = "Blue Hour", artist: String = "Studio", duration: Double = 244) -> [String: Any] {
        ["trackName": title, "artistName": artist, "albumName": "Original", "duration": duration, "syncedLyrics": lyric]
    }

    static func data(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }

    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogFixture.self]
        let store = LyricsStore(session: URLSession(configuration: config))
        let matched = "[00:10]matched"
        let other = "[00:10]other"
        let rejected = [record(other, title: "Blue Hour (Live)"), record(other, title: "Blue Hour - Remix"),
                        record(other, artist: "Another Artist"), record(other, duration: 170), record("untimed text")]

        CatalogFixture.handle = { url in
            precondition(url.path == "/api/get")
            return (200, data(record(matched)))
        }
        let exact = try await store.lookup(track)
        precondition(exact.content == matched)

        for exactStatus in [200, 404] {
            CatalogFixture.handle = { url in
                if url.path == "/api/get" { return (exactStatus, data(record(""))) }
                precondition(url.path == "/api/search")
                let keys = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map(\.name)
                precondition(Set(keys) == ["track_name", "artist_name"])
                return (200, data(rejected + [record(matched, title: "BLUE  HOUR", duration: 244.4)]))
            }
            let result = try await store.lookup(track)
            precondition(result.content == matched)
        }

        CatalogFixture.handle = { url in url.path == "/api/get" ? (404, Data()) : (200, data(rejected)) }
        do { _ = try await store.lookup(track); fatalError("Accepted unrelated recording") }
        catch LookupError.missing {}

        CatalogFixture.handle = { url in url.path == "/api/get" ? (404, Data()) : (429, Data()) }
        do { _ = try await store.lookup(track); fatalError("Missed rate limit") }
        catch LookupError.limited {}
        CatalogFixture.handle = { _ in fatalError("Queried provider during backoff") }
        do { _ = try await store.lookup(track); fatalError("Missed backoff") }
        catch LookupError.limited {}
        print("PASS exact match, alternate releases, version and duration rejection, and rate limiting")
    }
}
