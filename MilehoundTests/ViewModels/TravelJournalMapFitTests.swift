import XCTest
@testable import Milehound

final class TravelJournalMapFitTests: XCTestCase {
    private let mapSize = CGSize(width: 500, height: 360)

    func testSplitIgnoresBottomSheet() {
        let split = TravelJournalMapFit.padding(
            style: .split,
            mapExpanded: false,
            mapSize: mapSize,
            topChrome: 44,
            bottomChrome: 200,
            sheetHeight: 400,
            trailingCover: 59,
            homeIndicator: 21
        )
        let sheet = TravelJournalMapFit.padding(
            style: .overlay,
            mapExpanded: false,
            mapSize: mapSize,
            topChrome: 44,
            bottomChrome: 200,
            sheetHeight: 400,
            trailingCover: 59,
            homeIndicator: 21
        )

        XCTAssertEqual(split.bottom, 21, accuracy: 0.5)
        XCTAssertGreaterThan(sheet.bottom, 400)
        XCTAssertEqual(split.right, split.left + 59, accuracy: 0.5)
    }

    func testExpandedSplitDoesNotKeepTheSheetInset() {
        let expanded = TravelJournalMapFit.padding(
            style: .split,
            mapExpanded: true,
            mapSize: mapSize,
            topChrome: 44,
            bottomChrome: 90,
            sheetHeight: 400,
            trailingCover: 59,
            homeIndicator: 21
        )
        XCTAssertLessThan(expanded.bottom, 200)
        XCTAssertEqual(expanded.left, expanded.right, accuracy: 0.5)
    }

    func testClosedCoverLandscapeIsOnlyTheShortSidewaysCover() {
        let cover = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 640, height: 400),
            idiom: .phone
        )
        let phoneBook = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .compact,
            size: CGSize(width: 844, height: 390),
            idiom: .phone
        )
        let portrait = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 390, height: 844),
            idiom: .phone
        )
        XCTAssertTrue(cover.isClosedCoverLandscape)
        XCTAssertFalse(phoneBook.isClosedCoverLandscape)
        XCTAssertFalse(portrait.isClosedCoverLandscape)
        XCTAssertEqual(cover.coverCardWidthForTests, GlassTokens.TravelCornerCardMetrics.compactWidth(screenWidth: 640))
    }

    func testCoverCardPushesTheRouteBesideAndAboveIt() {
        let trailing = TravelJournalMapFit.padding(
            style: .floatingPanel,
            mapExpanded: false,
            mapSize: mapSize,
            topChrome: 54,
            bottomChrome: 34,
            sheetHeight: 400,
            trailingCover: 0,
            homeIndicator: 21,
            coverCardWidth: 200,
            coverCardHeight: 140,
            coverCardIsTrailing: true
        )
        let leading = TravelJournalMapFit.padding(
            style: .floatingPanel,
            mapExpanded: false,
            mapSize: mapSize,
            topChrome: 54,
            bottomChrome: 34,
            sheetHeight: 400,
            trailingCover: 0,
            homeIndicator: 21,
            coverCardWidth: 200,
            coverCardHeight: 140,
            coverCardIsTrailing: false
        )
        XCTAssertGreaterThan(trailing.right, trailing.left)
        XCTAssertGreaterThan(leading.left, leading.right)
        XCTAssertEqual(trailing.bottom, leading.bottom, accuracy: 0.5)
        XCTAssertGreaterThan(trailing.bottom, 140)
    }

    func testIPadCornerCardIsNarrowerThanThePageAndShorterWhenOpen() {
        let page = CGSize(width: 1180, height: 820)
        let compact: CGFloat = 160
        let bottom: CGFloat = 20
        let openSpan = page.height - 80
        let landscape = TravelJournalPadCardMetrics.expandedHeight(
            pageHeight: page.height,
            openSpan: openSpan,
            compact: compact,
            landscape: true,
            bottomInset: bottom
        )
        let portrait = TravelJournalPadCardMetrics.expandedHeight(
            pageHeight: page.width,
            openSpan: page.width - 80,
            compact: compact,
            landscape: false,
            bottomInset: bottom
        )
        XCTAssertEqual(
            TravelJournalPadCardMetrics.width(screenWidth: page.width),
            page.width * 0.44,
            accuracy: 0.5
        )
        XCTAssertEqual(landscape, page.height / 2 - bottom, accuracy: 0.5)
        XCTAssertEqual(portrait, (page.width - 80) * 0.48, accuracy: 0.5)
        XCTAssertLessThan(landscape, page.height / 2)
        XCTAssertGreaterThan(landscape, compact)
    }
}

private extension MilehoundLayoutSnapshot {
    var coverCardWidthForTests: CGFloat {
        guard isClosedCoverLandscape else { return 0 }
        return GlassTokens.TravelCornerCardMetrics.compactWidth(screenWidth: size.width)
    }
}
