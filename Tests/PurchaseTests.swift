import StoreKitTest
import XCTest
@testable import Stay

/// Exercises the real StoreKit 2 code paths against Stay.storekit.
@MainActor
final class PurchaseTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        // The simulator can read the project folder, so use the same file the app scheme uses.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Stay.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    func testProductsLoadInPaywallOrder() async {
        let manager = PurchaseManager()
        await manager.load()
        XCTAssertEqual(manager.products.map(\.id), [PurchaseManager.ProductID.yearly, PurchaseManager.ProductID.monthly, PurchaseManager.ProductID.lifetime])
        XCTAssertFalse(manager.isPro)
        if let yearly = manager.yearly {
            XCTAssertEqual(manager.trialText(for: yearly), "7-day free trial")
            XCTAssertNotNil(manager.monthlyEquivalent(for: yearly))
        } else {
            XCTFail("Yearly plan missing")
        }
    }

    func testBuyingYearlyUnlocksPro() async throws {
        let manager = PurchaseManager()
        await manager.load()
        let yearly = try XCTUnwrap(manager.yearly)
        let result = try await manager.purchase(yearly)
        XCTAssertEqual(result, .purchased)
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.activeProductID, PurchaseManager.ProductID.yearly)
    }

    func testLifetimeSurvivesRestore() async throws {
        let manager = PurchaseManager()
        await manager.load()
        _ = try await manager.purchase(try XCTUnwrap(manager.lifetime))
        let fresh = PurchaseManager()
        await fresh.load()
        XCTAssertTrue(fresh.isPro)
        XCTAssertEqual(fresh.activePlanName, "Stay Pro Lifetime")
    }
}
