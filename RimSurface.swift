import SwiftUI

struct SaverGlow: View {
    let rim: SaverRim
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Canvas { context, size in
            guard size.width > 1 && size.height > 1 else { return }
            let scale = min(1, min(size.width, size.height) / 440)
            let first = Color(hex: rim.primary), second = Color(hex: rim.secondary)
            let energy = reduceMotion ? 0.45 : min(1, max(0, rim.level))
            let strength = 0.40 + 0.6 * energy
            let band = max(0.7, (rim.thickness + 4 * energy) * scale)
            let spread = (12 + 52 * rim.glow) * scale * (0.7 + 0.45 * energy)
            let bounds = CGRect(origin: .zero, size: size)
            let gradient = Gradient(colors: [first, second, first, second, first])
            let paint = GraphicsContext.Shading.conicGradient(gradient, center: CGPoint(x: bounds.midX, y: bounds.midY), angle: .degrees(-125 + energy * 12))
            let path = Path(roundedRect: bounds, cornerRadius: max(4, 12 * scale))
            context.drawLayer { layer in
                layer.opacity = strength * rim.glow * 0.65
                layer.addFilter(.blur(radius: spread * 0.60))
                layer.stroke(path, with: paint, lineWidth: band + spread * 1.3)
            }
            context.drawLayer { layer in
                layer.opacity = strength * 0.86
                layer.addFilter(.blur(radius: max(0.6, band * 0.55)))
                layer.stroke(path, with: paint, lineWidth: band * 2.4)
            }
            context.opacity = min(1, strength + 0.12)
            context.stroke(path, with: paint, lineWidth: band)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
