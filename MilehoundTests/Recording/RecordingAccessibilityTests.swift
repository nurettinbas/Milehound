import XCTest
@testable import Milehound

/// `RecordingAccessibility` exists as a pure helper so the recording card's body never reads
/// the ~4 Hz display sampler. These tests pin that shape down: if the formatting ever moves
/// back into a view body, it stops being testable here.
final class RecordingAccessibilityTests: XCTestCase {
    func testSummaryIncludesStatusDurationSpeedAndDistance() {
        let summary = RecordingAccessibility.summary(
            status: "Recording",
            elapsed: 3661,
            speedMps: 25,
            distanceMeters: 12_000
        )

        XCTAssertTrue(summary.contains("Recording"))
        XCTAssertTrue(summary.contains(DateFormatters.formatDuration(3661)))
        XCTAssertTrue(summary.contains(DateFormatters.formatDistance(12_000)))
        XCTAssertTrue(summary.contains("90"))
    }

    func testSpeedTextConvertsToKmh() {
        XCTAssertEqual(RecordingAccessibility.speedText(speedMps: 10), "36 \(L10n.speedKmh)")
    }

    func testSpeedTextClampsNegativeGpsSpeed() {
        XCTAssertEqual(RecordingAccessibility.speedText(speedMps: -1), "0 \(L10n.speedKmh)")
    }

    func testSummaryHandlesZeroedState() {
        let summary = RecordingAccessibility.summary(
            status: "Paused",
            elapsed: 0,
            speedMps: 0,
            distanceMeters: 0
        )

        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("Paused"))
    }
}

@MainActor
final class RecordingLiveMapHintTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RecordingLiveMapHint.resetForTests()
    }

    func testHintPlaysOncePerTrip() {
        let tripID = UUID()
        XCTAssertTrue(RecordingLiveMapHint.shouldPlay(for: tripID))
        RecordingLiveMapHint.markPlayed(for: tripID)
        XCTAssertFalse(RecordingLiveMapHint.shouldPlay(for: tripID))
        XCTAssertTrue(RecordingLiveMapHint.shouldPlay(for: UUID()))
    }

    func testNilTripAlwaysEligibleUntilMarkedNoOp() {
        XCTAssertTrue(RecordingLiveMapHint.shouldPlay(for: nil))
        RecordingLiveMapHint.markPlayed(for: nil)
        XCTAssertTrue(RecordingLiveMapHint.shouldPlay(for: nil))
    }

    func testOpenHintIsLocalized() {
        let text = L10n.string("recording.live_map.open_hint")
        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "recording.live_map.open_hint")
    }
}
