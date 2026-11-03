import CoreLocation
import XCTest
@testable import Milehound

@MainActor
final class TripMapFitTests: XCTestCase {
    func testPanelInsetZoomsOutMoreThanFullscreen() {
        // North–south route so latitude is the limiting axis once the panel shrinks the visible band.
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.002)
        ]

        let fullscreen = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .fullscreen
        )
        let withPanel = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailWithPanel
        )

        XCTAssertNotNil(fullscreen)
        XCTAssertNotNil(withPanel)
        XCTAssertGreaterThan(withPanel!.span.latitudeDelta, fullscreen!.span.latitudeDelta)
    }

    func testOverlayPanelFitShiftsRouteIntoUpperVisibleBand() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        ]
        let midLat = 41.005
        let fit = TripDetailViewModel.MapFitContext.detailOverlay(
            panelFraction: 0.52,
            aspectWidthOverHeight: 0.46
        )
        let region = TripDetailViewModel.regionFitting(coordinates: coordinates, fit: fit)

        XCTAssertNotNil(region)
        // Center moves south so the route sits above the overlay panel (north = top of map).
        XCTAssertLessThan(region!.center.latitude, midLat)
        XCTAssertGreaterThan(fit.bottom, 0.52)
    }

    func testTallPanelStillKeepsUsableVisibleBand() {
        let fit = TripDetailViewModel.MapFitContext.detailOverlay(
            panelFraction: 0.78,
            aspectWidthOverHeight: 0.46
        )
        let visible = 1 - fit.top - fit.bottom
        XCTAssertGreaterThanOrEqual(visible, 0.16)

        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.01)
        ]
        let region = TripDetailViewModel.regionFitting(coordinates: coordinates, fit: fit)
        XCTAssertNotNil(region)

        let balanced = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailOverlay(panelFraction: 0.52, aspectWidthOverHeight: 0.46)
        )
        XCTAssertNotNil(balanced)
        // Taller panel must zoom out more so the route still fits the thin strip.
        XCTAssertGreaterThan(region!.span.latitudeDelta, balanced!.span.latitudeDelta)
    }

    func testOverlayBottomIncludesLegendClearance() {
        let fit = TripDetailViewModel.MapFitContext.detailOverlay(
            panelFraction: 0.52,
            aspectWidthOverHeight: 0.46,
            topChromeFraction: 0.10
        )
        XCTAssertGreaterThanOrEqual(fit.bottom, 0.52 + 0.08)
    }

    func testAspectMatchedSpansAreNotSquareOnPortrait() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        ]
        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailOverlay(panelFraction: 0.52, aspectWidthOverHeight: 0.46)
        )
        XCTAssertNotNil(region)
        XCTAssertNotEqual(region!.span.latitudeDelta, region!.span.longitudeDelta, accuracy: 0.0001)
        XCTAssertLessThan(region!.span.longitudeDelta, region!.span.latitudeDelta)
    }

    func testShortRouteGetsReadableMinimumZoom() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.0004, longitude: 29.0004)
        ]

        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailWithPanel
        )

        XCTAssertNotNil(region)
        XCTAssertGreaterThanOrEqual(region!.span.latitudeDelta, 0.0016)
    }

    func testLongAndShortRoutesUseSimilarRelativeMargin() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.08, longitude: 29.12)
        ]

        let short = TripDetailViewModel.regionFitting(
            coordinates: [
                CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
                CLLocationCoordinate2D(latitude: 41.002, longitude: 29.002)
            ],
            fit: .detailWithPanel
        )
        let long = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailWithPanel
        )

        XCTAssertNotNil(short)
        XCTAssertNotNil(long)
        let shortMarginRatio = short!.span.latitudeDelta / 0.002
        let longMarginRatio = long!.span.latitudeDelta / 0.08
        // Pixel fit uses a fixed 1.2 margin; Mercator + aspect can differ by a few thousandths.
        XCTAssertEqual(longMarginRatio, shortMarginRatio, accuracy: 0.05)
        XCTAssertGreaterThan(long!.span.latitudeDelta, short!.span.latitudeDelta)
    }

    func testPixelPaddingCentersRouteInUsableBand() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.01)
        ]
        let mapSize = CGSize(width: 390, height: 844)
        let panelHeight: CGFloat = 844 * 0.52
        let padding = UIEdgeInsets(top: 96, left: 24, bottom: panelHeight + 56, right: 24)
        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            mapSize: mapSize,
            edgePadding: padding
        )

        XCTAssertNotNil(region)
        let midLat = 41.01
        // Route sits in the upper visible band → camera center shifts south.
        XCTAssertLessThan(region!.center.latitude, midLat)

        let tallPadding = UIEdgeInsets(top: 96, left: 24, bottom: 844 * 0.78 + 56, right: 24)
        let tall = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            mapSize: mapSize,
            edgePadding: tallPadding
        )
        XCTAssertNotNil(tall)
        XCTAssertGreaterThan(tall!.span.latitudeDelta, region!.span.latitudeDelta)
    }

    func testExpandedPaddingCentersRouteAboveTabBar() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 38.36, longitude: 27.14),
            CLLocationCoordinate2D(latitude: 38.42, longitude: 27.16)
        ]
        let mapSize = CGSize(width: 390, height: 844)
        let top: CGFloat = 96 + 52
        let bottom: CGFloat = 83 + 36
        let padding = UIEdgeInsets(top: top, left: 24, bottom: bottom, right: 24)
        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            mapSize: mapSize,
            edgePadding: padding
        )

        XCTAssertNotNil(region)
        let midLat = 38.39
        let midLon = 27.15
        // More top chrome than bottom → visible band sits slightly below map midpoint.
        // Camera center is therefore slightly north of the route mid (north = top of map).
        XCTAssertGreaterThan(region!.center.latitude, midLat)
        XCTAssertEqual(region!.center.longitude, midLon, accuracy: 0.004)
        // Must stay wider than the raw route so start/end are not clipped by the tab bar.
        XCTAssertGreaterThan(region!.span.latitudeDelta, 0.06)
    }
}

// MARK: - Posture framing

extension TripMapFitTests {
    private var bayAreaRoute: [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: 37.3230, longitude: -122.0322),
            CLLocationCoordinate2D(latitude: 37.3847, longitude: -122.1917)
        ]
    }

    private var bayAreaMidpoint: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (37.3230 + 37.3847) / 2,
            longitude: (-122.0322 + -122.1917) / 2
        )
    }

    private func assertRouteCentered(
        _ input: TripDetailMapFraming.Input,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let region = TripDetailViewModel.regionFitting(
            coordinates: bayAreaRoute,
            mapSize: input.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(input)
        )
        XCTAssertNotNil(region, file: file, line: line)
        guard let region else { return }
        let fraction = TripDetailMapProjection.fraction(bayAreaMidpoint, in: region)
        let visible = TripDetailMapFraming.visibleCenter(
            mapSize: input.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(input)
        )
        XCTAssertEqual(fraction.x, visible.x / input.mapSize.width, accuracy: 0.04, file: file, line: line)
        XCTAssertEqual(fraction.y, visible.y / input.mapSize.height, accuracy: 0.04, file: file, line: line)
    }

    private func framing(
        _ posture: TripDetailMapFraming.Posture,
        size: CGSize,
        cardFraction: CGFloat = 0,
        trailingCover: CGFloat = 0,
        leadingInset: CGFloat = 0
    ) -> TripDetailMapFraming.Input {
        TripDetailMapFraming.Input(
            posture: posture,
            mapSize: size,
            topChrome: 96,
            bottomCardHeight: size.height * cardFraction,
            trailingCover: trailingCover,
            leadingInset: leadingInset,
            homeIndicator: 34
        )
    }

    func testEveryPostureCentersTheRouteInTheVisibleMap() {
        let cases: [TripDetailMapFraming.Input] = [
            framing(.sheet, size: CGSize(width: 390, height: 844), cardFraction: 0.52),
            framing(
                .sheet,
                size: CGSize(width: 744, height: 1133),
                cardFraction: 0.52,
                trailingCover: 84,
                leadingInset: 16
            ),
            framing(.phoneLandscape, size: CGSize(width: 844, height: 390), cardFraction: 0.52, trailingCover: 84),
            framing(.duoSplit, size: CGSize(width: 540, height: 744), trailingCover: 76),
            framing(.padTrailing, size: CGSize(width: 1194, height: 834)),
            framing(.stacked, size: CGSize(width: 834, height: 460)),
            framing(.expanded, size: CGSize(width: 390, height: 844), cardFraction: 0.52, trailingCover: 80, leadingInset: 16)
        ]
        for input in cases {
            assertRouteCentered(input)
        }
    }

    func testSideTabShiftsTheCenterAwayFromTheTrailingEdge() {
        let clear = framing(.phoneLandscape, size: CGSize(width: 844, height: 390), cardFraction: 0.52)
        let covered = framing(
            .phoneLandscape,
            size: CGSize(width: 844, height: 390),
            cardFraction: 0.52,
            trailingCover: 84
        )
        let clearCenter = TripDetailMapFraming.visibleCenter(
            mapSize: clear.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(clear)
        )
        let coveredCenter = TripDetailMapFraming.visibleCenter(
            mapSize: covered.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(covered)
        )
        XCTAssertLessThan(coveredCenter.x, clearCenter.x)
        assertRouteCentered(covered)
    }

    func testPortraitFramingDoesNotUseTheTrailingPanelInset() {
        let portrait = framing(.sheet, size: CGSize(width: 390, height: 844), cardFraction: 0.52)
        let pad = framing(.padTrailing, size: CGSize(width: 1194, height: 834))
        let portraitInsets = TripDetailMapFraming.edgeInsets(portrait)
        let padInsets = TripDetailMapFraming.edgeInsets(pad)
        XCTAssertEqual(portraitInsets.left, portraitInsets.right, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(padInsets.right - padInsets.left, GlassTokens.floatingPanelWidth)
        XCTAssertLessThan(portraitInsets.right - portraitInsets.left, 50)
    }

    func testSplitOmitsTheBottomCardAndLegend() {
        let split = framing(.duoSplit, size: CGSize(width: 540, height: 744), trailingCover: 76)
        let insets = TripDetailMapFraming.edgeInsets(split)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.5)
        XCTAssertLessThan(insets.bottom, TripDetailMapFraming.legendAndPins)
    }

    func testLargerVisibleMapZoomsIn() {
        let phone = framing(.sheet, size: CGSize(width: 390, height: 844), cardFraction: 0.52)
        let split = framing(.duoSplit, size: CGSize(width: 700, height: 744))
        let phoneRegion = TripDetailViewModel.regionFitting(
            coordinates: bayAreaRoute,
            mapSize: phone.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(phone)
        )
        let splitRegion = TripDetailViewModel.regionFitting(
            coordinates: bayAreaRoute,
            mapSize: split.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(split)
        )
        XCTAssertNotNil(phoneRegion)
        XCTAssertNotNil(splitRegion)
        let phoneArea = phoneRegion!.span.latitudeDelta * phoneRegion!.span.longitudeDelta
        let splitArea = splitRegion!.span.latitudeDelta * splitRegion!.span.longitudeDelta
        XCTAssertLessThan(splitArea, phoneArea)
    }

    func testTinyCameraChangeIsNotWritten() {
        let input = framing(.sheet, size: CGSize(width: 390, height: 844), cardFraction: 0.52)
        let current = TripDetailViewModel.regionFitting(
            coordinates: bayAreaRoute,
            mapSize: input.mapSize,
            edgePadding: TripDetailMapFraming.edgeInsets(input)
        )!
        XCTAssertFalse(
            TripDetailCameraMotion.shouldWrite(current: current, proposed: current, mapSize: input.mapSize)
        )

        var nudged = current
        nudged.center.latitude += current.span.latitudeDelta * (1.5 / input.mapSize.height)
        XCTAssertFalse(
            TripDetailCameraMotion.shouldWrite(current: current, proposed: nudged, mapSize: input.mapSize)
        )

        var moved = current
        moved.center.latitude += current.span.latitudeDelta * (8 / input.mapSize.height)
        XCTAssertTrue(
            TripDetailCameraMotion.shouldWrite(current: current, proposed: moved, mapSize: input.mapSize)
        )

        var zoomed = current
        zoomed.span.latitudeDelta *= 1.03
        XCTAssertTrue(
            TripDetailCameraMotion.shouldWrite(current: current, proposed: zoomed, mapSize: input.mapSize)
        )
    }
}

// MARK: - Settle sequences

extension TripMapFitTests {
    private func settleFrame(
        _ posture: TripDetailMapFraming.Posture,
        size: CGSize
    ) -> TripDetailMapFraming.Input {
        framing(
            posture,
            size: size,
            cardFraction: posture == .sheet || posture == .phoneLandscape ? 0.52 : 0,
            trailingCover: posture == .phoneLandscape || posture == .duoSplit ? 80 : 0
        )
    }

    func testLandscapeToPortraitFitsTheFinalFrameOnce() {
        var state = TripDetailCameraSettle.State()
        let landscape = settleFrame(.phoneLandscape, size: CGSize(width: 844, height: 390))
        let portrait = settleFrame(.sheet, size: CGSize(width: 390, height: 844))

        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: landscape, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: true), .none)
        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: portrait, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        expectSingleFit(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false), posture: .sheet, size: portrait.mapSize)
        XCTAssertEqual(state.fits.count, 1)
        XCTAssertEqual(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false), .none)
    }

    func testPortraitToLandscapeFitsTheFinalFrameOnce() {
        var state = TripDetailCameraSettle.State()
        let portrait = settleFrame(.sheet, size: CGSize(width: 390, height: 844))
        let landscape = settleFrame(.phoneLandscape, size: CGSize(width: 844, height: 390))

        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: portrait, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: landscape, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        expectSingleFit(
            TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false),
            posture: .phoneLandscape,
            size: landscape.mapSize
        )
        XCTAssertEqual(state.fits.count, 1)
    }

    func testFoldFromDuoToPhoneFitsTheSheetOnce() {
        var state = TripDetailCameraSettle.State()
        let split = settleFrame(.duoSplit, size: CGSize(width: 540, height: 744))
        let phone = settleFrame(.sheet, size: CGSize(width: 390, height: 844))

        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: split, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: phone, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        expectSingleFit(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false), posture: .sheet, size: phone.mapSize)
        XCTAssertEqual(state.fits.count, 1)
    }

    func testUnfoldFromPhoneToDuoFitsTheSplitOnce() {
        var state = TripDetailCameraSettle.State()
        let phone = settleFrame(.sheet, size: CGSize(width: 390, height: 844))
        let split = settleFrame(.duoSplit, size: CGSize(width: 540, height: 744))

        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: phone, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: split, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        expectSingleFit(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false), posture: .duoSplit, size: split.mapSize)
        XCTAssertEqual(state.fits.count, 1)
    }

    func testTwoQuickTurnsFitOnlyTheLastPosture() {
        var state = TripDetailCameraSettle.State()
        let landscape = settleFrame(.phoneLandscape, size: CGSize(width: 844, height: 390))
        let portrait = settleFrame(.sheet, size: CGSize(width: 390, height: 844))

        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: landscape, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: portrait, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        expectSingleFit(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false), posture: .sheet, size: portrait.mapSize)
        XCTAssertEqual(state.fits.count, 1)
    }

    func testTurnLongerThanTheOldWaitStillFitsOnce() {
        var state = TripDetailCameraSettle.State()
        let portrait = settleFrame(.sheet, size: CGSize(width: 390, height: 844))

        XCTAssertEqual(
            TripDetailCameraSettle.reduce(&state, layout: portrait, rotating: true, looksLikeTurn: true),
            .none
        )
        XCTAssertEqual(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: true), .none)
        XCTAssertTrue(state.fits.isEmpty)
        XCTAssertTrue(state.owed)
        XCTAssertEqual(TripDetailCameraSettle.reduceTurnFlag(&state, rotating: false), .waitForQuiet)
        expectSingleFit(TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: false), posture: .sheet, size: portrait.mapSize)
        XCTAssertEqual(state.fits.count, 1)
    }

    private func expectSingleFit(
        _ action: TripDetailCameraSettle.Action,
        posture: TripDetailMapFraming.Posture,
        size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .fit(let frame) = action else {
            XCTFail("expected one fit, got \(action)", file: file, line: line)
            return
        }
        XCTAssertEqual(frame.posture, posture, file: file, line: line)
        XCTAssertEqual(frame.mapSize, size, file: file, line: line)
    }
}
