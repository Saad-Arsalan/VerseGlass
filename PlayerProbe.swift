import AppKit

struct PlayerReading: Sendable {
    var status = "Not running"
    var track: PlaybackTrack?
    var playing = false
    var position = 0.0
    var sampled = ProcessInfo.processInfo.systemUptime
}

// Use each player's published scripting dictionary through Apple Events. Target
// the running PID so checking for music can never launch a closed player.
actor PlayerProbe {
    private let source: MusicSource
    private var lastTrack: PlaybackTrack?
    private var lastPID: pid_t?
    init(_ source: MusicSource) { self.source = source }

    private func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private func property(_ name: String, of parent: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record()
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("seld"))
        spec.setDescriptor(parent ?? NSAppleEventDescriptor.null(), forKeyword: code("from"))
        guard let result = spec.coerce(toDescriptorType: code("obj ")) else { throw CocoaError(.coderInvalidValue) }
        return result
    }

    func read(_ pid: pid_t?) -> PlayerReading {
        guard let pid else {
            lastTrack = nil
            return PlayerReading()
        }
        if lastPID != pid { lastPID = pid; lastTrack = nil }
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        func get(_ name: String, of parent: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(eventClass: code("core"), eventID: code("getd"), targetDescriptor: target, returnID: -1, transactionID: 0)
            event.setParam(try property(name, of: parent), forKeyword: code("----"))
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 2)
            if let err = reply.paramDescriptor(forKeyword: code("errn")), err.int32Value != 0 {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(err.int32Value))
            }
            guard let result = reply.paramDescriptor(forKeyword: code("----")) else { throw CocoaError(.coderValueNotFound) }
            return result
        }
        do {
            let state = try get("pPlS").enumCodeValue
            let playing = state == code("kPSP")
            guard playing || state == code("kPSp") else { lastTrack = nil; return PlayerReading(status: "Stopped") }
            let current = try property("pTrk")
            let id = (try? get(source == .spotify ? "ID  " : "pPIS", of: current).stringValue) ?? ""
            if lastTrack == nil || id.isEmpty || id == "0" || id == "0000000000000000" || id != lastTrack?.id {
                guard let name = try get("pnam", of: current).stringValue, !name.isEmpty else { return PlayerReading(status: "No track") }
                let artist = (try? get("pArt", of: current).stringValue) ?? ""
                let album = (try? get("pAlb", of: current).stringValue) ?? ""
                let rawDuration = (try? get("pDur", of: current).doubleValue) ?? 0
                let duration = rawDuration / (source == .spotify ? 1000 : 1)
                let url = source == .spotify ? (try? get("aUrl", of: current).stringValue).flatMap(URL.init(string:)) : nil
                lastTrack = PlaybackTrack(source: source, id: id, title: name, artist: artist, album: album,
                                          duration: duration.isFinite ? max(0, duration) : 0, artwork: url)
            }
            let position = try get("pPos").doubleValue
            return PlayerReading(status: playing ? "Playing" : "Paused", track: lastTrack, playing: playing,
                                 position: position.isFinite ? max(0, position) : 0)
        } catch {
            let code = (error as NSError).code
            let status = code == -1743 || code == -1744 ? "Allow Automation in System Settings"
                : code == -1728 ? "No track" : "Waiting for player"
            return PlayerReading(status: status)
        }
    }
}
