import SwiftUI
import UIKit
import XCTest
@testable import Milehound

final class SideColumnChromeTests: XCTestCase {
    private let buttonSide = GlassTokens.toolbarControlCircleSide
    private let gap = GlassTokens.sideColumnChromeGap

    func testTopRightCapsuleSitsUnderTheStatusCluster() {
        let bar = CGRect(x: 820, y: 220, width: 64, height: 360)
        let status: CGFloat = 54
        let placement = SideColumnChromeResolver.resolve(
            metrics(tabBar: bar, safe: UIEdgeInsets(top: 54, left: 0, bottom: 21, right: 0), buttons: 2, status: status)
        )
        guard case .sideColumn(let frame, let below) = placement else {
            return XCTFail("Expected the capsule under the status cluster")
        }
        XCTAssertFalse(below)
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, status + gap, accuracy: 0.5)
        XCTAssertEqual(frame.width, buttonSide, accuracy: 0.5)
        XCTAssertEqual(frame.height, buttonSide * 2, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(bar.minY - frame.maxY, gap - 0.5)
        let camera = SideColumnChromeResolver.cameraRegion(
            windowSize: CGSize(width: 900, height: 700),
            safeInsets: UIEdgeInsets(top: 54, left: 0, bottom: 21, right: 0),
            column: bar
        )
        XCTAssertFalse(frame.intersects(camera))
        XCTAssertFalse(frame.intersects(bar))
    }

    func testOneButtonUsesTheSameTopEdge() {
        let bar = CGRect(x: 820, y: 220, width: 64, height: 360)
        let status: CGFloat = 54
        let placement = SideColumnChromeResolver.resolve(
            metrics(tabBar: bar, safe: .zero, buttons: 1, status: status)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the single bell under the status cluster")
        }
        XCTAssertEqual(frame.minY, status + gap, accuracy: 0.5)
        XCTAssertEqual(frame.height, buttonSide, accuracy: 0.5)
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
    }

    func testUnmeasuredStatusStaysInTheToolbar() {
        let bar = CGRect(x: 820, y: 220, width: 64, height: 360)
        let placement = SideColumnChromeResolver.resolve(metrics(tabBar: bar, safe: .zero, buttons: 2, status: nil))
        XCTAssertEqual(placement, .toolbar)
    }

    func testOverlapWithTheTabBarStaysInTheToolbar() {
        let bar = CGRect(x: 820, y: 100, width: 64, height: 400)
        let placement = SideColumnChromeResolver.resolve(
            metrics(tabBar: bar, safe: .zero, buttons: 2, status: 40)
        )
        XCTAssertEqual(placement, .toolbar)
    }

    func testSideInsetIsTheTabColumnNotACamera() {
        let window = CGSize(width: 678, height: 466)
        let bar = CGRect(x: 606, y: 122, width: 46, height: 260)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, status: 0)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the pair above the side icons")
        }
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, bar.minY - gap - buttonSide * 2, accuracy: 0.5)
        XCTAssertEqual(frame.height, buttonSide * 2, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(bar.minY - frame.maxY, gap - 0.5)
        let camera = SideColumnChromeResolver.cameraRegion(windowSize: window, safeInsets: safe, column: bar)
        XCTAssertTrue(camera.isEmpty)
        XCTAssertFalse(frame.intersects(bar))
    }

    func testCoverColumnClearsThePunchHole() {
        let window = CGSize(width: 678, height: 466)
        // The cover drops the left icon pill to 180 so it clears the punch hole.
        // The hole itself ends at 65pt and is not in the safe area.
        let bar = CGRect(x: 26, y: 180, width: 46, height: 260)
        let safe = UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 0)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, status: 0)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the pair below the punch hole")
        }
        let punchHoleBottom: CGFloat = 65
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, bar.minY - gap - buttonSide * 2, accuracy: 0.5)
        XCTAssertGreaterThan(frame.minY, punchHoleBottom)
        XCTAssertGreaterThanOrEqual(bar.minY - frame.maxY, gap - 0.5)
        XCTAssertFalse(frame.intersects(bar))
    }

    func testTopSensorCoversACapsuleThatStartsInsideIt() {
        let window = CGSize(width: 900, height: 700)
        let bar = CGRect(x: window.width - 76, y: 220, width: 64, height: 360)
        let safe = UIEdgeInsets(top: 80, left: 0, bottom: 21, right: 0)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, status: 10)
        )
        XCTAssertEqual(placement, .toolbar)
        let camera = SideColumnChromeResolver.cameraRegion(windowSize: window, safeInsets: safe, column: bar)
        XCTAssertFalse(camera.isEmpty)
    }

    func testTallCoverClearsTheStackedClock() {
        let window = CGSize(width: 466, height: 678)
        let bar = CGRect(x: 394, y: 392, width: 46, height: 260)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        let status = SideColumnChromeResolver.collapsedStatusBottom(columnInset: safe.right, portrait: true)
        XCTAssertEqual(status, safe.right + 54 + 12)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, status: status)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the pair under the stacked clock")
        }
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, status + gap, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(bar.minY - frame.maxY, gap - 0.5)
    }

    func testOpenBookStacksUnderTheColumnInset() {
        let window = CGSize(width: 951, height: 669)
        let bar = CGRect(x: 879, y: 383, width: 46, height: 260)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        let status = SideColumnChromeResolver.collapsedStatusBottom(columnInset: safe.right, portrait: false)
        XCTAssertEqual(status, safe.right + 12)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 3, status: status)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected bell, plus, and merge under the clock")
        }
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, status + gap, accuracy: 0.5)
        XCTAssertEqual(frame.height, buttonSide * 3, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(bar.minY - frame.maxY, gap - 0.5)
    }

    func testLeftColumnWithNoStatusBarUsesThatColumn() {
        let window = CGSize(width: 678, height: 466)
        let bar = CGRect(x: 26, y: 122, width: 46, height: 260)
        let safe = UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 0)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, status: 0)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the pair above the left icons")
        }
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, bar.minY - gap - buttonSide * 2, accuracy: 0.5)
    }

    func testCameraOnTheOtherEdgeLeavesTheCapsuleUnderTheStatusCluster() {
        let window = CGSize(width: 900, height: 700)
        let bar = CGRect(x: 12, y: 220, width: 64, height: 360)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 59)
        let status: CGFloat = 48
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 1, status: status)
        )
        guard case .sideColumn(let frame, let below) = placement else {
            return XCTFail("Expected the capsule under the status cluster")
        }
        XCTAssertFalse(below)
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, status + gap, accuracy: 0.5)
        let camera = SideColumnChromeResolver.cameraRegion(windowSize: window, safeInsets: safe, column: bar)
        XCTAssertTrue(camera.isEmpty)
        XCTAssertFalse(frame.intersects(camera))
    }

    func testOffScreenAxisStaysInTheToolbar() {
        let window = CGSize(width: 900, height: 700)
        let bar = CGRect(x: window.width - 10, y: 220, width: 64, height: 360)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: .zero, buttons: 2, status: 54)
        )
        XCTAssertEqual(placement, .toolbar)
    }

    func testWidePortraitBottomTabStaysInTheToolbar() {
        let window = CGSize(width: 669, height: 951)
        let bar = CGRect(x: 24, y: 860, width: 621, height: 62)
        let placement = SideColumnChromeResolver.resolve(
            metrics(
                window: window,
                tabBar: bar,
                safe: UIEdgeInsets(top: 54, left: 0, bottom: 21, right: 0),
                buttons: 2,
                status: 54
            )
        )
        XCTAssertEqual(placement, .toolbar)
    }

    func testSideTabOnTheLeftUsesThatColumn() {
        let window = CGSize(width: 951, height: 669)
        let bar = CGRect(x: 12, y: 240, width: 64, height: 380)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: .zero, buttons: 2, status: 54)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the capsule on the leading side tab")
        }
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, 54 + gap, accuracy: 0.5)
    }

    func testNarrowPhoneBottomTabStaysInTheToolbar() {
        let window = CGSize(width: 390, height: 844)
        let bar = CGRect(x: 16, y: 760, width: 358, height: 56)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), buttons: 2, status: 59)
        )
        XCTAssertEqual(placement, .toolbar)
    }

    func testBottomTabBarStaysInTheToolbar() {
        let bar = CGRect(x: 80, y: 760, width: 230, height: 56)
        let placement = SideColumnChromeResolver.resolve(
            metrics(tabBar: bar, safe: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), buttons: 2, status: 59)
        )
        XCTAssertEqual(placement, .toolbar)
    }

    func testMissingPlatterStaysPending() {
        let placement = SideColumnChromeResolver.resolve(metrics(tabBar: nil, safe: .zero, buttons: 1, status: 54))
        XCTAssertEqual(placement, .pending)
    }

    func testFullHeightColumnStaysInTheToolbar() {
        let window = CGSize(width: 900, height: 420)
        let bar = CGRect(x: 0, y: 0, width: 64, height: window.height)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, status: 54)
        )
        XCTAssertEqual(placement, .toolbar)
    }

    func testRotationStaysPendingUntilTheNextPlatter() {
        var metrics = metrics(tabBar: CGRect(x: 820, y: 220, width: 64, height: 360), safe: .zero, buttons: 2, status: 54)
        metrics.isTransitioning = true
        XCTAssertEqual(SideColumnChromeResolver.resolve(metrics), .pending)
    }

    func testStatusClusterUsesTheLowerMeasuredEdge() {
        XCTAssertNil(SideColumnChromeResolver.measuredStatusClusterMaxY(statusBarMaxY: nil, safeTop: 59))
        XCTAssertNil(SideColumnChromeResolver.measuredStatusClusterMaxY(statusBarMaxY: 0, safeTop: 59))
        XCTAssertEqual(
            SideColumnChromeResolver.measuredStatusClusterMaxY(statusBarMaxY: 54, safeTop: 59),
            59
        )
        XCTAssertEqual(
            SideColumnChromeResolver.measuredStatusClusterMaxY(statusBarMaxY: 80, safeTop: 20),
            80
        )
    }

    @MainActor
    func testStatePublishesPendingOnlyWhileTransitioning() {
        let state = SideColumnChromeState()
        state.update(
            windowSize: CGSize(width: 900, height: 700),
            safeInsets: .zero,
            tabBarFrame: CGRect(x: 820, y: 220, width: 64, height: 360),
            layoutDirection: .leftToRight,
            statusClusterMaxY: 54
        )
        XCTAssertTrue(state.showsToolbarChrome == false)
        state.beginTransition()
        XCTAssertEqual(state.placement(buttonCount: 2), .pending)
        XCTAssertTrue(state.showsToolbarChrome)
        state.endTransition()
        guard case .sideColumn = state.placement(buttonCount: 2) else {
            return XCTFail("Expected the side column after the transition")
        }
    }

    @MainActor
    func testUprightDuoRequiresThePairToFit() {
        let state = SideColumnChromeState()
        let duo = MilehoundLayoutSnapshot(
            layoutClass: .duoOpen,
            size: CGSize(width: 900, height: 700),
            isLandscape: false
        )
        state.update(
            windowSize: duo.size,
            safeInsets: .zero,
            tabBarFrame: CGRect(x: 820, y: 220, width: 64, height: 360),
            layoutDirection: .leftToRight,
            statusClusterMaxY: 54
        )
        let bell = state.uprightDuoCapsuleFrame(buttonCount: 1, layout: duo)
        let pair = state.uprightDuoCapsuleFrame(buttonCount: 2, layout: duo)
        XCTAssertNotNil(bell)
        XCTAssertNotNil(pair)
        XCTAssertEqual(bell?.minY, pair?.minY)
        let phone = MilehoundLayoutSnapshot.phone
        XCTAssertEqual(state.uprightDuoCapsuleFrame(buttonCount: 2, layout: phone)?.midX, 852)
        let uprightFold = MilehoundLayoutSnapshot(
            layoutClass: .phone,
            size: CGSize(width: 669, height: 951),
            isLandscape: false
        )
        state.update(
            windowSize: uprightFold.size,
            safeInsets: UIEdgeInsets(top: 54, left: 0, bottom: 21, right: 0),
            tabBarFrame: CGRect(x: 24, y: 860, width: 621, height: 62),
            layoutDirection: .leftToRight,
            statusClusterMaxY: 54
        )
        XCTAssertNil(state.uprightDuoCapsuleFrame(buttonCount: 2, layout: uprightFold))
        var landscape = duo
        landscape.isLandscape = true
        XCTAssertNil(state.uprightDuoCapsuleFrame(buttonCount: 3, layout: landscape))
        let book = CGSize(width: 951, height: 669)
        let sideTab = CGRect(x: 870, y: 240, width: 64, height: 380)
        state.update(
            windowSize: book,
            safeInsets: .zero,
            tabBarFrame: sideTab,
            layoutDirection: .leftToRight,
            statusClusterMaxY: 54
        )
        landscape.size = book
        let stack = state.uprightDuoCapsuleFrame(buttonCount: 3, layout: landscape)
        XCTAssertEqual(stack?.minY, 70)
        XCTAssertEqual(stack?.height, 132)
        XCTAssertEqual(stack?.midX, sideTab.midX)
        let phoneLandscape = MilehoundLayoutSnapshot(
            layoutClass: .phoneLandscape,
            size: book,
            isLandscape: true
        )
        let sidePair = state.uprightDuoCapsuleFrame(buttonCount: 2, layout: phoneLandscape)
        XCTAssertEqual(sidePair?.midX, sideTab.midX)
        XCTAssertEqual(sidePair?.minY, 70)
        let pad = MilehoundLayoutSnapshot(
            layoutClass: .pad,
            size: book,
            isLandscape: true
        )
        XCTAssertNil(state.uprightDuoCapsuleFrame(buttonCount: 2, layout: pad))
    }

    private func metrics(
        window: CGSize = CGSize(width: 900, height: 700),
        tabBar: CGRect?,
        safe: UIEdgeInsets,
        buttons: Int,
        direction: LayoutDirection = .leftToRight,
        status: CGFloat? = nil
    ) -> SideColumnChromeMetrics {
        SideColumnChromeMetrics(
            windowSize: window,
            safeInsets: safe,
            tabBarFrame: tabBar,
            layoutDirection: direction,
            buttonCount: buttons,
            isTransitioning: false,
            statusClusterMaxY: status
        )
    }
}
