import SwiftData
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class ExpenseReceiptStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ExpenseReceiptStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExpenseReceiptStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = ExpenseReceiptStore(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveDownsamplesAndLoads() async throws {
        let fileName = try await store.save(makeImage(width: 3_000, height: 4_000))
        XCTAssertTrue(store.exists(fileName: fileName))

        store.clearMemory()
        let image = await store.image(fileName: fileName)
        let loaded = try XCTUnwrap(image)
        let longest = max(loaded.size.width * loaded.scale, loaded.size.height * loaded.scale)
        XCTAssertLessThanOrEqual(longest, ExpenseReceiptStore.maxPixelSize)

        let thumbnail = await store.thumbnail(fileName: fileName)
        let thumb = try XCTUnwrap(thumbnail)
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), ExpenseReceiptStore.thumbnailPixelSize)
    }

    func testRemoveIfUnreferencedKeepsSharedInstallmentReceipt() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Receipt Car")
        context.insert(vehicle)
        let fileName = try await store.save(makeImage(width: 400, height: 600))

        let first = try VehicleExpenseInstallmentService.insert(
            category: .repair,
            totalAmount: 1_200,
            startDate: Date(),
            installmentCount: 3,
            note: nil,
            receiptFileName: fileName,
            vehicle: vehicle,
            in: context
        )
        let rows = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.receiptFileName == fileName })
        XCTAssertEqual(ExpenseReceiptStore.referenceCount(of: fileName, in: context), 3)

        context.delete(first)
        try context.save()
        store.removeIfUnreferenced(fileName: fileName, in: context)
        XCTAssertTrue(store.exists(fileName: fileName))

        for row in try context.fetch(FetchDescriptor<VehicleExpense>()) {
            context.delete(row)
        }
        try context.save()
        XCTAssertEqual(ExpenseReceiptStore.referenceCount(of: fileName, in: context), 0)
        store.removeIfUnreferenced(fileName: fileName, in: context)
        try await waitUntil { !self.store.exists(fileName: fileName) }
    }

    func testReplaceCarriesReceiptToEverySlice() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Replace Car")
        context.insert(vehicle)
        let first = try VehicleExpenseInstallmentService.insert(
            category: .casco,
            totalAmount: 600,
            startDate: Date(),
            installmentCount: 2,
            note: nil,
            receiptFileName: "old.jpg",
            vehicle: vehicle,
            in: context
        )
        _ = try VehicleExpenseInstallmentService.replace(
            existing: first,
            category: .casco,
            totalAmount: 900,
            startDate: Date(),
            installmentCount: 3,
            note: nil,
            receiptFileName: "new.jpg",
            in: context
        )
        let rows = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.receiptFileName == "new.jpg" })
        XCTAssertEqual(ExpenseReceiptStore.referenceCount(of: "old.jpg", in: context), 0)
    }

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
