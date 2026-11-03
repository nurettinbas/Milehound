import SwiftUI
import XCTest
@testable import Milehound

@MainActor
final class DeleteConfirmPresenterTests: XCTestCase {
    override func tearDown() {
        DeleteConfirmPresenter.shared.cancel()
        DeleteConfirmPresenter.shared.hideProgress()
        super.tearDown()
    }

    /// Cancel must not run `onConfirm`. Swipe-to-delete uses `confirmingDeleteSwipe`,
    /// which must not use `Button(role: .destructive)` or List removes the row first.
    /// The overlay host must not implicit-animate the list when this request changes.
    func testCancelDoesNotPerform() {
        var didRun = false
        DeleteConfirmPresenter.shared.confirm(.generic) {
            didRun = true
        }

        XCTAssertNotNil(DeleteConfirmPresenter.shared.request)
        DeleteConfirmPresenter.shared.cancel()
        XCTAssertFalse(didRun)
        XCTAssertNil(DeleteConfirmPresenter.shared.request)
    }

    func testConfirmPerformsAndClearsRequest() {
        var didRun = false
        DeleteConfirmPresenter.shared.confirm(.generic) {
            didRun = true
        }

        DeleteConfirmPresenter.shared.performConfirm()
        XCTAssertTrue(didRun)
        XCTAssertNil(DeleteConfirmPresenter.shared.request)
    }

    func testNewRequestReplacesOpenOneWithoutRunningIt() {
        var firstRan = false
        var secondRan = false
        DeleteConfirmPresenter.shared.confirm(.generic) {
            firstRan = true
        }
        DeleteConfirmPresenter.shared.confirm(.category) {
            secondRan = true
        }

        XCTAssertEqual(
            DeleteConfirmPresenter.shared.request?.title,
            DeleteConfirmKind.category.title
        )
        DeleteConfirmPresenter.shared.performConfirm()
        XCTAssertFalse(firstRan)
        XCTAssertTrue(secondRan)
    }

    func testKindCopyIsNonEmpty() {
        let kinds: [DeleteConfirmKind] = [
            .generic,
            .vehicle(isActivePaired: false),
            .vehicle(isActivePaired: true),
            .journalRemove,
            .category,
            .installmentPlan(count: 6),
            .vehiclePhoto,
            .notificationsAll
        ]

        for kind in kinds {
            XCTAssertFalse(kind.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(kind)")
            XCTAssertFalse(kind.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(kind)")
            XCTAssertFalse(kind.confirmTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(kind)")
        }
    }

    func testVehicleKindUsesActiveCopyWhenPaired() {
        XCTAssertEqual(
            DeleteConfirmKind.vehicle(isActivePaired: false).message,
            L10n.pairingTabDeleteVehicleMessage
        )
        XCTAssertEqual(
            DeleteConfirmKind.vehicle(isActivePaired: true).message,
            L10n.pairingTabDeleteVehicleMessageActive
        )
        XCTAssertNotEqual(
            DeleteConfirmKind.vehicle(isActivePaired: false).message,
            DeleteConfirmKind.vehicle(isActivePaired: true).message
        )
    }

    func testJournalRemoveCopyDiffersFromGeneric() {
        XCTAssertNotEqual(DeleteConfirmKind.journalRemove.message, DeleteConfirmKind.generic.message)
        XCTAssertEqual(DeleteConfirmKind.journalRemove.confirmTitle, L10n.journalRemove)
    }

    func testProminentMergeAccentFollowsPaletteNotSystemBlue() {
        let rose = ShellPalette.rose.tintColor(for: .light)
        let sky = ShellPalette.sky.tintColor(for: .light)
        XCTAssertNotEqual(rose, sky)
        XCTAssertNotEqual(rose, Color.blue)
        XCTAssertNotEqual(rose, Color.accentColor)
        XCTAssertEqual(
            ShellPalette.magenta.tintColor(for: .light),
            ShellPalette.magenta.atmosphere(for: .light).tint.color
        )
    }

    func testProminentMergeConfirmDoesNotUseDestructiveChrome() {
        DeleteConfirmPresenter.shared.present(
            title: L10n.tripsMergeTitle,
            message: L10n.tripsMergeMessage(2),
            confirmTitle: L10n.actionMerge,
            role: .prominent
        ) {}

        let request = DeleteConfirmPresenter.shared.request
        XCTAssertEqual(request?.role, .prominent)
        XCTAssertEqual(request?.title, L10n.tripsMergeTitle)
        XCTAssertEqual(request?.confirmTitle, L10n.actionMerge)
        XCTAssertEqual(request?.systemImage, "arrow.triangle.merge")
        XCTAssertNil(DeleteConfirmPresenter.shared.progressMessage)
    }

    func testShowProgressClearsConfirmAndBlocksUntilHidden() {
        DeleteConfirmPresenter.shared.present(
            title: L10n.tripsMergeTitle,
            message: L10n.tripsMergeMessage(2),
            confirmTitle: L10n.actionMerge,
            role: .prominent
        ) {}
        XCTAssertTrue(DeleteConfirmPresenter.shared.isBlocking)

        DeleteConfirmPresenter.shared.showProgress(L10n.tripsMergeProgress)
        XCTAssertNil(DeleteConfirmPresenter.shared.request)
        XCTAssertEqual(DeleteConfirmPresenter.shared.progressMessage, L10n.tripsMergeProgress)
        XCTAssertTrue(DeleteConfirmPresenter.shared.isProgressVisible)
        XCTAssertTrue(DeleteConfirmPresenter.shared.isBlocking)

        DeleteConfirmPresenter.shared.hideProgress()
        XCTAssertFalse(DeleteConfirmPresenter.shared.isProgressVisible)
        XCTAssertFalse(DeleteConfirmPresenter.shared.isBlocking)
    }

    func testCancelDoesNotClearProgress() {
        DeleteConfirmPresenter.shared.showProgress(L10n.tripsMergeProgress)
        DeleteConfirmPresenter.shared.cancel()
        XCTAssertEqual(DeleteConfirmPresenter.shared.progressMessage, L10n.tripsMergeProgress)
    }
}
