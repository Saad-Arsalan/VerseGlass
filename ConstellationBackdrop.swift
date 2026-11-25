import ImageIO
import SwiftUI

// A screen saver runs inside another process. Resolve the wallpaper relative
// to the bundle containing this class so both the app and saver can find it.
private final class ConstellationResources: NSObject {
    static let wallpaper: CGImage? = {
        let bundle = Bundle(for: ConstellationResources.self)
        guard let url = bundle.url(forResource: "ConstellationInk", withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
}

struct ConstellationBackdrop: View {
    var artwork: Data? = nil
    let showsClock: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shortSide = min(size.width, size.height)
            let coverSide = shortSide * 0.075
            ZStack {
                Color(red: 0.18, green: 0.13, blue: 0.16)
                if let wallpaper = ConstellationResources.wallpaper {
                    Image(decorative: wallpaper, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }
                Color.black.opacity(contrast == .increased ? 0.42 : 0.16)
                if showsClock {
                    TimelineView(.everyMinute) { tick in
                        VStack(spacing: -shortSide * 0.008) {
                            Text(tick.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.system(size: shortSide * 0.025, weight: .medium))
                            Text(tick.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                .font(.system(size: shortSide * 0.115, weight: .light, design: .serif))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.94, blue: 0.86).opacity(0.84))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    }
                    .position(x: size.width * 0.5, y: max(shortSide * 0.13, size.height * 0.12))
                }
                if let artwork {
                    ConstellationCover(data: artwork)
                        .equatable()
                        .frame(width: coverSide, height: coverSide)
                        .clipShape(RoundedRectangle(cornerRadius: coverSide * 0.18))
                        .shadow(color: .black.opacity(0.4), radius: coverSide * 0.12, y: 2)
                        .position(x: size.width - coverSide * 0.95, y: size.height * 0.86)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}

// Identical cover bytes arrive with successive lyric frames. EquatableView
// skips decoding until the image changes.
private struct ConstellationCover: View, Equatable {
    let data: Data

    var body: some View {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192
        ]
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cover = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            Image(decorative: cover, scale: 1).resizable().scaledToFill()
        }
    }
}
