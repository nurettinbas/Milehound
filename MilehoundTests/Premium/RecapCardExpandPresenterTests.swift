import SwiftUI
import XCTest
@testable import Milehound

@MainActor
final class RecapCardExpandPresenterTests: XCTestCase {
    override func tearDown() {
        RecapCardExpandPresenter.shared.dismissImmediately()
        super.tearDown()
    }

    func testSecondPresentIsIgnored() {
        let presenter = RecapCardExpandPresenter.shared
        let model = RecapExpandModel()
        presenter.present(
            kind: .achievements,
            anchor: CGRect(x: 0, y: 80, width: 200, height: 40),
            startsShown: false,
            model: model,
            onWillDismiss: {},
            onDismissed: {}
        )
        let first = presenter.presentation?.id
        presenter.present(
            kind: .routes,
            anchor: .zero,
            startsShown: true,
            model: model,
            onWillDismiss: {},
            onDismissed: {}
        )
        XCTAssertEqual(presenter.presentation?.id, first)
        XCTAssertEqual(presenter.presentation?.kind, .achievements)
    }

    func testDismissImmediatelyClearsThePresentation() {
        let presenter = RecapCardExpandPresenter.shared
        var willDismiss = 0
        var dismissed = 0
        presenter.present(
            kind: .forecast,
            anchor: CGRect(x: 10, y: 10, width: 100, height: 40),
            startsShown: false,
            model: RecapExpandModel(),
            onWillDismiss: { willDismiss += 1 },
            onDismissed: { dismissed += 1 }
        )
        presenter.dismissImmediately()
        XCTAssertNil(presenter.presentation)
        XCTAssertFalse(presenter.isOpenSettled)
        XCTAssertEqual(willDismiss, 1)
        XCTAssertEqual(dismissed, 1)
        presenter.dismissImmediately()
        XCTAssertEqual(dismissed, 1)
    }

    func testUnitPointUsesTheCardCenter() {
        let overlay = CGRect(x: 0, y: 0, width: 200, height: 400)
        let card = CGRect(x: 10, y: 50, width: 100, height: 80)
        let point = RecapCardExpandGeometry.unitPoint(for: card, overlayGlobal: overlay)
        XCTAssertEqual(point.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.225, accuracy: 0.001)
    }

    func testUnitPointAccountsForAnOffsetOverlay() {
        let overlay = CGRect(x: 0, y: 20, width: 200, height: 400)
        let card = CGRect(x: 0, y: 20, width: 200, height: 80)
        let point = RecapCardExpandGeometry.unitPoint(for: card, overlayGlobal: overlay)
        XCTAssertEqual(point.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.1, accuracy: 0.001)
    }

    func testUnitPointFallsBackToCenter() {
        let overlay = CGRect(x: 0, y: 0, width: 200, height: 400)
        XCTAssertEqual(RecapCardExpandGeometry.unitPoint(for: .zero, overlayGlobal: overlay), .center)
        XCTAssertEqual(
            RecapCardExpandGeometry.unitPoint(for: CGRect(x: 0, y: 0, width: 4, height: 4), overlayGlobal: overlay),
            .center
        )
        XCTAssertEqual(
            RecapCardExpandGeometry.unitPoint(
                for: CGRect(x: 0, y: 0, width: 40, height: 40),
                overlayGlobal: .zero
            ),
            .center
        )
    }

    func testUnitPointClampsACardPastTheEdge() {
        let overlay = CGRect(x: 0, y: 0, width: 100, height: 100)
        let card = CGRect(x: 180, y: -40, width: 40, height: 20)
        let point = RecapCardExpandGeometry.unitPoint(for: card, overlayGlobal: overlay)
        XCTAssertEqual(point.x, 1, accuracy: 0.001)
        XCTAssertEqual(point.y, 0, accuracy: 0.001)
    }

    func testCloseAnchorStaysFrozenWhenTheLiveCardIsOffScreen() {
        let frozen = CGRect(x: 16, y: 200, width: 300, height: 90)
        let live = CGRect(x: 16, y: 900, width: 300, height: 90)
        XCTAssertEqual(
            RecapCardExpandGeometry.anchorForClose(frozen: frozen, live: live, liveIsOnScreen: false),
            frozen
        )
        XCTAssertEqual(
            RecapCardExpandGeometry.anchorForClose(frozen: frozen, live: live, liveIsOnScreen: true),
            live
        )
        XCTAssertEqual(
            RecapCardExpandGeometry.anchorForClose(frozen: frozen, live: .zero, liveIsOnScreen: true),
            frozen
        )
    }

    func testScaleAndBlurMatchTheGlassPanel() {
        XCTAssertEqual(
            RecapCardExpandGeometry.scale(isShown: false, isClosing: false, reduceMotion: false),
            GlassTokens.morphPanelOpenScale
        )
        XCTAssertEqual(
            RecapCardExpandGeometry.scale(isShown: false, isClosing: true, reduceMotion: false),
            GlassTokens.morphPanelCloseScale
        )
        XCTAssertEqual(RecapCardExpandGeometry.scale(isShown: true, isClosing: false, reduceMotion: false), 1)
        XCTAssertEqual(RecapCardExpandGeometry.scale(isShown: false, isClosing: false, reduceMotion: true), 1)
        XCTAssertEqual(
            RecapCardExpandGeometry.blur(isShown: false, reduceMotion: false),
            GlassTokens.morphPanelBlur
        )
        XCTAssertEqual(RecapCardExpandGeometry.blur(isShown: true, reduceMotion: false), 0)
        XCTAssertEqual(RecapCardExpandGeometry.blur(isShown: false, reduceMotion: true), 0)
        XCTAssertNotNil(MilehoundMotion.recapCardExpandOpen(reduceMotion: false))
        XCTAssertNotNil(MilehoundMotion.recapCardExpandClose(reduceMotion: true))
    }
}
