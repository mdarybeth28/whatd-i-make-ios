import Foundation
import StoreKit

/// StoreKit 2, and only StoreKit 2 — no third-party purchase
/// SDK. Adapted from the Pet Keeper build's proven store.
///
/// What this store owns: loading the one subscription product
/// (StoreConfig.monthlyProductID, $12/month — the settled price
/// on every door), running a purchase, restoring purchases,
/// and watching for transactions that arrive on their own
/// (renewals, purchases on another device).
///
/// What it deliberately does NOT own: ACCESS. A verified
/// StoreKit transaction is handed — as its signed JWS — to the
/// server's Apple bridge (POST /billing/apple/verify), and the
/// SERVER writes subscription_status into the same fields the
/// Stripe webhook writes. The app then re-asks /auth/me. If
/// the server does not grant access, this store cannot and
/// will not let anyone in locally — the gate is the server's,
/// on this door exactly as on the web door.
@MainActor
final class SubscriptionStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingProducts
        case purchasing
        case restoring
        case failed(message: String)
    }

    @Published private(set) var product: Product?
    @Published private(set) var phase: Phase = .idle

    /// Set by the paywall: receives the signed transaction
    /// (JWS) of every verified transaction that arrives
    /// outside a purchase tap, so it can be confirmed with the
    /// server bridge the same way.
    var onVerifiedTransaction: ((String) async -> Void)?

    private var updatesTask: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .loadingProducts, .purchasing, .restoring: return true
        case .idle, .failed: return false
        }
    }

    // MARK: - Lifecycle

    /// Starts the transaction listener and loads the product.
    /// Safe to call repeatedly.
    func start() {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = update {
                        let jws = update.jwsRepresentation
                        await transaction.finish()
                        if transaction.productID == StoreConfig.monthlyProductID {
                            await self.onVerifiedTransaction?(jws)
                        }
                    }
                }
            }
        }
        Task { await loadProduct() }
    }

    // MARK: - Product

    func loadProduct() async {
        phase = .loadingProducts
        do {
            let loaded = try await Product.products(for: StoreConfig.allProductIDs)
            product = loaded.first { $0.id == StoreConfig.monthlyProductID }
            phase = .idle
        } catch {
            phase = .failed(message: "Could not load the subscription from Apple. Check your connection and try again.")
        }
    }

    // MARK: - Purchase

    /// Runs the purchase. On a verified success, returns the
    /// transaction's signed JWS — the caller sends it to the
    /// server bridge and re-asks the gate. Returns nil when
    /// nothing was bought (cancelled, pending, or failed);
    /// `phase` carries the honest words for the screen.
    func purchase() async -> String? {
        guard let product else {
            phase = .failed(message: "That subscription is not available right now. Try again in a moment.")
            return nil
        }
        phase = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    phase = .failed(message: "Apple could not verify that purchase, so it has not been counted. If you were charged, tap Restore purchases.")
                    return nil
                }
                let jws = verification.jwsRepresentation
                await transaction.finish()
                phase = .idle
                return jws
            case .userCancelled:
                phase = .idle
                return nil
            case .pending:
                phase = .failed(message: "Apple is still approving that purchase (for example, Ask to Buy). When it goes through, tap Restore purchases here.")
                return nil
            @unknown default:
                phase = .failed(message: "Apple returned something unexpected. Nothing has been counted here; tap Restore purchases to check.")
                return nil
            }
        } catch {
            phase = .failed(message: "The purchase did not finish: " + error.localizedDescription)
            return nil
        }
    }

    // MARK: - Restore

    /// AppStore.sync() re-presents this Apple account's
    /// purchases; the current entitlement's JWS (if any) goes
    /// back to the caller for the same server confirmation a
    /// fresh purchase gets. Restore, like purchase, never
    /// grants access locally.
    func restore() async -> String? {
        phase = .restoring
        do {
            try await AppStore.sync()
            let jws = await currentEntitlementJWS()
            phase = .idle
            return jws
        } catch {
            phase = .failed(message: "Restore did not finish: " + error.localizedDescription)
            return nil
        }
    }

    private func currentEntitlementJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == StoreConfig.monthlyProductID else { continue }
            guard transaction.revocationDate == nil else { continue }
            return result.jwsRepresentation
        }
        return nil
    }
}
