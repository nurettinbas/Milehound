import XCTest
@testable import Milehound

final class VehicleExpenseEditorDraftTests: XCTestCase {
    func testAmountParsesWholeDigitsOnly() {
        var draft = VehicleExpenseEditorDraft()
        draft.amountText = "10000"
        XCTAssertEqual(draft.amount, 10_000)
    }

    func testAmountRejectsDecimalCommaOrDot() {
        var draft = VehicleExpenseEditorDraft()
        draft.amountText = "10.50"
        XCTAssertNil(draft.amount)

        draft.amountText = "10,50"
        XCTAssertNil(draft.amount)
    }

    func testAmountRejectsEmptyAndNonDigits() {
        var draft = VehicleExpenseEditorDraft()
        draft.amountText = ""
        XCTAssertNil(draft.amount)

        draft.amountText = "abc"
        XCTAssertNil(draft.amount)
    }

    func testPrefillFromExpenseUsesRoundedWholeNumber() {
        let expense = VehicleExpense(category: .fuel, amount: 1250.50, occurredAt: Date())
        let draft = VehicleExpenseEditorDraft(from: expense)
        XCTAssertEqual(draft.amountText, "1251")
        XCTAssertEqual(draft.amount, 1251)
    }

    func testReceiptSurvivesEditPrefill() {
        let expense = VehicleExpense(category: .service, amount: 900, receiptFileName: "saved.jpg")
        let draft = VehicleExpenseEditorDraft(from: expense)
        XCTAssertEqual(draft.receiptFileName, "saved.jpg")
        XCTAssertNil(draft.receiptToDeleteAfterSave)
        XCTAssertNil(draft.receiptToDeleteOnCancel)
    }

    func testRemovingSavedReceiptDeletesOnlyAfterSave() {
        let expense = VehicleExpense(category: .service, amount: 900, receiptFileName: "saved.jpg")
        var draft = VehicleExpenseEditorDraft(from: expense)
        XCTAssertNil(draft.removeReceipt(), "Saved file must stay on disk until Save")
        XCTAssertNil(draft.receiptFileName)
        XCTAssertEqual(draft.receiptToDeleteAfterSave, "saved.jpg")
        XCTAssertNil(draft.receiptToDeleteOnCancel)
    }

    func testReplacingReceiptCleansUpUnsavedFiles() {
        let expense = VehicleExpense(category: .service, amount: 900, receiptFileName: "saved.jpg")
        var draft = VehicleExpenseEditorDraft(from: expense)
        XCTAssertNil(draft.attachReceipt("new-1.jpg"))
        XCTAssertEqual(draft.attachReceipt("new-2.jpg"), "new-1.jpg")
        XCTAssertEqual(draft.receiptToDeleteOnCancel, "new-2.jpg")
        XCTAssertEqual(draft.receiptToDeleteAfterSave, "saved.jpg")
        XCTAssertEqual(draft.removeReceipt(), "new-2.jpg")
    }

    func testScannedAmountFillsWholeUnits() {
        var draft = VehicleExpenseEditorDraft()
        draft.applyScannedAmount(1_492)
        XCTAssertEqual(draft.amountText, "1492")
        XCTAssertEqual(draft.amount, 1_492)
    }
}
