import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class PersonalRecordEvaluatorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainerFactory.makeInMemory()
    }

    func testFirstCompletedTripIsBothRecords() throws {
        let trip = makeTrip(distanceMeters: 5_000, cruiseKmh: 80, cruiseSeconds: 120)
        insert(trip)
        try container.mainContext.save()

        let payload = try XCTUnwrap(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
        XCTAssertEqual(payload.longestDistanceMeters, 5_000)
        XCTAssertEqual(payload.fastestCruiseKmh, 80)
        XCTAssertTrue(payload.accessibilityMessage.contains(L10n.toastRecordKicker))
        XCTAssertTrue(
            payload.accessibilityMessage.contains("NEW RECORD")
                || payload.accessibilityMessage.contains("YENİ REKOR")
        )
    }

    func testLongerTripBeatsPreviousDistance() throws {
        insert(makeTrip(distanceMeters: 4_000, cruiseKmh: 70, cruiseSeconds: 90, hoursAgo: 4))
        try container.mainContext.save()

        let trip = makeTrip(distanceMeters: 9_000, cruiseKmh: 60, cruiseSeconds: 90)
        insert(trip)
        try container.mainContext.save()

        let payload = try XCTUnwrap(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
        XCTAssertEqual(payload.longestDistanceMeters, 9_000)
        XCTAssertNil(payload.fastestCruiseKmh)
    }

    func testFasterCruiseBeatsPreviousCruise() throws {
        insert(makeTrip(distanceMeters: 8_000, cruiseKmh: 70, cruiseSeconds: 120, hoursAgo: 3))
        try container.mainContext.save()

        let trip = makeTrip(distanceMeters: 3_000, cruiseKmh: 95, cruiseSeconds: 90)
        insert(trip)
        try container.mainContext.save()

        let payload = try XCTUnwrap(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
        XCTAssertNil(payload.longestDistanceMeters)
        XCTAssertEqual(payload.fastestCruiseKmh, 95)
    }

    func testShorterAndSlowerTripIsSilent() throws {
        insert(makeTrip(distanceMeters: 12_000, cruiseKmh: 110, cruiseSeconds: 180, hoursAgo: 5))
        try container.mainContext.save()

        let trip = makeTrip(distanceMeters: 4_000, cruiseKmh: 80, cruiseSeconds: 90)
        insert(trip)
        try container.mainContext.save()

        XCTAssertNil(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
    }

    func testCruiseBelowMinimumMovingTimeIsNotARecord() throws {
        let trip = makeTrip(distanceMeters: 2_000, cruiseKmh: 140, cruiseSeconds: 30)
        insert(trip)
        try container.mainContext.save()

        let payload = try XCTUnwrap(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
        XCTAssertEqual(payload.longestDistanceMeters, 2_000)
        XCTAssertNil(payload.fastestCruiseKmh)
    }

    func testBothRecordsInOnePayload() throws {
        insert(makeTrip(distanceMeters: 3_000, cruiseKmh: 50, cruiseSeconds: 90, hoursAgo: 2))
        try container.mainContext.save()

        let trip = makeTrip(distanceMeters: 20_000, cruiseKmh: 118, cruiseSeconds: 600)
        insert(trip)
        try container.mainContext.save()

        let payload = try XCTUnwrap(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
        XCTAssertEqual(payload.longestDistanceMeters, 20_000)
        XCTAssertEqual(payload.fastestCruiseKmh, 118)
        XCTAssertEqual(
            ToastKind.personalRecord(payload).message,
            payload.accessibilityMessage
        )
        XCTAssertEqual(ToastKind.personalRecord(payload).hapticStyle, .personalRecord)
        XCTAssertEqual(ToastKind.personalRecord(payload).systemImage, "trophy.fill")
        XCTAssertEqual(ToastKind.personalRecord(payload).emblemTone, .gold)
    }

    func testUnfinishedTripIsSilent() throws {
        let trip = makeTrip(distanceMeters: 8_000, cruiseKmh: 90, cruiseSeconds: 120)
        trip.endedAt = nil
        insert(trip)
        try container.mainContext.save()

        XCTAssertNil(PersonalRecordEvaluator.evaluate(trip: trip, in: container.mainContext))
    }

    func testPresentIfNeededSkipsToastInUnitTests() throws {
        let trip = makeTrip(distanceMeters: 7_000, cruiseKmh: 88, cruiseSeconds: 120)
        insert(trip)
        try container.mainContext.save()

        PersonalRecordToast.presentIfNeeded(
            for: trip,
            in: container.mainContext,
            timing: .immediate
        )
        XCTAssertFalse(ToastPresenter.shared.isPresented)
        XCTAssertNil(ToastPresenter.shared.kind)
    }

    private func insert(_ trip: Trip) {
        container.mainContext.insert(trip)
    }

    private func makeTrip(
        distanceMeters: Double,
        cruiseKmh: Double,
        cruiseSeconds: Double,
        hoursAgo: Int = 0
    ) -> Trip {
        let started = Date().addingTimeInterval(TimeInterval(-3600 * hoursAgo - 1_800))
        let trip = Trip(
            startedAt: started,
            endedAt: started.addingTimeInterval(1_800),
            distanceMeters: distanceMeters
        )
        trip.cruiseSpeedKmh = cruiseKmh
        trip.cruiseDurationSeconds = cruiseSeconds
        return trip
    }
}

final class WeekSummaryRefreshTests: XCTestCase {
    func testAnimationIDChangesWhenTokenChangesEvenIfTextIsSame() {
        let text = "12.4 km · 1:10"
        let first = WeekSummaryRefresh.animationID(text: text, token: 1)
        let second = WeekSummaryRefresh.animationID(text: text, token: 2)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains(text))
        XCTAssertTrue(second.contains(text))
    }

    func testShouldPlayMotionRequiresTripsModeAndText() {
        XCTAssertTrue(
            WeekSummaryRefresh.shouldPlayMotion(
                listMode: .trips,
                weekSummaryText: "1 km · 0:12",
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WeekSummaryRefresh.shouldPlayMotion(
                listMode: .travels,
                weekSummaryText: "1 km · 0:12",
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WeekSummaryRefresh.shouldPlayMotion(
                listMode: .trips,
                weekSummaryText: "",
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            WeekSummaryRefresh.shouldPlayMotion(
                listMode: .trips,
                weekSummaryText: "1 km · 0:12",
                reduceMotion: true
            )
        )
    }
}
