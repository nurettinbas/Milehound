import XCTest
@testable import Milehound

final class EmptyLibraryShowcaseTests: XCTestCase {
    // MARK: - Layout

    func testNoRoomSizesToContentInTheRegularStack() {
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: nil, accessibilitySize: false), .regular)
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: .zero, accessibilitySize: false), .regular)
    }

    func testPhonePortraitStacksWithHighlights() {
        let layout = GlassShowcaseLayout.resolve(available: CGSize(width: 358, height: 600), accessibilitySize: false)
        XCTAssertEqual(layout, .regular)
        XCTAssertTrue(layout.showsHighlights)
        XCTAssertFalse(layout.isHorizontal)
    }

    func testMediumHeightCondenses() {
        XCTAssertEqual(
            GlassShowcaseLayout.resolve(available: CGSize(width: 340, height: 360), accessibilitySize: false),
            .condensed
        )
    }

    func testShortWidePaneGoesSideBySide() {
        let layout = GlassShowcaseLayout.resolve(available: CGSize(width: 520, height: 220), accessibilitySize: false)
        XCTAssertEqual(layout, .wide)
        XCTAssertTrue(layout.isHorizontal)
        XCTAssertTrue(layout.showsHighlights)
    }

    func testShortNarrowPaneDropsHighlights() {
        let layout = GlassShowcaseLayout.resolve(available: CGSize(width: 330, height: 190), accessibilitySize: false)
        XCTAssertEqual(layout, .minimal)
        XCTAssertFalse(layout.showsHighlights)
    }

    func testThresholdsAreInclusive() {
        let regular = GlassShowcaseLayout.regularMinHeight
        let condensed = GlassShowcaseLayout.condensedMinHeight
        let wide = GlassShowcaseLayout.wideMinWidth
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: CGSize(width: 300, height: regular), accessibilitySize: false), .regular)
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: CGSize(width: 300, height: condensed), accessibilitySize: false), .condensed)
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: CGSize(width: wide, height: condensed - 1), accessibilitySize: false), .wide)
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: CGSize(width: wide - 1, height: condensed - 1), accessibilitySize: false), .minimal)
    }

    func testAccessibilityTextAlwaysStacks() {
        XCTAssertEqual(
            GlassShowcaseLayout.resolve(available: CGSize(width: 520, height: 200), accessibilitySize: true),
            .regular
        )
    }

    func testEmblemFitsTheShortLayouts() {
        let short = CGSize(width: 520, height: 160)
        let wideSide = GlassShowcaseLayout.wide.emblemSide(available: short)
        XCTAssertLessThanOrEqual(wideSide * GlassShowcaseEmblemView.frameScale, short.height)
        let tiny = CGSize(width: 300, height: 110)
        let minimalSide = GlassShowcaseLayout.minimal.emblemSide(available: tiny)
        XCTAssertGreaterThanOrEqual(minimalSide, 40)
        XCTAssertLessThanOrEqual(minimalSide, 52)
    }

    // MARK: - Trips

    func testFirstRunWhenTheLibraryIsEmptyAndIdle() {
        XCTAssertEqual(kind(), .firstRun)
    }

    func testFirstRunIgnoresFiltersWithNoTrips() {
        XCTAssertEqual(kind(hasActiveFilters: true), .firstRun)
    }

    func testRecordingTheFirstTrip() {
        XCTAssertEqual(kind(isRecording: true), .recordingFirstTrip)
    }

    func testRecordingTransitionHidesTheShowcase() {
        XCTAssertNil(kind(isRecording: true, isRecordingTransition: true))
        XCTAssertNil(kind(isRecordingTransition: true))
    }

    func testFilteredWhenTripsExist() {
        XCTAssertEqual(kind(hasAnyTrips: true, hasActiveFilters: true), .filtered)
    }

    func testNothingWhenTripsExistWithoutFilters() {
        XCTAssertNil(kind(hasAnyTrips: true))
        XCTAssertNil(kind(hasAnyTrips: true, isRecording: true))
    }

    func testSearchActivityHidesEveryEmptyState() {
        XCTAssertNil(kind(isSearchBusy: true))
        XCTAssertNil(kind(hasAnyTrips: true, hasActiveFilters: true, isSearchBusy: true))
    }

    func testListFractionShrinksWithSectionsAbove() {
        XCTAssertEqual(EmptyLibraryPolicy.listHeightFraction(sectionsAbove: 0), 0.86, accuracy: 0.0001)
        XCTAssertLessThan(
            EmptyLibraryPolicy.listHeightFraction(sectionsAbove: 2),
            EmptyLibraryPolicy.listHeightFraction(sectionsAbove: 1)
        )
        XCTAssertEqual(EmptyLibraryPolicy.listHeightFraction(sectionsAbove: 20), 0.42, accuracy: 0.0001)
        XCTAssertEqual(EmptyLibraryPolicy.listHeightFraction(sectionsAbove: -3), 0.86, accuracy: 0.0001)
    }

    func testListShowcaseSizeNeedsAMeasuredViewport() {
        XCTAssertNil(EmptyLibraryPolicy.listShowcaseSize(viewport: .zero, sectionsAbove: 0))
        let size = EmptyLibraryPolicy.listShowcaseSize(viewport: CGSize(width: 390, height: 700), sectionsAbove: 0)
        XCTAssertEqual(size?.width ?? 0, 390 - 2 * GlassTokens.panelHorizontalInset, accuracy: 0.001)
        XCTAssertEqual(size?.height ?? 0, 700 * 0.86, accuracy: 0.001)
    }

    func testPhoneBookListPaneIsShortAndWide() {
        let size = EmptyLibraryPolicy.listShowcaseSize(viewport: CGSize(width: 520, height: 260), sectionsAbove: 0)
        XCTAssertEqual(GlassShowcaseLayout.resolve(available: size, accessibilitySize: false), .wide)
    }

    // MARK: - Stats and Recap

    func testInsightsShowcaseNeedsBothCountsToBeZero() {
        XCTAssertTrue(EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: false, hasExpense: false))
        XCTAssertFalse(EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: true, hasExpense: false))
        XCTAssertFalse(EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: false, hasExpense: true))
    }

    func testInsightsShowcaseWaitsForTheCounts() {
        XCTAssertFalse(EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: nil, hasExpense: false))
        XCTAssertFalse(EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: false, hasExpense: nil))
        XCTAssertFalse(EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: nil, hasExpense: nil))
    }

    private func kind(
        hasAnyTrips: Bool = false,
        hasActiveFilters: Bool = false,
        isSearchBusy: Bool = false,
        isRecording: Bool = false,
        isRecordingTransition: Bool = false
    ) -> EmptyLibraryPolicy.TripsKind? {
        EmptyLibraryPolicy.tripsKind(
            hasAnyTrips: hasAnyTrips,
            hasActiveFilters: hasActiveFilters,
            isSearchBusy: isSearchBusy,
            isRecording: isRecording,
            isRecordingTransition: isRecordingTransition
        )
    }
}
