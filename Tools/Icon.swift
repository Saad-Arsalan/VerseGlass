import AppKit

@main
struct DrawVerseglassIcon {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func color(_ rgb: Int, alpha: CGFloat = 1) -> CGColor {
        let r = CGFloat((rgb >> 16) & 255) / 255
        let g = CGFloat((rgb >> 8) & 255) / 255
        let b = CGFloat(rgb & 255) / 255
        return CGColor(colorSpace: space, components: [r, g, b, alpha])!
    }

    static func fill(_ path: CGPath, in context: CGContext, colors: [Int], from: CGPoint, to: CGPoint) {
        let palette = colors.map { color($0) }
        let gradient = CGGradient(colorsSpace: space, colors: palette as CFArray, locations: nil)!
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    static func image(size: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        // Match the SwiftUI mark's coordinate convention.
        context.translateBy(x: 0, y: CGFloat(size))
        let scale = CGFloat(size) / 128
        context.scaleBy(x: scale, y: -scale)
        let tile = CGPath(roundedRect: CGRect(x: 8, y: 7, width: 112, height: 112), cornerWidth: 25, cornerHeight: 25, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1.7), blur: 2.6, color: color(0x180c14, alpha: 0.35))
        context.addPath(tile)
        context.setFillColor(color(0x321e31))
        context.fillPath()
        context.restoreGState()
        fill(tile, in: context, colors: [0x633c55, 0x32202f, 0x201925, 0x463446],
             from: CGPoint(x: 22, y: 9), to: CGPoint(x: 107, y: 119))
        context.addPath(tile)
        context.setLineWidth(0.7)
        context.setStrokeColor(color(0xfce3f0, alpha: 0.20))
        context.strokePath()

        context.translateBy(x: 24, y: 26)
        context.scaleBy(x: 0.8, y: 0.8)
        context.setFillColor(color(0x533449))
        context.addPath(VerseglassGlyph.silhouette)
        context.fillPath()
        fill(VerseglassGlyph.fold, in: context, colors: [0xffe9ed, 0xeeafc2, 0xb46b90],
             from: CGPoint(x: 14, y: 15), to: CGPoint(x: 51, y: 83))
        fill(VerseglassGlyph.blade, in: context, colors: [0xfff5ef, 0xf6c7d7, 0xd78fa8],
             from: CGPoint(x: 76, y: 29), to: CGPoint(x: 46, y: 85))
        fill(VerseglassGlyph.accent, in: context, colors: [0xfff2e2, 0xf4c0cd],
             from: CGPoint(x: 71, y: 8), to: CGPoint(x: 91, y: 21))
        return rep
    }

    static func main() throws {
        let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let url = target.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                try image(size: points * scale).representation(using: .png, properties: [:])!.write(to: url)
            }
        }
    }
}
