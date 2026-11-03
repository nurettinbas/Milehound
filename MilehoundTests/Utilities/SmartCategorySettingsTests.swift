import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class SmartCategorySettingsTests: XCTestCase {
    func testSuggestionsDefaultOnWhenKeyMissing() {
        let defaults = UserDefaults(suiteName: "test.milehound.smartcat.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        XCTAssertTrue(settings.smartCategorySuggestionsEnabled)
    }

    func testSuggestionsCanBeDisabled() {
        let defaults = UserDefaults(suiteName: "test.milehound.smartcat.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.smartCategorySuggestionsEnabled = false
        XCTAssertFalse(settings.smartCategorySuggestionsEnabled)
    }

    func testWorkHoursDefaultAndClamp() {
        let defaults = UserDefaults(suiteName: "test.milehound.smartcat.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        XCTAssertEqual(settings.workHourStart, 9)
        XCTAssertEqual(settings.workHourEnd, 18)

        settings.workHourStart = 99
        settings.workHourEnd = 99
        XCTAssertEqual(settings.workHourStart, 23)
        XCTAssertEqual(settings.workHourEnd, 23)
    }
}

final class UITestSupportHostTests: XCTestCase {
    func testUnitTestHostSkipsExternalEffects() {
        XCTAssertTrue(UITestSupport.isUnitTesting)
        XCTAssertTrue(UITestSupport.shouldSkipExternalEffects)
        XCTAssertFalse(UITestSupport.isEnabled)
    }
}

@MainActor
final class SmartCategorySeedTests: XCTestCase {
    func testSeededCommuteIsNewestRowWithPendingSuggestion() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let older = PreviewData.sampleTrip
        context.insert(older)
        for point in older.points {
            context.insert(point)
        }

        UITestSupport.seedSmartCategoryFixtures(in: context)
        try context.save()

        var descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let trips = try context.fetch(descriptor)
        let first = try XCTUnwrap(trips.first)
        XCTAssertEqual(first.id, UITestSupport.smartCategorySeedTripID)
        XCTAssertTrue(first.hasPendingCategorySuggestion)
        XCTAssertGreaterThan(first.startedAt, older.startedAt)
        XCTAssertGreaterThanOrEqual(first.points.count, 2)

        UITestSupport.seedSmartCategoryFixtures(in: context)
        try context.save()
        descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let refreshed = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertEqual(refreshed.id, UITestSupport.smartCategorySeedTripID)
        XCTAssertTrue(refreshed.hasPendingCategorySuggestion)
    }
}

final class SmartCategoryToastTests: XCTestCase {
    func testCategoryAcceptedMessageIsDistinctFromJournalTitleRequired() {
        XCTAssertEqual(ToastKind.categoryAccepted.message, L10n.toastCategoryAccepted)
        XCTAssertEqual(ToastKind.journalTitleRequired.message, L10n.journalTitleRequired)
        XCTAssertNotEqual(ToastKind.categoryAccepted.message, ToastKind.journalTitleRequired.message)
    }

    func testToastKindsExposeSymbolsAndHaptics() {
        XCTAssertEqual(ToastKind.journalSaved.message, L10n.toastJournalSaved)
        XCTAssertEqual(ToastKind.journalSaved.systemImage, "book.closed.fill")
        XCTAssertEqual(ToastKind.journalSaved.hapticStyle, .success)
        XCTAssertEqual(ToastKind.categoryAccepted.systemImage, "sparkles")
        XCTAssertEqual(ToastKind.categoryAccepted.symbolAnimation, .pulse)
        XCTAssertEqual(ToastKind.deleted.systemImage, "trash.fill")
        XCTAssertEqual(ToastKind.deleted.hapticStyle, .destructive)
        XCTAssertEqual(ToastKind.deleted.emblemTone, .destructive)
        XCTAssertEqual(ToastKind.journalTitleRequired.hapticStyle, .warning)
        XCTAssertEqual(ToastKind.journalTitleRequired.symbolAnimation, .wiggle)
        XCTAssertEqual(ToastKind.tripsMerged.hapticStyle, .merge)
        XCTAssertEqual(ToastKind.shortcutsAutomationReached.hapticStyle, .automation)
        XCTAssertEqual(ToastKind.vehicleReminderSaved.symbolAnimation, .wiggle)
        XCTAssertNotEqual(ToastKind.saved.systemImage, ToastKind.tripSaved.systemImage)
    }
}
