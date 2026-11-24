import AppKit
import SwiftUI

/// Shared artwork in a 100-point, top-left-origin square.
enum VerseglassGlyph {
    static let fold: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 4, y: 19))
        p.addQuadCurve(to: CGPoint(x: 9, y: 16), control: CGPoint(x: 4, y: 16))
        p.addLine(to: CGPoint(x: 26, y: 16))
        p.addQuadCurve(to: CGPoint(x: 35, y: 23), control: CGPoint(x: 32, y: 16))
        p.addLine(to: CGPoint(x: 57, y: 70))
        p.addLine(to: CGPoint(x: 52, y: 82))
        p.addQuadCurve(to: CGPoint(x: 47, y: 85), control: CGPoint(x: 50, y: 85))
        p.addLine(to: CGPoint(x: 41, y: 85))
        p.addQuadCurve(to: CGPoint(x: 34, y: 80), control: CGPoint(x: 36, y: 85))
        p.closeSubpath()
        return p.copy()!
    }()

    static let blade: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 34, y: 80))
        p.addQuadCurve(to: CGPoint(x: 40, y: 79), control: CGPoint(x: 37, y: 86))
        p.addLine(to: CGPoint(x: 62, y: 35))
        p.addQuadCurve(to: CGPoint(x: 71, y: 29), control: CGPoint(x: 65, y: 29))
        p.addLine(to: CGPoint(x: 88, y: 29))
        p.addLine(to: CGPoint(x: 62, y: 80))
        p.addQuadCurve(to: CGPoint(x: 55, y: 85), control: CGPoint(x: 60, y: 85))
        p.addLine(to: CGPoint(x: 41, y: 85))
        p.addQuadCurve(to: CGPoint(x: 34, y: 80), control: CGPoint(x: 36, y: 85))
        p.closeSubpath()
        return p.copy()!
    }()

    static let accent: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 68, y: 21))
        p.addLine(to: CGPoint(x: 72, y: 13))
        p.addQuadCurve(to: CGPoint(x: 80, y: 8), control: CGPoint(x: 75, y: 8))
        p.addLine(to: CGPoint(x: 96, y: 8))
        p.addLine(to: CGPoint(x: 92, y: 16))
        p.addQuadCurve(to: CGPoint(x: 84, y: 21), control: CGPoint(x: 89, y: 21))
        p.closeSubpath()
        return p.copy()!
    }()

    static var silhouette: CGPath {
        let p = CGMutablePath()
        for part in [fold, blade, accent] { p.addPath(part) }
        return p.copy()!
    }
}

struct VerseglassMark: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height)
        var transform = CGAffineTransform(translationX: rect.midX - length / 2,
                                          y: rect.midY - length / 2)
            .scaledBy(x: length / 100, y: length / 100)
        return Path(VerseglassGlyph.silhouette.copy(using: &transform)!)
    }

    @MainActor static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: rect.midX - 9, y: rect.midY - 9)
            context.scaleBy(x: 0.18, y: 0.18)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(VerseglassGlyph.silhouette)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Verseglass lyrics"
        return image
    }
}
