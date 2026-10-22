import SwiftUI

/// The Stay mark: a dog waiting calmly inside a home outline.
/// Geometry lives in a unit square so the same drawing powers the app icon,
/// onboarding hero, widgets and share cards.
enum StayMarkGeometry {
    static func house(in rect: CGRect) -> Path {
        let p = UnitMapper(rect)
        var path = Path()
        path.move(to: p.point(0.20, 0.84))
        path.addLine(to: p.point(0.20, 0.47))
        path.addLine(to: p.point(0.50, 0.20))
        path.addLine(to: p.point(0.80, 0.47))
        path.addLine(to: p.point(0.80, 0.84))
        return path
    }

    static func houseLineWidth(in rect: CGRect) -> CGFloat { min(rect.width, rect.height) * 0.06 }

    /// Head, ears and chest as one filled silhouette.
    static func dog(in rect: CGRect) -> Path {
        let p = UnitMapper(rect)
        var path = Path()
        // Chest, flaring out like a sitting dog
        path.move(to: p.point(0.42, 0.64))
        path.addLine(to: p.point(0.58, 0.64))
        path.addQuadCurve(to: p.point(0.665, 0.845), control: p.point(0.655, 0.69))
        path.addQuadCurve(to: p.point(0.63, 0.87), control: p.point(0.67, 0.87))
        path.addLine(to: p.point(0.37, 0.87))
        path.addQuadCurve(to: p.point(0.335, 0.845), control: p.point(0.33, 0.87))
        path.addQuadCurve(to: p.point(0.42, 0.64), control: p.point(0.345, 0.69))
        path.closeSubpath()
        // Head
        path.addEllipse(in: p.rect(0.355, 0.43, 0.29, 0.27))
        // Ears (soft, floppy)
        path.addPath(ear(center: p.point(0.365, 0.555), size: p.size(0.11, 0.22), angle: .degrees(14)))
        path.addPath(ear(center: p.point(0.635, 0.555), size: p.size(0.11, 0.22), angle: .degrees(-14)))
        return path
    }

    /// Eyes and nose, drawn in the background colour on top of the silhouette.
    static func face(in rect: CGRect) -> Path {
        let p = UnitMapper(rect)
        var path = Path()
        path.addEllipse(in: p.rect(0.425, 0.535, 0.036, 0.036))
        path.addEllipse(in: p.rect(0.539, 0.535, 0.036, 0.036))
        path.addRoundedRect(in: p.rect(0.47, 0.595, 0.06, 0.042), cornerSize: p.size(0.02, 0.02))
        return path
    }

    private static func ear(center: CGPoint, size: CGSize, angle: Angle) -> Path {
        let ellipse = Path(ellipseIn: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle.radians)
        return ellipse.applying(transform)
    }

    private struct UnitMapper {
        let rect: CGRect
        init(_ rect: CGRect) { self.rect = rect }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func size(_ w: CGFloat, _ h: CGFloat) -> CGSize {
            CGSize(width: w * rect.width, height: h * rect.height)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: point(x, y), size: size(w, h))
        }
    }
}

/// Renders the Stay mark with configurable colours.
struct StayMark: View {
    var houseColor: Color = StayPalette.cream
    var dogColor: Color = StayPalette.apricot
    var faceColor: Color = StayPalette.sageDeep

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            context.stroke(
                StayMarkGeometry.house(in: rect),
                with: .color(houseColor),
                style: StrokeStyle(lineWidth: StayMarkGeometry.houseLineWidth(in: rect), lineCap: .round, lineJoin: .round)
            )
            context.fill(StayMarkGeometry.dog(in: rect), with: .color(dogColor))
            context.fill(StayMarkGeometry.face(in: rect), with: .color(faceColor))
        }
        .accessibilityHidden(true)
    }
}

/// The mark on its signature rounded tile, as used for the app icon.
struct StayMarkTile: View {
    var cornerRadiusRatio: CGFloat = 0.225

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            RoundedRectangle(cornerRadius: side * cornerRadiusRatio, style: .continuous)
                .fill(StayPalette.heroGradient)
                .overlay(StayMark(faceColor: Color(hex: 0x24443B)).padding(side * 0.02))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
