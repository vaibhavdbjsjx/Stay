import SwiftUI

/// Stay's type scale. Display styles use the serif (New York) for warmth;
/// interface text uses the rounded system face. Every style is built on a
/// text style so it scales with Dynamic Type.
enum StayFont {
    static let hero = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let display = Font.system(.title, design: .serif).weight(.semibold)
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded)
    static let bodyEmphasis = Font.system(.body, design: .rounded).weight(.semibold)
    static let callout = Font.system(.callout, design: .rounded)
    static let caption = Font.system(.footnote, design: .rounded)
    static let captionEmphasis = Font.system(.footnote, design: .rounded).weight(.semibold)
    static let eyebrow = Font.system(.caption, design: .rounded).weight(.bold)
    /// Big timer digits. Monospaced so the layout never jitters.
    static let timer = Font.system(size: 64, weight: .light, design: .rounded).monospacedDigit()
    static let metric = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
}

extension View {
    /// Small uppercase label above a section or card.
    func eyebrowStyle(_ color: Color = StayPalette.inkSecondary) -> some View {
        font(StayFont.eyebrow)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(color)
    }
}
