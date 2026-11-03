import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

final class MilehoundLayoutTests: XCTestCase {
    func testPhonePortraitStaysPhone() {
        let resolved = MilehoundLayoutResolver.resolve(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 390, height: 844),
            idiom: .phone,
            debugOverride: nil
        )
        XCTAssertEqual(resolved, .phone)
    }

    func testLiveMapHidesTheTabBarOnThePhoneBookAndEveryFullSizeiPad() {
        let book = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 874, height: 402),
            idiom: .phone
        )
        let padLandscape = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1180, height: 820),
            idiom: .pad
        )
        let padPortrait = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 820, height: 1180),
            idiom: .pad
        )
        let phone = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 390, height: 844),
            idiom: .phone
        )
        let duo = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1180, height: 820),
            idiom: .phone
        )

        XCTAssertTrue(book.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: true, ending: false))
        XCTAssertTrue(padLandscape.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: true, ending: false))
        XCTAssertTrue(padPortrait.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: true, ending: false))
        XCTAssertFalse(phone.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: true, ending: false))
        XCTAssertFalse(duo.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: true, ending: false))
        XCTAssertFalse(padLandscape.hidesTabBarWhileLiveMap(showingLiveMap: false, recording: true, ending: false))
        XCTAssertFalse(padLandscape.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: false, ending: false))
        XCTAssertFalse(padLandscape.hidesTabBarWhileLiveMap(showingLiveMap: true, recording: true, ending: true))
        XCTAssertTrue(book.hidesNavigationBarForLiveMap)
        XCTAssertTrue(padLandscape.hidesNavigationBarForLiveMap)
        XCTAssertTrue(padPortrait.hidesNavigationBarForLiveMap)
        XCTAssertFalse(phone.hidesNavigationBarForLiveMap)
    }

    func testPhoneLandscape() {
        let resolved = MilehoundLayoutResolver.resolve(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 844, height: 390),
            idiom: .phone,
            debugOverride: nil
        )
        XCTAssertEqual(resolved, .phoneLandscape)
    }

    func testOpenFoldPortraitPinsTheRecordingCardToAHorizontalHinge() {
        let compactWide = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 402, height: 1600),
            idiom: .phone
        )
        XCTAssertEqual(compactWide.layoutClass, .duoOpen)
        XCTAssertFalse(compactWide.isLandscape)
        XCTAssertTrue(compactWide.pinsRecordingCardToFold)
        XCTAssertFalse(compactWide.splitsTrips)
        XCTAssertFalse(compactWide.splitsIdleLibrary)
        XCTAssertTrue(compactWide.hidesRecordingCardFromList)

        let regularPortrait = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 680, height: 1100),
            idiom: .phone
        )
        XCTAssertEqual(regularPortrait.layoutClass, .duoOpen)
        XCTAssertTrue(regularPortrait.pinsRecordingCardToFold)
        XCTAssertEqual(regularPortrait.duoSheetLeadingInset(matchingTrailingSafeArea: 80), GlassTokens.panelHorizontalInset)
        XCTAssertEqual(regularPortrait.duoSheetLeadingInset(matchingTrailingSafeArea: 0), 0)
        XCTAssertEqual(compactWide.duoSheetLeadingInset(matchingTrailingSafeArea: 80), GlassTokens.panelHorizontalInset)
    }

    func testClosedLandscapeKeepsTheRecordingCardInTheList() {
        let book = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .compact,
            size: CGSize(width: 1600, height: 402),
            idiom: .phone
        )
        XCTAssertEqual(book.layoutClass, .phoneLandscape)
        XCTAssertTrue(book.splitsTrips)
        XCTAssertTrue(book.isWideBook)
        XCTAssertTrue(book.splitsIdleLibrary)
        XCTAssertFalse(book.splitsRecording)
        XCTAssertFalse(book.recordingCardLeads)
        XCTAssertFalse(book.pinsRecordingCardToFold)
        XCTAssertEqual(book.recordingCardArrangement, .list)
        XCTAssertFalse(book.hidesRecordingCardFromList)
        XCTAssertFalse(book.isPhoneBook)
        XCTAssertFalse(book.usesBookPanes)
        XCTAssertFalse(book.showsPairingVehicleFocus)
        XCTAssertEqual(book.settingsChrome, .split)
    }

    func testWidePhoneLandscapeUsesTheOpenBook() {
        let phone = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 874, height: 402),
            idiom: .phone
        )
        XCTAssertEqual(phone.layoutClass, .phoneLandscape)
        XCTAssertTrue(phone.isPhoneBook)
        XCTAssertTrue(phone.usesBookPanes)
        XCTAssertFalse(phone.isOpenBookLandscape)
        XCTAssertTrue(phone.splitsIdleLibrary)
        XCTAssertTrue(phone.splitsRecording)
        XCTAssertTrue(phone.recordingCardLeads)
        XCTAssertEqual(phone.recordingCardArrangement, .pane)
        XCTAssertTrue(phone.hidesRecordingCardFromList)
        XCTAssertEqual(phone.tripDetailStyle, .split)
        XCTAssertEqual(phone.mapChrome, .splitPane)
        XCTAssertEqual(phone.settingsChrome, .split)
        XCTAssertTrue(phone.showsPairingVehicleFocus)
        XCTAssertEqual(phone.badgeColumnCount, 4)
        XCTAssertFalse(
            MilehoundLayoutResolver.usesOffHingeVehicleSplit(
                layoutClass: phone.layoutClass,
                isLandscape: phone.isLandscape,
                hingeFullyOpen: true
            )
        )

        let plus = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 956, height: 440),
            idiom: .phone
        )
        XCTAssertTrue(plus.isPhoneBook)
        XCTAssertTrue(plus.usesBookPanes)
    }

    func testNarrowPhoneLandscapeStaysOneColumn() {
        let cover = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 678, height: 466),
            idiom: .phone
        )
        XCTAssertEqual(cover.layoutClass, .phoneLandscape)
        XCTAssertFalse(cover.isPhoneBook)
        XCTAssertFalse(cover.usesBookPanes)
        XCTAssertFalse(cover.splitsIdleLibrary)
        XCTAssertFalse(cover.splitsRecording)
        XCTAssertFalse(cover.recordingCardLeads)
        XCTAssertEqual(cover.recordingCardArrangement, .list)
        XCTAssertEqual(cover.tripDetailStyle, .floatingPanel)
        XCTAssertEqual(cover.settingsChrome, .form)
        XCTAssertFalse(cover.showsPairingVehicleFocus)

        let se = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 667, height: 375),
            idiom: .phone
        )
        XCTAssertFalse(se.isPhoneBook)
        XCTAssertFalse(se.splitsIdleLibrary)
        XCTAssertFalse(se.splitsRecording)
        XCTAssertEqual(se.tripDetailStyle, .floatingPanel)
        XCTAssertEqual(se.settingsChrome, .form)
        XCTAssertFalse(se.showsPairingVehicleFocus)
    }

    func testPhoneBookSeamIgnoresTheIslandInset() {
        let gutter: CGFloat = 24
        let content: CGFloat = 800
        let leading = MilehoundLayoutResolver.fractionLeadingPaneWidth(
            contentWidth: content,
            gutter: gutter,
            leadingFraction: 0.5
        )
        let usable = content - gutter
        XCTAssertEqual(leading, usable / 2, accuracy: 0.5)

        let bounds = CGRect(x: 0, y: 0, width: content, height: 390)
        let inset = CGRect(x: 59, y: 0, width: content, height: 390)
        let window = CGSize(width: content + 59, height: 390)
        let even = LibraryAxisPlacement.frames(
            in: bounds,
            gutter: gutter,
            frameSplit: 1,
            listOnVisualLeft: true,
            contentInWindow: inset,
            windowSize: window,
            evenSplit: true
        )
        XCTAssertEqual(even.trips.width, usable / 2, accuracy: 0.5)
        XCTAssertEqual(even.travels.width, usable / 2, accuracy: 0.5)

        let hinged = LibraryAxisPlacement.frames(
            in: bounds,
            gutter: gutter,
            frameSplit: 1,
            listOnVisualLeft: true,
            contentInWindow: inset,
            windowSize: window,
            evenSplit: false
        )
        XCTAssertNotEqual(hinged.trips.width, even.trips.width, accuracy: 1)
    }

    func testPhoneBookUsesTheFlatBookColumnShares() {
        XCTAssertEqual(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: true,
                layoutClass: .phoneLandscape,
                isLandscape: true,
                hingeFullyOpen: false,
                fraction: MilehoundLayoutResolver.flatStatsLeadingFraction
            ),
            0.45
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: true,
                layoutClass: .phoneLandscape,
                isLandscape: true,
                hingeFullyOpen: false,
                fraction: MilehoundLayoutResolver.flatVehicleListFraction
            ),
            0.6
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: true,
                layoutClass: .phoneLandscape,
                isLandscape: true,
                hingeFullyOpen: false,
                fraction: MilehoundLayoutResolver.flatVehicleProfileFraction
            ),
            0.4
        )
        XCTAssertNil(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: false,
                layoutClass: .duoOpen,
                isLandscape: true,
                hingeFullyOpen: false,
                fraction: MilehoundLayoutResolver.flatStatsLeadingFraction
            )
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: false,
                layoutClass: .duoOpen,
                isLandscape: true,
                hingeFullyOpen: true,
                fraction: MilehoundLayoutResolver.flatVehicleListFraction
            ),
            0.6
        )
    }

    func testOpenBookLandscapePutsTheRecordingCardOnTheLeadingHalf() {
        let openBook = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1600, height: 1100),
            idiom: .phone
        )
        XCTAssertEqual(openBook.layoutClass, .duoOpen)
        XCTAssertTrue(openBook.isLandscape)
        XCTAssertTrue(openBook.splitsTrips)
        XCTAssertTrue(openBook.isWideBook)
        XCTAssertTrue(openBook.splitsIdleLibrary)
        XCTAssertTrue(openBook.splitsRecording)
        XCTAssertTrue(openBook.recordingCardLeads)
        XCTAssertFalse(openBook.pinsRecordingCardToFold)
        XCTAssertEqual(openBook.recordingCardArrangement, .pane)
        XCTAssertTrue(openBook.hidesRecordingCardFromList)
        XCTAssertTrue(openBook.showsPairingVehicleFocus)
        XCTAssertTrue(openBook.isOpenBookLandscape)
        XCTAssertFalse(openBook.isPhoneBook)
        XCTAssertTrue(openBook.usesBookPanes)
        XCTAssertEqual(openBook.settingsChrome, .split)
    }

    func testRecordingOpensTripsInAPaneOnlyWhereThePaneExists() {
        let openBook = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1600, height: 1100),
            idiom: .phone
        )
        XCTAssertTrue(openBook.opensTripInPane(whileRecording: false))
        XCTAssertTrue(openBook.opensTripInPane(whileRecording: true))

        let padLand = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1366, height: 1024),
            idiom: .pad
        )
        XCTAssertTrue(padLand.opensTripInPane(whileRecording: true))

        let padPortrait = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1024, height: 1366),
            idiom: .pad
        )
        XCTAssertTrue(padPortrait.opensTripInPane(whileRecording: true))

        let closedLandscape = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 667, height: 375),
            idiom: .phone
        )
        XCTAssertEqual(closedLandscape.layoutClass, .phoneLandscape)
        XCTAssertTrue(closedLandscape.opensTripInPane(whileRecording: true))

        let upright = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 680, height: 1100),
            idiom: .phone
        )
        XCTAssertTrue(upright.pinsRecordingCardToFold)
        XCTAssertTrue(upright.opensTripInPane(whileRecording: false))
        XCTAssertFalse(upright.opensTripInPane(whileRecording: true), "No trip pane under the pinned card: push")

        let phone = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 390, height: 844),
            idiom: .phone
        )
        XCTAssertFalse(phone.opensTripInPane(whileRecording: false))
        XCTAssertFalse(phone.opensTripInPane(whileRecording: true))
    }

    func testUprightOpenFoldKeepsSettingsInOneColumn() {
        let upright = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 680, height: 1100),
            idiom: .phone
        )
        XCTAssertEqual(upright.layoutClass, .duoOpen)
        XCTAssertFalse(upright.isLandscape)
        XCTAssertEqual(upright.settingsChrome, .form)
        XCTAssertTrue(upright.packsPortraitRecapHalves)
    }

    func testPortraitPadPacksRecapHubsInHalvesFromMiniThroughPro() {
        let mini = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 744, height: 1133),
            idiom: .pad
        )
        let pro = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1024, height: 1366),
            idiom: .pad
        )
        XCTAssertEqual(mini.layoutClass, .pad)
        XCTAssertEqual(pro.layoutClass, .pad)
        XCTAssertTrue(mini.packsPortraitRecapHalves)
        XCTAssertTrue(pro.packsPortraitRecapHalves)
        XCTAssertFalse(MilehoundLayoutSnapshot.phone.packsPortraitRecapHalves)
    }

    func testSlightlyOpenFoldKeepsTheVehicleSeamOnTheHinge() {
        let slight = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 951, height: 669),
            idiom: .phone
        )
        XCTAssertEqual(slight.layoutClass, .duoOpen)
        XCTAssertTrue(slight.isLandscape)
        XCTAssertFalse(slight.isPhoneBook)
        XCTAssertTrue(slight.usesBookPanes)
        XCTAssertTrue(slight.showsPairingVehicleFocus)
        XCTAssertFalse(
            MilehoundLayoutResolver.usesOffHingeVehicleSplit(
                layoutClass: slight.layoutClass,
                isLandscape: slight.isLandscape,
                hingeFullyOpen: false
            )
        )
        XCTAssertTrue(
            MilehoundLayoutResolver.usesOffHingeVehicleSplit(
                layoutClass: slight.layoutClass,
                isLandscape: slight.isLandscape,
                hingeFullyOpen: true
            )
        )

        let padLand = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1366, height: 1024),
            idiom: .pad
        )
        XCTAssertFalse(
            MilehoundLayoutResolver.usesOffHingeVehicleSplit(
                layoutClass: padLand.layoutClass,
                isLandscape: padLand.isLandscape,
                hingeFullyOpen: true
            )
        )
    }

    func testFlatBookVehicleListTakesSixtyPercentOfTheContent() {
        let gutter: CGFloat = 24
        let content: CGFloat = 900
        let leading = MilehoundLayoutResolver.fractionLeadingPaneWidth(
            contentWidth: content,
            gutter: gutter,
            leadingFraction: MilehoundLayoutResolver.flatVehicleListFraction
        )
        let usable = content - gutter
        XCTAssertEqual(leading, usable * 0.6, accuracy: 0.5)
        XCTAssertEqual(usable - leading, usable * 0.4, accuracy: 0.5)

        let profile = MilehoundLayoutResolver.fractionLeadingPaneWidth(
            contentWidth: content,
            gutter: gutter,
            leadingFraction: MilehoundLayoutResolver.flatVehicleProfileFraction
        )
        XCTAssertEqual(profile, usable * 0.4, accuracy: 0.5)
        XCTAssertEqual(usable - profile, usable * 0.6, accuracy: 0.5)

        let stats = MilehoundLayoutResolver.fractionLeadingPaneWidth(
            contentWidth: content,
            gutter: gutter,
            leadingFraction: MilehoundLayoutResolver.flatStatsLeadingFraction
        )
        XCTAssertEqual(stats, usable * 0.45, accuracy: 0.5)
        XCTAssertEqual(usable - stats, usable * 0.55, accuracy: 0.5)
    }

    func testOpenFoldLandscapeIsHalfMapHalfDetails() {
        let book = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 1600, height: 402),
            idiom: .phone
        )
        XCTAssertEqual(book.layoutClass, .duoOpen)
        XCTAssertTrue(book.isLandscape)
        XCTAssertFalse(book.isPhoneBook)
        XCTAssertTrue(book.usesBookPanes)
        XCTAssertEqual(book.tripDetailStyle, .split)
        XCTAssertEqual(book.duoSheetLeadingInset(matchingTrailingSafeArea: 80), 0)

        let upright = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 402, height: 1600),
            idiom: .phone
        )
        XCTAssertEqual(upright.tripDetailStyle, .overlay)
    }

    func testViewportJumpIsARotationNotASheet() {
        XCTAssertFalse(
            MilehoundLayoutResolver.viewportChangeCancelsRotation(
                from: .zero,
                to: CGSize(width: 390, height: 844)
            )
        )
        XCTAssertFalse(
            MilehoundLayoutResolver.viewportChangeCancelsRotation(
                from: CGSize(width: 390, height: 844),
                to: CGSize(width: 390, height: 780)
            )
        )
        XCTAssertTrue(
            MilehoundLayoutResolver.viewportChangeCancelsRotation(
                from: CGSize(width: 402, height: 1600),
                to: CGSize(width: 1600, height: 402)
            )
        )
        XCTAssertTrue(
            MilehoundLayoutResolver.aspectFlips(
                from: CGSize(width: 951, height: 669),
                to: CGSize(width: 669, height: 951)
            )
        )
        XCTAssertFalse(
            MilehoundLayoutResolver.aspectFlips(
                from: CGSize(width: 390, height: 844),
                to: CGSize(width: 390, height: 780)
            )
        )
        XCTAssertFalse(
            MilehoundLayoutResolver.aspectFlips(
                from: .zero,
                to: CGSize(width: 390, height: 844)
            )
        )
    }

    func testSlightlyOpenTurnKeepsTheLayoutThatStartedTheRotation() {
        let outer = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 466, height: 678),
            idiom: .phone
        )
        let inner = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 951, height: 669),
            idiom: .phone
        )
        XCTAssertEqual(outer.layoutClass, .phone)
        XCTAssertEqual(inner.layoutClass, .duoOpen)
        XCTAssertTrue(inner.isLandscape)
        let held = MilehoundLayoutResolver.snapshotDuringTurn(
            presented: outer,
            live: inner,
            isRotating: true
        )
        XCTAssertEqual(held, outer)
        let released = MilehoundLayoutResolver.snapshotDuringTurn(
            presented: outer,
            live: inner,
            isRotating: false
        )
        XCTAssertEqual(released, inner)
    }

    func testUprightDuoCentersOnboarding() {
        let duo = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 620, height: 900),
            idiom: .phone
        )
        XCTAssertTrue(duo.centersOnboardingColumn)
        let turned = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 900, height: 620),
            idiom: .phone
        )
        XCTAssertFalse(turned.centersOnboardingColumn)
        let squatFold = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 620, height: 900),
            idiom: .phone
        )
        XCTAssertEqual(squatFold.layoutClass, .phone)
        XCTAssertTrue(squatFold.centersOnboardingColumn)
        XCTAssertFalse(MilehoundLayoutSnapshot.phone.centersOnboardingColumn)
    }

    func testOpenInnerScreenIsDuo() {
        let resolved = MilehoundLayoutResolver.resolve(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 844, height: 700),
            idiom: .phone,
            debugOverride: nil
        )
        XCTAssertEqual(resolved, .duoOpen)
    }

    func testPadAndNarrowSplit() {
        let pad = MilehoundLayoutResolver.resolve(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1024, height: 1366),
            idiom: .pad,
            debugOverride: nil
        )
        XCTAssertEqual(pad, .pad)
        let split = MilehoundLayoutResolver.resolve(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 320, height: 800),
            idiom: .pad,
            debugOverride: nil
        )
        XCTAssertEqual(split, .phone)
        let padLand = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1366, height: 1024),
            idiom: .pad
        )
        XCTAssertTrue(padLand.showsPairingVehicleFocus)
        XCTAssertTrue(padLand.usesSplitInbox)
        XCTAssertEqual(padLand.settingsChrome, .split)
        let padPortrait = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1024, height: 1366),
            idiom: .pad
        )
        XCTAssertTrue(padPortrait.showsPairingVehicleFocus)
        XCTAssertTrue(padPortrait.usesSplitInbox)
        XCTAssertEqual(padPortrait.settingsChrome, .split)
        XCTAssertEqual(
            MilehoundLayoutResolver.settingsLeadingFraction(
                isPhoneBook: false,
                layoutClass: .pad,
                isLandscape: false,
                hingeFullyOpen: false
            ),
            0.3
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.settingsLeadingFraction(
                isPhoneBook: false,
                layoutClass: .pad,
                isLandscape: true,
                hingeFullyOpen: false
            ),
            0.3
        )
    }

    func testPadLandscapeUsesWidePanes() {
        let air = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1180, height: 820),
            idiom: .pad
        )
        let pro = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1376, height: 1032),
            idiom: .pad
        )
        XCTAssertTrue(air.isLandscape)
        XCTAssertTrue(air.isPadBook)
        XCTAssertTrue(air.usesWidePanes)
        XCTAssertFalse(air.usesBookPanes)
        XCTAssertFalse(air.packsPortraitRecapHalves)
        XCTAssertTrue(pro.isPadBook)
        XCTAssertTrue(pro.usesWidePanes)

        let portrait = MilehoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 820, height: 1180),
            idiom: .pad
        )
        XCTAssertFalse(portrait.isPadBook)
        XCTAssertFalse(portrait.usesWidePanes)
        XCTAssertTrue(portrait.packsPortraitRecapHalves)
        XCTAssertTrue(portrait.splitsIdleLibrary)
        XCTAssertTrue(portrait.splitsRecording)
        XCTAssertEqual(portrait.recordingCardArrangement, .pane)

        let split = MilehoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 320, height: 800),
            idiom: .pad
        )
        XCTAssertEqual(split.layoutClass, .phone)
        XCTAssertFalse(split.isPadBook)
        XCTAssertFalse(split.usesWidePanes)

        XCTAssertEqual(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: false,
                layoutClass: .pad,
                isLandscape: true,
                hingeFullyOpen: false,
                fraction: MilehoundLayoutResolver.flatVehicleProfileFraction,
                isPadBook: true
            ),
            0.4
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: false,
                layoutClass: .pad,
                isLandscape: true,
                hingeFullyOpen: false,
                fraction: MilehoundLayoutResolver.flatStatsLeadingFraction,
                isPadBook: true
            ),
            0.45
        )
        XCTAssertNil(
            MilehoundLayoutResolver.flatBookLeadingFraction(
                isPhoneBook: false,
                layoutClass: .pad,
                isLandscape: true,
                hingeFullyOpen: true,
                fraction: MilehoundLayoutResolver.flatStatsLeadingFraction,
                isPadBook: false
            )
        )
    }

    func testColumnCountDoesNotStretchHalfTiles() {
        let phone = MilehoundLayoutResolver.columnCount(layout: .phone, contentWidth: 358)
        XCTAssertEqual(phone, 2)
        let widePad = MilehoundLayoutResolver.columnCount(layout: .pad, contentWidth: 1600)
        XCTAssertGreaterThanOrEqual(widePad, 4)
        let half = MilehoundLayoutResolver.halfWidth(columns: widePad, contentWidth: 1600)
        XCTAssertLessThanOrEqual(half, GlassTokens.moduleMaxHalf + 0.5)
        XCTAssertGreaterThanOrEqual(half, GlassTokens.moduleMinHalf - 0.5)
    }

    func testDuoSplitLandsOnTheHingeWhenTheTabColumnInsetsTheTrailingEdge() {
        let window: CGFloat = 1000
        let tabColumn: CGFloat = 100
        let gutter: CGFloat = 24
        let leading = MilehoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: 0,
            contentWidth: window - tabColumn,
            windowWidth: window,
            gutter: gutter,
            listOnVisualLeft: true
        )
        XCTAssertEqual(leading, window / 2 - gutter / 2)
        let seam = leading + gutter / 2
        XCTAssertEqual(seam, window / 2)
    }

    func testDuoSplitLandsOnTheHingeWhenTheTabColumnInsetsTheLeadingEdge() {
        let window: CGFloat = 1000
        let tabColumn: CGFloat = 80
        let gutter: CGFloat = 24
        let leading = MilehoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: tabColumn,
            contentWidth: window - tabColumn,
            windowWidth: window,
            gutter: gutter,
            listOnVisualLeft: true
        )
        XCTAssertEqual(leading + tabColumn + gutter / 2, window / 2)
    }

    func testHingeGutterRejectsACardOnTheFold() {
        let container = CGSize(width: 844, height: 700)
        let hinge = MilehoundLayoutResolver.hingeFrame(in: container)
        let straddling = CGRect(x: hinge.midX - 20, y: 40, width: 80, height: 120)
        let clear = CGRect(x: 16, y: 40, width: 300, height: 120)
        XCTAssertTrue(MilehoundLayoutResolver.frameIntersectsHinge(straddling, container: container))
        XCTAssertFalse(MilehoundLayoutResolver.frameIntersectsHinge(clear, container: container))
    }

    func testListLeadsAndMirrors() {
        XCTAssertTrue(MilehoundLayoutResolver.listIsOnVisualLeft(direction: .leftToRight))
        XCTAssertFalse(MilehoundLayoutResolver.listIsOnVisualLeft(direction: .rightToLeft))
    }

    func testBadgeColumns() {
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .phone, isLandscape: false, accessibility: false),
            2
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .phoneLandscape, isLandscape: true, accessibility: false),
            4
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .duoOpen, isLandscape: true, accessibility: false),
            4
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .duoOpen, isLandscape: false, accessibility: false),
            3
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .pad, isLandscape: false, accessibility: false),
            4
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .pad, isLandscape: true, accessibility: false),
            6
        )
        XCTAssertEqual(
            MilehoundLayoutResolver.badgeColumnCount(layout: .pad, isLandscape: true, accessibility: true),
            1
        )
    }

    func testLayoutReflowMatchesBadgeSpring() {
        XCTAssertNotNil(MilehoundMotion.layoutReflow(reduceMotion: false))
        XCTAssertNotNil(MilehoundMotion.layoutReflow(reduceMotion: true))
    }

    func testRecordingAxisIsSideBySideWhenWideAndStackedWhenTall() {
        XCTAssertEqual(RecordingAxisPlacement.stackAmount(width: 1200, height: 700), 0, accuracy: 0.001)
        XCTAssertEqual(RecordingAxisPlacement.stackAmount(width: 700, height: 1200), 1, accuracy: 0.001)
        let mid = RecordingAxisPlacement.stackAmount(width: 900, height: 900)
        XCTAssertGreaterThan(mid, 0.4)
        XCTAssertLessThan(mid, 0.6)
    }

    func testRecordingAxisKeepsTheCardOnTheLeadingSideUntilTheFold() {
        let gutter: CGFloat = 24
        let wide = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let landscape = RecordingAxisPlacement.frames(
            in: wide,
            gutter: gutter,
            liveLeads: true,
            listOnVisualLeft: true,
            contentInWindow: wide,
            windowSize: wide.size
        )
        XCTAssertEqual(landscape.live.minX, 0, accuracy: 0.5)
        XCTAssertLessThan(landscape.live.maxX, landscape.list.minX)
        XCTAssertEqual(landscape.live.height, wide.height, accuracy: 0.5)

        let tall = CGRect(x: 0, y: 0, width: 700, height: 1200)
        let portrait = RecordingAxisPlacement.frames(
            in: tall,
            gutter: gutter,
            liveLeads: true,
            listOnVisualLeft: true,
            contentInWindow: tall,
            windowSize: tall.size
        )
        XCTAssertEqual(portrait.live.minY, 0, accuracy: 0.5)
        XCTAssertLessThan(portrait.live.maxY, portrait.list.minY)
        XCTAssertEqual(portrait.live.width, tall.width, accuracy: 0.5)

        let square = CGRect(x: 0, y: 0, width: 900, height: 900)
        let turning = RecordingAxisPlacement.frames(
            in: square,
            gutter: gutter,
            liveLeads: true,
            listOnVisualLeft: true,
            contentInWindow: square,
            windowSize: square.size
        )
        let side = (square.width - gutter) / 2
        XCTAssertGreaterThan(turning.live.width, side + 1)
        XCTAssertLessThan(turning.live.width, square.width - 1)
        XCTAssertLessThan(turning.live.height, square.height - 1)
        XCTAssertGreaterThan(turning.live.height, side + 1)
    }

    func testLibraryAxisStaysOneColumnOnAPhoneAndOnATallBook() {
        XCTAssertEqual(LibraryAxisPlacement.splitAmount(width: 390, height: 844), 0, accuracy: 0.001)
        XCTAssertEqual(LibraryAxisPlacement.splitAmount(width: 844, height: 390), 0, accuracy: 0.001)
        XCTAssertEqual(LibraryAxisPlacement.splitAmount(width: 900, height: 1600), 0, accuracy: 0.001)
        XCTAssertEqual(
            LibraryAxisPlacement.splitAmount(width: 1600, height: 900, requiresBookSpan: false),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LibraryAxisPlacement.splitAmount(width: 1366, height: 1024, requiresBookSpan: false),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LibraryAxisPlacement.splitAmount(width: 874, height: 402, requiresBookSpan: false),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(LibraryAxisPlacement.splitAmount(width: 874, height: 402), 0, accuracy: 0.001)
    }

    func testLibraryAxisFadesTheTrailingLibraryBeforeTheColumnWidens() {
        let width: CGFloat = 1400
        for step in 0...40 {
            let ratio = 0.7 + CGFloat(step) * 0.04
            let split = LibraryAxisPlacement.splitAmount(
                width: width,
                height: width / ratio,
                requiresBookSpan: false
            )
            let frame = LibraryAxisPlacement.frameSplit(split)
            let opacity = LibraryAxisPlacement.travelsOpacity(split)
            if opacity > 0.001 {
                XCTAssertEqual(frame, 1, accuracy: 0.001, "ratio \(ratio)")
            }
            if frame < 0.999 {
                XCTAssertEqual(opacity, 0, accuracy: 0.001, "ratio \(ratio)")
            }
        }
    }

    func testLibraryAxisGivesTheTripsListTheFullWidthOnceTheBookIsTall() {
        let gutter: CGFloat = 24
        let wide = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let split = LibraryAxisPlacement.frames(
            in: wide,
            gutter: gutter,
            frameSplit: 1,
            listOnVisualLeft: true,
            contentInWindow: wide,
            windowSize: wide.size
        )
        XCTAssertLessThan(split.trips.maxX, split.travels.minX)
        XCTAssertEqual(split.trips.height, wide.height, accuracy: 0.5)
        XCTAssertEqual(split.travels.height, wide.height, accuracy: 0.5)
        XCTAssertEqual(split.trips.width + gutter + split.travels.width, wide.width, accuracy: 0.5)

        let tall = CGRect(x: 0, y: 0, width: 900, height: 1600)
        let stacked = LibraryAxisPlacement.frames(
            in: tall,
            gutter: gutter,
            frameSplit: 0,
            listOnVisualLeft: true,
            contentInWindow: tall,
            windowSize: tall.size
        )
        XCTAssertEqual(stacked.trips, tall)
        XCTAssertEqual(LibraryAxisPlacement.travelsOpacity(0), 0, accuracy: 0.001)
        XCTAssertFalse(LibraryAxisPlacement.pinsTripsLibrary(0))
        XCTAssertTrue(LibraryAxisPlacement.pinsTripsLibrary(1))
    }

}

@MainActor
final class RecordingListCardWidthTests: XCTestCase {
    func testInnerDuoFoldInsetIsTheListMargin() {
        XCTAssertEqual(GlassTokens.recordingFoldExtraInset(contentWidth: 669), 20)
        XCTAssertEqual(GlassTokens.recordingFoldExtraInset(contentWidth: 402), GlassTokens.panelHorizontalInset)
    }

    func testInnerDuoFoldCardMeetsTheTripPlate() {
        let extra = GlassTokens.recordingFoldExtraInset(contentWidth: 669)
        let laid = measureFold(extraInset: extra, width: 669, sizeClass: .regular)
        XCTAssertEqual(laid.card.minX, laid.plate.minX, accuracy: 0.5, "card \(laid.card) plate \(laid.plate)")
        XCTAssertEqual(laid.card.maxX, laid.plate.maxX, accuracy: 0.5, "card \(laid.card) plate \(laid.plate)")
        let plain = measureFold(extraInset: 0, width: 669, sizeClass: .regular)
        XCTAssertEqual(laid.card.minX, plain.card.minX + extra, accuracy: 0.5)
        XCTAssertEqual(laid.card.maxX, plain.card.maxX - extra, accuracy: 0.5)
        recordSnapshot(of: laid.controller, named: "duo-portrait-fold", size: laid.canvas)
    }

    func testPhoneWidthFoldUsesOnePanelInset() {
        let extra = GlassTokens.recordingFoldExtraInset(contentWidth: 402)
        let laid = measureFold(extraInset: extra, width: 402, sizeClass: .compact)
        XCTAssertEqual(laid.card.minX, laid.plate.minX, accuracy: 0.5, "card \(laid.card) plate \(laid.plate)")
        XCTAssertEqual(laid.card.maxX, laid.plate.maxX, accuracy: 0.5, "card \(laid.card) plate \(laid.plate)")
    }

    private func recordSnapshot(of controller: UIViewController, named: String, size: CGSize) {
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller,
                as: .image(precision: 0.99, perceptualPrecision: 0.98, size: size),
                named: named
            )
        }
    }

    private func measureFold(
        extraInset: CGFloat,
        width: CGFloat,
        sizeClass: UserInterfaceSizeClass
    ) -> LaidOutRecordingList {
        let store = RecordingListFrameStore()
        let canvas = CGSize(width: width, height: 520)
        let root = FoldRecordingWidthHarness(extraInset: extraInset, store: store)
            .environment(\.horizontalSizeClass, sizeClass)
            .frame(width: canvas.width, height: canvas.height)
        let controller = UIHostingController(rootView: root)
        controller.view.bounds = CGRect(origin: .zero, size: canvas)
        controller.view.backgroundColor = UIColor(red: 0.31, green: 0.61, blue: 0.86, alpha: 1)
        let window = UIWindow(frame: CGRect(origin: .zero, size: canvas))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        let ready = expectation(description: "fold layout \(width) \(sizeClass)")
        DispatchQueue.main.async {
            controller.view.layoutIfNeeded()
            ready.fulfill()
        }
        wait(for: [ready], timeout: 2)
        return LaidOutRecordingList(
            card: store.card,
            plate: store.plate,
            controller: controller,
            window: window,
            canvas: canvas
        )
    }
}

private struct LaidOutRecordingList {
    var card: CGRect
    var plate: CGRect
    var controller: UIViewController
    var window: UIWindow
    var canvas: CGSize
}

private final class RecordingListFrameStore {
    var card = CGRect.null
    var plate = CGRect.null
    var pad = CGRect.null
}

private struct RecordingListFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Upright fold: the recording card is a sibling of the list, not a row in it.
private struct FoldRecordingWidthHarness: View {
    var extraInset: CGFloat
    var store: RecordingListFrameStore

    var body: some View {
        VStack(spacing: GlassTokens.hingeGutter) {
            RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous)
                .fill(Color.white)
                .frame(height: 120)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RecordingListFrameKey.self,
                            value: ["card": geo.frame(in: .global)]
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.horizontal, extraInset)

            List {
                Section {
                    Text("Trip")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 44)
                }
                .listRowInsets(
                    EdgeInsets(
                        top: 14,
                        leading: GlassTokens.listContentHorizontalInset,
                        bottom: 14,
                        trailing: GlassTokens.listContentHorizontalInset
                    )
                )
                .listRowBackground(
                    Color.white
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: RecordingListFrameKey.self,
                                    value: ["plate": geo.frame(in: .global)]
                                )
                            }
                        }
                        .padding(.horizontal, GlassTokens.panelHorizontalInset)
                )
                .listRowSeparator(.hidden)
            }
            .listSectionSpacing(6)
            .scrollContentBackground(.hidden)
        }
        .background(Color(red: 0.31, green: 0.61, blue: 0.86))
        .environment(\.colorScheme, .light)
        .environment(\.shellPalette, .sky)
        .onPreferenceChange(RecordingListFrameKey.self) { frames in
            if let card = frames["card"] { store.card = card }
            if let plate = frames["plate"] { store.plate = plate }
        }
    }
}
