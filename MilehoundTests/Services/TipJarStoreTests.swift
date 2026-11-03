import StoreKit
import StoreKitTest
import XCTest
@testable import Milehound

@MainActor
final class TipJarStoreTests: XCTestCase {
    private var session: SKTestSession?

    private static var configurationURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Milehound/MilehoundTips.storekit")
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
        super.tearDown()
    }

    func testConfigurationListsTheThreeConsumableTips() throws {
        let data = try Data(contentsOf: Self.configurationURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(root["products"] as? [[String: Any]])
        XCTAssertEqual(products.compactMap { $0["productID"] as? String }, TipJarStore.productIDs)
        XCTAssertTrue(products.allSatisfy { $0["type"] as? String == "Consumable" })
        let prices = products.compactMap { ($0["displayPrice"] as? String).flatMap(Double.init) }
        XCTAssertEqual(prices, prices.sorted())
        for product in products {
            let localizations = product["localizations"] as? [[String: Any]] ?? []
            let locales = Set(localizations.compactMap { $0["locale"] as? String })
            XCTAssertEqual(locales, ["en_US", "tr_TR"])
        }
    }

    func testProductsLoadSortedByPrice() async throws {
        let products = try await loadProducts(TipJarStore.productIDs)
        XCTAssertEqual(Set(products.map(\.id)), Set(TipJarStore.productIDs))
        XCTAssertEqual(TipJarStore.sortedByPrice(products).map(\.id), TipJarStore.productIDs)
        XCTAssertTrue(products.allSatisfy { $0.type == .consumable })
    }

    func testLoadReusesCachedProducts() async throws {
        let session = try SKTestSession(contentsOf: Self.configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session

        let store = TipJarStore()
        await store.load()
        if store.loadState != .loaded {
            throw XCTSkip("StoreKit test session unavailable on this runner; run from Xcode.")
        }
        let ids = store.products.map(\.id)
        await store.load()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.products.map(\.id), ids)
        XCTAssertFalse(ids.isEmpty)
    }

    func testTipFinishesTheTransaction() async throws {
        let fetched = try await loadProducts(["com.milehound.app.tip.small"])
        let product = try XCTUnwrap(fetched.first)
        let store = TipJarStore()
        let succeeded = await store.tip(product)
        XCTAssertTrue(succeeded)
        XCTAssertNil(store.purchasingID)

        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        XCTAssertEqual(unfinished, 0)
    }

    /// The StoreKit test service is not reachable from every runner (for example `xcodebuild` without Xcode open).
    private func loadProducts(_ ids: [String]) async throws -> [Product] {
        let session = try SKTestSession(contentsOf: Self.configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
        let products = try await Product.products(for: ids)
        if products.isEmpty {
            throw XCTSkip("StoreKit test session unavailable on this runner; run from Xcode.")
        }
        return products
    }
}
