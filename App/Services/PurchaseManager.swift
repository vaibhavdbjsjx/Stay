import Foundation
import StoreKit

/// StoreKit 2 purchases. Products are defined in Stay.storekit for local
/// testing and must be created with the same IDs in App Store Connect.
@MainActor
@Observable
final class PurchaseManager {
    enum ProductID {
        static let monthly = "com.vaibhavsg.stay.pro.monthly"
        static let yearly = "com.vaibhavsg.stay.pro.yearly"
        static let all = [yearly, monthly]
    }

    enum PurchaseResult {
        case purchased
        case pending
        case cancelled
    }

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var activeProductID: String?
    private(set) var renewalDate: Date?
    private(set) var willAutoRenew = false
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var isEligibleForTrial = true

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    var monthly: Product? { products.first { $0.id == ProductID.monthly } }
    var yearly: Product? { products.first { $0.id == ProductID.yearly } }

    var activePlanName: String? {
        switch activeProductID {
        case ProductID.monthly: String(localized: "Stay Pro Monthly")
        case ProductID.yearly: String(localized: "Stay Pro Yearly")
        default: nil
        }
    }

    func load() async {
        guard products.isEmpty else {
            await refreshEntitlements()
            return
        }
        isLoading = true
        loadError = nil
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = ProductID.all.compactMap { id in loaded.first { $0.id == id } }
            if products.isEmpty {
                loadError = String(localized: "The App Store didn't return any plans. Check your connection and try again.")
            }
        } catch {
            loadError = String(localized: "Couldn't reach the App Store. Check your connection and try again.")
        }
        if let subscription = yearly?.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
        isLoading = false
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async throws -> PurchaseResult {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return .cancelled }
            await transaction.finish()
            await refreshEntitlements()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var pro = false
        var active: String?
        var renewal: Date?
        var renews = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  ProductID.all.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < .now { continue }
            pro = true
            active = transaction.productID
            if transaction.productType == .autoRenewable {
                renewal = transaction.expirationDate
            }
        }
        let subscription = yearly?.subscription ?? monthly?.subscription
        let statuses = (try? await subscription?.status) ?? []
        if let status = statuses.first(where: { $0.state == .subscribed || $0.state == .inGracePeriod }) ?? statuses.first,
           case .verified(let info) = status.renewalInfo {
            renews = info.willAutoRenew
        }
        isPro = pro
        activeProductID = active
        renewalDate = renewal
        willAutoRenew = renews
    }

    /// "7-day free trial" style text for the yearly plan, if offered.
    func trialText(for product: Product) -> String? {
        guard isEligibleForTrial, let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        let days = switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        @unknown default: period.value
        }
        return String(localized: "\(days)-day free trial")
    }

    func periodText(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return String(localized: "one-time purchase") }
        switch period.unit {
        case .month: return String(localized: "per month")
        case .year: return String(localized: "per year")
        case .week: return String(localized: "per week")
        case .day: return String(localized: "per day")
        @unknown default: return ""
        }
    }

    /// Yearly price expressed per month, for the comparison line.
    func monthlyEquivalent(for product: Product) -> String? {
        guard product.subscription?.subscriptionPeriod.unit == .year else { return nil }
        let perMonth = product.price / 12
        return perMonth.formatted(product.priceFormatStyle)
    }
}
