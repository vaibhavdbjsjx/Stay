import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = PurchaseManager.ProductID.yearly
    @State private var purchasing = false
    @State private var message: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var selected: Product? { purchases.products.first { $0.id == selectedID } }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                plans.reveal(1)
                features.reveal(2)
                if let message {
                    Text(message).font(StayFont.callout).foregroundStyle(StayPalette.alert).multilineTextAlignment(.center)
                }
                if typeSize.isAccessibilitySize {
                    ctaDetailText
                }
                legal
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .stayBackground()
        .safeAreaInset(edge: .bottom) { cta }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(StayPalette.cream)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.25), in: Circle())
            }
            .accessibilityLabel(Text("Close"))
            .padding(16)
        }
        .task { await purchases.load() }
        .onChange(of: purchases.isPro) { _, isPro in
            if isPro {
                model.connectLinks()
                Haptics.success()
                dismiss()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            StayMark(faceColor: Color(hex: 0x24443B))
                .frame(width: 96, height: 96)
                .padding(.top, 50)
            Text("Stay Pro").font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(StayPalette.cream)
            Text("Everything you need to help \(model.selectedDog?.name ?? String(localized: "your dog")) feel safe home alone.")
                .font(StayFont.body)
                .foregroundStyle(StayPalette.cream.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(StayPalette.heroGradient.padding(.horizontal, -20).padding(.top, -200))
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaywallFeature(symbol: "infinity", title: String(localized: "Unlimited monitored missions"), detail: String(localized: "Free includes the baseline and 3 missions."))
            PaywallFeature(symbol: "bell.badge.waveform.fill", title: String(localized: "Alerts away from home"), detail: String(localized: "Instant push and a near-live view through your iCloud."))
            PaywallFeature(symbol: "sparkles", title: String(localized: "Weekly coach insights"), detail: String(localized: "Personalised on device, with Apple Intelligence where available."))
            PaywallFeature(symbol: "doc.richtext.fill", title: String(localized: "Trainer & vet report"), detail: String(localized: "A clear PDF of every session and the plan."))
            PaywallFeature(symbol: "pawprint.fill", title: String(localized: "Multiple dogs"), detail: String(localized: "A separate plan for every dog in your home."))
        }
        .stayCard()
    }

    @ViewBuilder
    private var plans: some View {
        if purchases.products.isEmpty {
            VStack(spacing: 12) {
                if purchases.isLoading {
                    ProgressView()
                } else {
                    Text(purchases.loadError ?? String(localized: "Plans are unavailable right now."))
                        .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.center)
                    Button("Try again") { Task { await purchases.load() } }.buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 12) {
                ForEach(purchases.products) { product in
                    PlanOption(product: product, selected: product.id == selectedID, badge: badge(for: product)) {
                        Haptics.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedID = product.id }
                    }
                }
            }
        }
    }

    private func badge(for product: Product) -> String? {
        switch product.id {
        case PurchaseManager.ProductID.yearly:
            if let monthly = purchases.monthly, monthly.price > 0 {
                let saving = 1 - (product.price / (monthly.price * 12))
                let percent = Int((NSDecimalNumber(decimal: saving).doubleValue * 100).rounded())
                return percent > 0 ? String(localized: "Save \(percent)%") : nil
            }
            return String(localized: "Best value")
        case PurchaseManager.ProductID.lifetime:
            return String(localized: "Pay once")
        default:
            return nil
        }
    }

    private var cta: some View {
        VStack(spacing: 8) {
            Button {
                guard let selected else { return }
                purchase(selected)
            } label: {
                if purchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaTitle)
                }
            }
            .buttonStyle(.stayPrimary(StayPalette.apricot))
            .disabled(selected == nil || purchasing)
            if !typeSize.isAccessibilitySize {
                ctaDetailText
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(StayPalette.canvas.opacity(0.97))
    }

    private var ctaDetailText: some View {
        Text(ctaDetail)
            .font(StayFont.caption)
            .foregroundStyle(StayPalette.inkSecondary)
            .multilineTextAlignment(.center)
    }

    private var ctaTitle: String {
        guard let selected else { return String(localized: "Continue") }
        if purchases.trialText(for: selected) != nil { return String(localized: "Start 7-day free trial") }
        return selected.type == .nonConsumable ? String(localized: "Buy for \(selected.displayPrice)") : String(localized: "Subscribe for \(selected.displayPrice)")
    }

    private var ctaDetail: String {
        guard let selected else { return "" }
        if selected.type == .nonConsumable {
            return String(localized: "One-time purchase of \(selected.displayPrice). No subscription.")
        }
        let period = purchases.periodText(for: selected)
        if let trial = purchases.trialText(for: selected) {
            return String(localized: "\(trial), then \(selected.displayPrice) \(period). Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before the trial ends and you won't be charged.")
        }
        return String(localized: "\(selected.displayPrice) \(period). Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before renewal.")
    }

    private var legal: some View {
        VStack(spacing: 12) {
            Button("Restore purchases") {
                Task {
                    do {
                        try await purchases.restore()
                        if !purchases.isPro { message = String(localized: "No previous purchases were found for this Apple Account.") }
                    } catch {
                        message = String(localized: "Couldn't reach the App Store. Please try again.")
                    }
                }
            }
            .font(StayFont.bodyEmphasis)
            Text("Payment is charged to your Apple Account at confirmation of purchase. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before the end of the period. Manage or cancel in your App Store account settings. Any unused part of a free trial is forfeited when you buy a subscription.")
                .font(StayFont.caption)
                .foregroundStyle(StayPalette.inkTertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Link("Terms of Use", destination: AppConfig.termsURL)
                Link("Privacy Policy", destination: AppConfig.privacyURL)
            }
            .font(StayFont.captionEmphasis)
        }
    }

    private func purchase(_ product: Product) {
        purchasing = true
        message = nil
        Task {
            do {
                switch try await purchases.purchase(product) {
                case .purchased: break
                case .pending: message = String(localized: "Your purchase is waiting for approval.")
                case .cancelled: break
                }
            } catch {
                message = String(localized: "The purchase couldn't be completed. Please try again.")
            }
            purchasing = false
        }
    }
}

private struct PaywallFeature: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, tint: StayPalette.apricot, fill: StayPalette.apricotSoft, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StayFont.bodyEmphasis).foregroundStyle(StayPalette.ink)
                Text(detail).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlanOption: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dynamicTypeSize) private var typeSize
    var product: Product
    var selected: Bool
    var badge: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
            layout {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selected ? StayPalette.apricot : StayPalette.inkTertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.displayName).font(StayFont.headline).foregroundStyle(StayPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let badge { Pill(text: badge, tint: .white, fill: StayPalette.apricot) }
                        if let trial = purchases.trialText(for: product) {
                            Text(trial).font(StayFont.captionEmphasis).foregroundStyle(StayPalette.calm)
                        } else if let perMonth = purchases.monthlyEquivalent(for: product) {
                            Text("\(perMonth) per month").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                        }
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(product.displayPrice).font(StayFont.headline).foregroundStyle(StayPalette.ink)
                    Text(purchases.periodText(for: product)).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(StayPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected ? StayPalette.apricot : StayPalette.hairline, lineWidth: selected ? 2 : 1))
            .scaleEffect(selected ? 1 : 0.985)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
