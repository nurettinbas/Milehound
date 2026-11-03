import XCTest
@testable import Milehound

final class GlassCollapsingLayoutTests: XCTestCase {
    func testStuckOffsetIsZeroWhenCardIsBelowThePin() {
        XCTAssertEqual(GlassCollapsingLayout.stuckOffset(minY: 80, pinY: 0), 0)
        XCTAssertEqual(GlassCollapsingLayout.stuckOffset(minY: 0, pinY: 0), 0)
    }

    func testStuckOffsetTracksHowFarTheCardHasCrossedThePin() {
        XCTAssertEqual(GlassCollapsingLayout.stuckOffset(minY: -40, pinY: 0), 40)
        XCTAssertEqual(GlassCollapsingLayout.stuckOffset(minY: -12, pinY: 8), 20)
    }

    func testFullBleedPosterStillInsetsTheSectionTitle() {
        XCTAssertEqual(
            GlassCollapsingLayout.titleChromeInset(contentInset: 0, applyCard: true),
            StatsCardTokens.contentInset
        )
        XCTAssertEqual(
            GlassCollapsingLayout.titleChromeInset(contentInset: StatsCardTokens.contentInset, applyCard: true),
            StatsCardTokens.contentInset
        )
        XCTAssertEqual(
            GlassCollapsingLayout.titleChromeInset(contentInset: 20, applyCard: true),
            20
        )
        XCTAssertEqual(
            GlassCollapsingLayout.titleChromeInset(contentInset: 0, applyCard: false),
            0
        )
    }

    func testVisibleHeightShrinksFromTheTop() {
        XCTAssertEqual(GlassCollapsingLayout.visibleHeight(fullHeight: 200, stuckOffset: 0), 200)
        XCTAssertEqual(GlassCollapsingLayout.visibleHeight(fullHeight: 200, stuckOffset: 60), 140)
        XCTAssertEqual(GlassCollapsingLayout.visibleHeight(fullHeight: 200, stuckOffset: 260), 0)
    }

    func testStripFadesOutInPlaceAndFadesBack() {
        let collapsing = GlassCollapsingLayout.placement(
            natural: 200,
            stuck: 60,
            minHeight: 48,
            titleBand: 32
        )
        XCTAssertFalse(collapsing.isExiting)
        XCTAssertEqual(collapsing.plateHeight, 140)
        XCTAssertEqual(collapsing.opacity, 1)
        XCTAssertEqual(collapsing.pinCompensation, 0)

        let leaving = GlassCollapsingLayout.placement(
            natural: 200,
            stuck: 176,
            minHeight: 48,
            titleBand: 32
        )
        XCTAssertTrue(leaving.isExiting)
        XCTAssertEqual(leaving.plateHeight, 48)
        XCTAssertEqual(leaving.titleOffset, 176)
        XCTAssertEqual(leaving.contentShown, 0)
        XCTAssertEqual(leaving.pinCompensation, 24)
        XCTAssertEqual(leaving.opacity, 0.5, accuracy: 0.001)

        let gone = GlassCollapsingLayout.placement(
            natural: 200,
            stuck: 200,
            minHeight: 48,
            titleBand: 32
        )
        XCTAssertEqual(gone.plateHeight, 48)
        XCTAssertEqual(gone.opacity, 0)

        let returning = GlassCollapsingLayout.placement(
            natural: 200,
            stuck: 140,
            minHeight: 48,
            titleBand: 32
        )
        XCTAssertEqual(returning.opacity, 1)
        XCTAssertFalse(returning.isExiting)
    }
}
