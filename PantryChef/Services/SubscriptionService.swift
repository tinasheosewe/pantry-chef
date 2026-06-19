import Foundation
import StoreKit

/// PantryChef Plus, the single paid tier (StoreKit 2). One auto-renewable product with
/// a 7-day intro free trial: "trial → paid." `isPlus` is the one flag the app reads to
/// gate Pro features — true while the subscription is active, *including* the trial.
///
/// Kept deliberately thin and self-contained: it loads the product (for the paywall's
/// localized price), exposes the entitlement, and handles purchase / restore. Renewals,
/// refunds, Ask-to-Buy approvals, and purchases on other devices flow in through the
/// transaction listener, so the gate never goes stale.
@MainActor
@Observable
final class SubscriptionService {
    /// The single auto-renewable "Plus" product id (annual, 7-day intro free trial).
    /// Mirrored in `PantryChef.storekit` for local testing and App Store Connect.
    static let plusProductID = "com.tboya.pantrychef.plus.yearly"

    /// The Plus product, once loaded — drives the paywall's price line.
    private(set) var product: Product?
    /// The entitlement the rest of the app reads. True while Plus is active (trial included).
    private(set) var isPlus = false
    /// Products couldn't be fetched (offline, or not configured) — the paywall softens.
    private(set) var loadFailed = false
    var purchaseError: String?

    init() {
        // Keep the entitlement live across renewals / refunds / cross-device buys.
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = update { await t.finish() }
                await self.refreshEntitlement()
            }
        }
        Task { await load(); await refreshEntitlement() }
    }

    /// Fetch the Plus product so the paywall can show its real localized price.
    func load() async {
        do {
            product = try await Product.products(for: [Self.plusProductID]).first
            loadFailed = (product == nil)
        } catch {
            loadFailed = true
        }
    }

    /// Recompute `isPlus` from the current entitlements (the source of truth).
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == Self.plusProductID, t.revocationDate == nil {
                active = true
            }
        }
        isPlus = active
    }

    /// Start the free trial / buy Plus. Returns whether the user is now subscribed.
    @discardableResult
    func purchase() async -> Bool {
        guard let product else { return false }
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification { await t.finish() }
                await refreshEntitlement()
                return isPlus
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = "Couldn’t complete the purchase. Please try again."
            return false
        }
    }

    /// Restore an existing subscription (re-sync with the App Store).
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    /// "$29.99/year" for the paywall, or nil until the product loads.
    var priceText: String? {
        guard let product else { return nil }
        let period = product.subscription?.subscriptionPeriod
        return period.map { "\(product.displayPrice)/\(unitLabel($0.unit))" } ?? product.displayPrice
    }

    /// "7-day free trial" — the intro offer, when present.
    var trialText: String? {
        guard let offer = product?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        return "\(p.value)-\(unitLabel(p.unit)) free trial"
    }

    private func unitLabel(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"; case .week: return "week"
        case .month: return "month"; case .year: return "year"
        @unknown default: return "period"
        }
    }
}
