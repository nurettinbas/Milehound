import XCTest
@testable import Milehound

@MainActor
final class ShortcutsSetupStoreTests: XCTestCase {
    func testPersistsTriggerVehicleAndChecklistOnStandardSuite() {
        let defaults = UserDefaults(suiteName: "test.milehound.shortcuts.setup.\(UUID().uuidString)")!
        let store = ShortcutsSetupStore(userDefaults: defaults)

        store.persistTrigger(.carplay)
        let vehicleID = UUID()
        store.persistVehicleID(vehicleID)
        store.toggle(.silentStart)

        let reloaded = ShortcutsSetupStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.trigger, .carplay)
        XCTAssertEqual(reloaded.vehicleID, vehicleID)
        XCTAssertTrue(reloaded.isChecked(.silentStart))
        XCTAssertFalse(reloaded.isChecked(.locationAlways))
    }

    func testWatchReachesInsideWindowAndExpiresAfterTenMinutes() {
        let defaults = UserDefaults(suiteName: "test.milehound.shortcuts.watch.\(UUID().uuidString)")!
        let store = ShortcutsSetupStore(userDefaults: defaults)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.armExternalStartWatch(at: start)

        XCTAssertTrue(store.consumePendingWatchIfReached(now: start.addingTimeInterval(9 * 60)))
        XCTAssertNil(store.pendingWatchAt)

        store.armExternalStartWatch(at: start)
        XCTAssertFalse(store.consumePendingWatchIfReached(now: start.addingTimeInterval(11 * 60)))
        XCTAssertNil(store.pendingWatchAt)
    }

    func testWizardTestDoesNotConsumeWatch() {
        let defaults = UserDefaults(suiteName: "test.milehound.shortcuts.watchtest.\(UUID().uuidString)")!
        let store = ShortcutsSetupStore(userDefaults: defaults)
        store.armExternalStartWatch()
        store.markTestInFlight()

        XCTAssertTrue(store.consumeTestInFlight())
        XCTAssertFalse(store.consumePendingWatchIfReached())
        XCTAssertNotNil(store.pendingWatchAt)
    }
}

final class ShortcutsWizardTestClassifierTests: XCTestCase {
    func testNoVehicleWins() {
        XCTAssertEqual(
            ShortcutsWizardTestClassifier.classify(
                hasVehicle: false,
                awaitingConfirmation: true,
                isRecording: true,
                locationAlways: true
            ),
            .noVehicle
        )
    }

    func testConfirmBeforeRecording() {
        XCTAssertEqual(
            ShortcutsWizardTestClassifier.classify(
                hasVehicle: true,
                awaitingConfirmation: true,
                isRecording: false,
                locationAlways: true
            ),
            .awaitingConfirmation
        )
    }

    func testRecordingStarted() {
        XCTAssertEqual(
            ShortcutsWizardTestClassifier.classify(
                hasVehicle: true,
                awaitingConfirmation: false,
                isRecording: true,
                locationAlways: false
            ),
            .recordingStarted
        )
    }

    func testLocationWhenIdle() {
        XCTAssertEqual(
            ShortcutsWizardTestClassifier.classify(
                hasVehicle: true,
                awaitingConfirmation: false,
                isRecording: false,
                locationAlways: false
            ),
            .locationNotAlways
        )
    }
}
