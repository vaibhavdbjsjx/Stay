// Generates the 1024×1024 App Store icon (and website assets) from code.
// Usage: swift scripts/make_icon.swift <output.png> [size]
// The geometry mirrors Shared/StayMark.swift.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "AppIcon-1024.png"
let size = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
let s = CGFloat(size)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }

// Flip to a top-left origin so unit coordinates match SwiftUI.
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

// Background: deep sage diagonal gradient with a soft warm glow.
let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x4F8070), rgb(0x24443B)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])
let glow = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.98, green: 0.82, blue: 0.66, alpha: 0.22), CGColor(srgbRed: 0.98, green: 0.82, blue: 0.66, alpha: 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.5, y: s * 0.62), startRadius: 0, endCenter: CGPoint(x: s * 0.5, y: s * 0.62), endRadius: s * 0.48, options: [])

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }

// House outline
let house = CGMutablePath()
house.move(to: p(0.20, 0.84))
house.addLine(to: p(0.20, 0.47))
house.addLine(to: p(0.50, 0.20))
house.addLine(to: p(0.80, 0.47))
house.addLine(to: p(0.80, 0.84))
ctx.addPath(house)
ctx.setStrokeColor(rgb(0xFBF3E6))
ctx.setLineWidth(s * 0.06)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// Dog silhouette
let dog = CGMutablePath()
dog.move(to: p(0.42, 0.64))
dog.addLine(to: p(0.58, 0.64))
dog.addQuadCurve(to: p(0.665, 0.845), control: p(0.655, 0.69))
dog.addQuadCurve(to: p(0.63, 0.87), control: p(0.67, 0.87))
dog.addLine(to: p(0.37, 0.87))
dog.addQuadCurve(to: p(0.335, 0.845), control: p(0.33, 0.87))
dog.addQuadCurve(to: p(0.42, 0.64), control: p(0.345, 0.69))
dog.closeSubpath()
dog.addEllipse(in: r(0.355, 0.43, 0.29, 0.27))
func ear(_ cx: CGFloat, _ cy: CGFloat, _ degrees: CGFloat) {
    var t = CGAffineTransform(translationX: cx * s, y: cy * s).rotated(by: degrees * .pi / 180)
    dog.addPath(CGPath(ellipseIn: CGRect(x: -0.055 * s, y: -0.11 * s, width: 0.11 * s, height: 0.22 * s), transform: &t))
}
ear(0.365, 0.555, 14)
ear(0.635, 0.555, -14)
ctx.addPath(dog)
ctx.setFillColor(rgb(0xF2A477))
ctx.fillPath()

// Face
ctx.setFillColor(rgb(0x24443B))
ctx.fillEllipse(in: r(0.425, 0.535, 0.036, 0.036))
ctx.fillEllipse(in: r(0.539, 0.535, 0.036, 0.036))
ctx.addPath(CGPath(roundedRect: r(0.47, 0.595, 0.06, 0.042), cornerWidth: 0.02 * s, cornerHeight: 0.02 * s, transform: nil))
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output) (\(size)px)")
