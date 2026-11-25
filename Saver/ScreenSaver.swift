import AppKit
import ScreenSaver
import OSLog
import SwiftUI

@MainActor final class SaverModel: ObservableObject {
    @Published var packet: SaverPacket?
    var receiver: NSObjectProtocol?
    private var reportedLyrics = false
    private let log = Logger(subsystem:"local.verseglass.app",category:"saver-host")
    private var lastRequest = Date.distantPast
    private var fullScreenHost = false
    func start(preview: Bool) {
        guard receiver == nil else { return }
        fullScreenHost = !preview
        let center = DistributedNotificationCenter.default()
        receiver = center.addObserver(forName:SaverPacket.response, object:nil, queue:.main) { [weak self] note in
            guard let data = note.userInfo?["frame"] as? Data, data.count <= SaverPacket.maximumBytes,
                  let frame = try? PropertyListDecoder().decode(SaverPacket.self,from:data),
                  abs(frame.date.timeIntervalSinceNow) < 2 else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.packet = frame
                if !self.reportedLyrics, frame.lines.indices.contains(frame.lineIndex) {
                    self.reportedLyrics = true
                    self.log.notice("Saver host decoded its first live lyric frame")
                }
            }
        }
        tick()
    }
    func tick() {
        if lastRequest.timeIntervalSinceNow < -1 {
            lastRequest = Date()
            let center = DistributedNotificationCenter.default()
            center.postNotificationName(SaverPacket.request, object: nil, userInfo: nil, options: [.deliverImmediately])
            if fullScreenHost {
                center.postNotificationName(SaverPacket.hostActive, object: nil, userInfo: nil, options: [.deliverImmediately])
            }
        }
        if let packet, packet.date.timeIntervalSinceNow < -2 { self.packet=nil }
    }
    func stop() {
        if let receiver { DistributedNotificationCenter.default().removeObserver(receiver) }
        reportedLyrics=false
        receiver=nil
        packet=nil
        lastRequest = .distantPast
    }
}

@objc(VerseglassSaverView)
final class VerseglassSaverView: ScreenSaverView {
    private let model = SaverModel()
    private var hosted: NSView?
    override func startAnimation() {
        super.startAnimation()
        animationTimeInterval = 0.25
        if hosted == nil {
            let scene = SaverScene(model:model,preview:isPreview,display:window?.screen?.verseID ?? NSScreen.main?.verseID ?? "")
            let view = NSHostingView(rootView:scene)
            view.frame=bounds
            view.autoresizingMask=[.width,.height]
            addSubview(view)
            hosted=view
        }
        model.start(preview: isPreview)
    }
    override func animateOneFrame() { model.tick() }
    override func stopAnimation() {
        model.stop()
        hosted?.removeFromSuperview()
        hosted=nil
        super.stopAnimation()
    }
}

private struct SaverScene: View {
    @ObservedObject var model: SaverModel
    let preview: Bool
    let display: String
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let p = model.packet {
                    let style = Style(rawValue: p.style) ?? .visual
                    let hasLine = p.lines.indices.contains(p.lineIndex)
                    if includes(p.display), p.showsConstellationBackdrop ?? (style == .constellation && hasLine) {
                        ConstellationBackdrop(artwork: p.artwork, showsClock: false)
                    }
                    if includes(p.display), hasLine {
                        let frame = LyricFrame(title: p.title, artist: p.artist, lines: p.lines, lineIndex: p.lineIndex,
                                               wordIndex: p.wordIndex, progress: p.progress, firstLineNumber: p.firstLineNumber ?? 0)
                        LyricScene(frame: frame, style: style, size: p.size, fontName: p.font, accent: Color(hex: p.accent))
                            .environment(\.lyricPrimary, Color(hex: p.primary))
                            .environment(\.lyricSecondary, Color(hex: p.secondary))
                            .padding(.horizontal, style == .constellation ? geometry.size.width * 0.03 : 32)
                            .padding(.top, style == .constellation ? geometry.size.height * 0.17 : 0)
                            .padding(.bottom, style == .constellation ? geometry.size.height * 0.05 : 0)
                    }
                    if p.rim.enabled && includes(p.rim.display) { SaverGlow(rim:p.rim) }
                } else if preview {
                    ConstellationBackdrop(showsClock: false)
                    TimelineView(.periodic(from: .now, by: 0.12)) { tick in
                        LyricScene(frame: .demo(at: tick.date.timeIntervalSinceReferenceDate), style: .constellation,
                                   size: 40, fontName: "SF Pro", accent: Color(hex: "F5E5C2"))
                            .padding(.top, geometry.size.height * 0.17)
                            .padding(.bottom, geometry.size.height * 0.05)
                    }
                }
            }
        }.preferredColorScheme(.dark)
    }
    func includes(_ ids:String) -> Bool { preview || ids == "all" || ids.split(separator:",").contains(Substring(display)) }
}
