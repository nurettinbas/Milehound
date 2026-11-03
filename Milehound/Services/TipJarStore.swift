import Foundation
import StoreKit

/// Optional "Support the developer" tips. Consumables only; nothing is unlocked or stored.
@MainActor
final class TipJarStore: ObservableObject {
    static let shared = TipJarStore()

    nonisolated static let productIDs = [
        "com.milehound.app.tip.small",
        "com.milehound.app.tip.medium",
        "com.milehound.app.tip.large"
    ]

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var purchasingID: String?

    private var updatesTask: Task<Void, Never>?

    func load() async {
        guard loadState != .loading else { return }
        if loadState == .loaded, !products.isEmpty { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = Self.sortedByPrice(fetched)
            loadState = products.isEmpty ? .unavailable : .loaded
        } catch {
            products = []
            loadState = .unavailable
        }
    }

    /// Returns true when the tip went through and was finished.
    @discardableResult
    func tip(_ product: Product) async -> Bool {
        guard purchasingID == nil else { return false }
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    AppErrorPresenter.shared.present(L10n.settingsTipJarFailed)
                    return false
                }
                await transaction.finish()
                ToastPresenter.shared.show(.tipThanks)
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            AppErrorPresenter.shared.present(L10n.settingsTipJarFailed)
            return false
        }
    }

    /// Finishes tips that complete outside a live purchase call (Ask to Buy, interrupted sheets).
    func observeTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update,
                      TipJarStore.productIDs.contains(transaction.productID) else { continue }
                await transaction.finish()
            }
        }
    }

    nonisolated static func sortedByPrice(_ products: [Product]) -> [Product] {
        products.sorted { $0.price < $1.price }
    }
}
