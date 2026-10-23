import SwiftUI
import UIKit

// MARK: - Haptics

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat = 20
    var fill: Color = StayPalette.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(StayPalette.hairline))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }
}

extension View {
    func stayCard(padding: CGFloat = 20, fill: Color = StayPalette.surface) -> some View {
        modifier(CardModifier(padding: padding, fill: fill))
    }

    /// Standard warm background for full screens.
    func stayBackground() -> some View {
        background(StayPalette.canvas.ignoresSafeArea())
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = StayPalette.sage
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StayFont.headline)
            .foregroundStyle(Color.white)
            .padding(.vertical, 17)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = StayPalette.sage

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StayFont.headline)
            .foregroundStyle(tint)
            .padding(.vertical, 15)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(StayPalette.sageSoft, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var stayPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func stayPrimary(_ tint: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var staySecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Motion

/// Fades and lifts content in on first appearance, staggered by `index`.
/// Falls back to a plain fade when Reduce Motion is on.
struct RevealModifier: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.55, dampingFraction: 0.86).delay(Double(index) * 0.06)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    func reveal(_ index: Int = 0) -> some View { modifier(RevealModifier(index: index)) }
}

/// Subtle press feedback for tappable cards.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Small pieces

struct Pill: View {
    var text: String
    var symbol: String?
    var tint: Color = StayPalette.sage
    var fill: Color = StayPalette.sageSoft

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(StayFont.captionEmphasis)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(fill, in: Capsule())
    }
}

struct IconBadge: View {
    var symbol: String
    var tint: Color = StayPalette.sage
    var fill: Color = StayPalette.sageSoft
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct MetricTile: View {
    var value: String
    var label: String
    var symbol: String
    var tint: Color = StayPalette.sage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(StayFont.metric)
                .foregroundStyle(StayPalette.ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(StayFont.caption)
                .foregroundStyle(StayPalette.inkSecondary)
        }
        .stayCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(StayFont.title).foregroundStyle(StayPalette.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Dog photo or a warm monogram when no photo is set.
struct DogAvatar: View {
    var dog: Dog?
    var size: CGFloat = 44
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let dog, let image = model.photo(for: dog) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    StayPalette.sunriseGradient
                    if let dog, !dog.initials.isEmpty {
                        Text(dog.initials)
                            .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: size > 60 ? 3 : 1.5))
        .accessibilityLabel(dog.map { String(localized: "Photo of \($0.name)") } ?? String(localized: "Dog photo"))
    }
}

/// A gentle illustrated empty state built from SF Symbols.
struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(StayPalette.sageSoft).frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(StayPalette.sage)
            }
            .accessibilityHidden(true)
            Text(title).font(StayFont.headline).foregroundStyle(StayPalette.ink)
            Text(message)
                .font(StayFont.callout)
                .foregroundStyle(StayPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Circular progress ring used by the mission timer.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = StayPalette.sage
    var track: Color = StayPalette.sageSoft

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0.001, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
        .accessibilityHidden(true)
    }
}

/// Bars for a short sound-level timeline.
struct LevelSparkline: View {
    var levels: [Float]
    var tint: Color = StayPalette.sage
    var highlight: Color = StayPalette.apricot

    var body: some View {
        GeometryReader { proxy in
            let shown = Array(levels.suffix(max(1, Int(proxy.size.width / 5))))
            HStack(alignment: .center, spacing: 2) {
                ForEach(shown.indices, id: \.self) { index in
                    let level = CGFloat(shown[index])
                    Capsule()
                        .fill(level > 0.6 ? highlight : tint.opacity(0.35 + level * 0.65))
                        .frame(width: 3, height: max(3, level * proxy.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }
}
