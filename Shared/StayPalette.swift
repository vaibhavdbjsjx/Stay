import SwiftUI
import UIKit

/// Stay's warm, calm palette. Every colour has a tuned light and dark variant.
enum StayPalette {
    static let ink = dynamic(0x2A2420, 0xF4EDE4)
    static let inkSecondary = dynamic(0x6E645B, 0xB9AEA2)
    static let inkTertiary = dynamic(0x9C9187, 0x857B71)
    static let canvas = dynamic(0xFBF6EF, 0x14120F)
    static let surface = dynamic(0xFFFFFF, 0x211D19)
    static let surfaceRaised = dynamic(0xF4ECE1, 0x2B2621)
    static let sage = dynamic(0x3F6B5E, 0x86B9A8)
    static let sageDeep = dynamic(0x24443B, 0x1B2E28)
    static let sageSoft = dynamic(0xDDE9E3, 0x23352F)
    static let apricot = dynamic(0xE07F52, 0xF2A477)
    static let apricotSoft = dynamic(0xFBE3D4, 0x3B2A20)
    static let cream = dynamic(0xFBF3E6, 0xFBF3E6)
    static let calm = dynamic(0x4E8F69, 0x84C79F)
    static let alert = dynamic(0xC9533F, 0xF08A76)
    static let amber = dynamic(0xC98A1E, 0xF0BC5E)
    static let hairline = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.07)
    })

    /// The signature gradient used behind hero moments and the app icon.
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x4A7A6B), Color(hex: 0x24443B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sunriseGradient = LinearGradient(
        colors: [Color(hex: 0xF6B48A), Color(hex: 0xE07F52)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
