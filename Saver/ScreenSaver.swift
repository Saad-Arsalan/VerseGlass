import AppKit
import ScreenSaver
import SwiftUI

@MainActor final class SaverModel: ObservableObject {
    @Published var packet: SaverPacket?
    var receiver: NSObjectProtocol?
    private var lastRequest = Date.distantPast
    func start() {
        guard receiver == nil else { return }
        let center = DistributedNotificationCenter.default()
        receiver = center.addObserver(forName:SaverPacket.response, object:nil, queue:.main) { [weak self] note in
            guard let data = note.userInfo?["frame"] as? Data, data.count <= 16384,
                  let frame = try? PropertyListDecoder().decode(SaverPacket.self,from:data),
                  abs(frame.date.timeIntervalSinceNow) < 2 else { return }
            MainActor.assumeIsolated { self?.packet = frame }
        }
        tick()
    }
    func tick() {
        if lastRequest.timeIntervalSinceNow < -1 {
            lastRequest = Date()
            DistributedNotificationCenter.default().postNotificationName(SaverPacket.request,object:nil,userInfo:nil,options:[.deliverImmediately])
        }
        if let packet, packet.date.timeIntervalSinceNow < -2 { self.packet=nil }
    }
    func stop() {
        if let receiver { DistributedNotificationCenter.default().removeObserver(receiver) }
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
        model.start()
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
        ZStack {
            Color.black
            if let p=model.packet {
                if includes(p.display), p.lines.indices.contains(p.lineIndex) {
                    LyricScene(frame:LyricFrame(title:p.title,artist:p.artist,lines:p.lines,lineIndex:p.lineIndex,wordIndex:p.wordIndex,progress:p.progress),
                               style:Style(rawValue:p.style) ?? .visual, size:p.size,fontName:p.font,accent:Color(hex:p.accent))
                        .environment(\.lyricPrimary,Color(hex:p.primary)).environment(\.lyricSecondary,Color(hex:p.secondary))
                        .padding(.horizontal,32)
                }
                if p.rim.enabled && includes(p.rim.display) { SaverGlow(rim:p.rim) }
            } else if preview {
                TimelineView(.periodic(from:.now,by:0.12)) { t in
                    LyricScene(frame:.demo(at:t.date.timeIntervalSinceReferenceDate),style:.visual,size:42,fontName:"SF Pro",accent:Color(hex:"D88089"))
                }
            }
        }.preferredColorScheme(.dark)
    }
    func includes(_ ids:String) -> Bool { preview || ids == "all" || ids.split(separator:",").contains(Substring(display)) }
}
