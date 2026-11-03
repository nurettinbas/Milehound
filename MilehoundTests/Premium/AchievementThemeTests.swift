import SwiftUI
import XCTest
@testable import Milehound

final class AchievementThemeTests: XCTestCase {
    func testEveryAchievementMapsToAFamily() {
        for id in AchievementID.allCases {
            _ = id.family
            XCTAssertGreaterThanOrEqual(id.familyTier, 0)
        }
        XCTAssertEqual(Set(AchievementID.allCases.map(\.family)).count, AchievementFamily.allCases.count)
    }

    func testListOrderPutsUnlockedFirst() {
        let lockedFirst = AchievementDisplay(id: .firstTrip, currentValue: 0, unlockedAt: nil, needsCelebration: false)
        let unlockedLate = AchievementDisplay(id: .routesRegular, currentValue: 10, unlockedAt: Date(), needsCelebration: false)
        let unlockedEarly = AchievementDisplay(id: .distance100, currentValue: 100_000, unlockedAt: Date(), needsCelebration: false)
        let lockedLate = AchievementDisplay(id: .nightOwl, currentValue: 0, unlockedAt: nil, needsCelebration: false)
        let ordered = [lockedFirst, unlockedLate, unlockedEarly, lockedLate].sorted(by: AchievementDisplay.listOrder)
        XCTAssertEqual(ordered.map(\.id), [.distance100, .routesRegular, .firstTrip, .nightOwl])
    }

    func testFamilyHuesAreUnique() {
        let hues = AchievementFamily.allCases.map { AchievementTheme.familyHue(for: $0) }
        XCTAssertEqual(Set(hues).count, hues.count)
        let sorted = hues.sorted()
        for index in sorted.indices {
            let a = sorted[index]
            let b = sorted[(index + 1) % sorted.count]
            let delta = index + 1 == sorted.count ? (360 - a + b) : (b - a)
            XCTAssertGreaterThanOrEqual(
                delta,
                AchievementTheme.minimumFamilyHueDelta - 0.01,
                "hue gap \(a) → \(b)"
            )
        }
    }

    func testEnamelLadderShiftsHueWithinFamily() {
        XCTAssertNotEqual(
            AchievementTheme.enamelHue(for: .business10),
            AchievementTheme.enamelHue(for: .business50)
        )
        XCTAssertNotEqual(
            AchievementTheme.enamelHue(for: .business50),
            AchievementTheme.enamelHue(for: .business100)
        )
        XCTAssertEqual(AchievementTheme.enamelHue(for: .business10), 44, accuracy: 0.01)
        XCTAssertEqual(AchievementTheme.enamelHue(for: .business50), 52, accuracy: 0.01)
        for family in AchievementFamily.allCases where family != .distance {
            let ids = AchievementID.allCases.filter { $0.family == family }
            let hues = Set(ids.map { AchievementTheme.enamelHue(for: $0) })
            XCTAssertEqual(hues.count, ids.count, "enamel hue clones in \(family.rawValue)")
        }
    }

    func testSystemImagesAreUniqueExceptDistanceCanvas() {
        let icons = AchievementID.allCases.filter { !$0.usesCanvasGlyph }.map(\.systemImage)
        XCTAssertEqual(Set(icons).count, icons.count)
    }

    func testNewCatalogIDs() {
        XCTAssertEqual(AchievementID.business100.predecessor, .business50)
        XCTAssertEqual(AchievementID.streak100.threshold, 100)
        XCTAssertEqual(AchievementID.night1000.progressKind, .distanceMeters)
        XCTAssertEqual(AchievementID.trips50.family, .trips)
        XCTAssertEqual(AchievementID.hours24.family, .hours)
        XCTAssertEqual(AchievementID.longhaul1.threshold, 1)
        XCTAssertEqual(AchievementID.dawn10.family, .dawn)
        XCTAssertEqual(AchievementID.weekend50.predecessor, .weekend10)
        XCTAssertEqual(AchievementID.fleet2.family, .fleet)
        XCTAssertEqual(AchievementID.countries2.family, .countries)
        XCTAssertEqual(AchievementID.allCases.count, 30)
    }

    func testIdleContractsPerFamily() {
        XCTAssertTrue(AchievementMedalIdle.discTilts(.routes))
        XCTAssertTrue(AchievementMedalIdle.discTilts(.weekend))
        XCTAssertTrue(AchievementMedalIdle.discTilts(.fleet))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.business))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.trips))
        XCTAssertEqual(AchievementMedalIdle.steeringSway(phase: 0), -AchievementMedalIdle.steeringSwayDegrees, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.steeringSway(phase: 1), AchievementMedalIdle.steeringSwayDegrees, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.steeringSwayDegrees, 20, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.period(for: .trips), 2.1, accuracy: 0.001)
        XCTAssertTrue(AchievementMedalIdle.glyphOverflows(.dawn))
        XCTAssertTrue(AchievementMedalIdle.glyphOverflows(.streak))
        XCTAssertTrue(AchievementMedalIdle.glyphOverflows(.hours))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.hours))
        XCTAssertEqual(AchievementMedalIdle.hourglassFlipDegrees(phase: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.hourglassFlipDegrees(phase: 1), 180, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.period(for: .hours), 2.7, accuracy: 0.001)
        XCTAssertEqual(AchievementID.hours24.systemImage, "hourglass")
        XCTAssertEqual(AchievementID.hours100.systemImage, "hourglass.bottomhalf.filled")
        XCTAssertEqual(AchievementID.longhaul1.systemImage, "car.side.fill")
        XCTAssertEqual(AchievementMedalIdle.longhaulCruiseX(phase: 0.5, size: 100), 0, accuracy: 0.01)
        XCTAssertEqual(AchievementMedalIdle.longhaulHillY(phase: 0, size: 100), 0, accuracy: 0.01)
        XCTAssertEqual(AchievementMedalIdle.longhaulHillY(phase: 1, size: 100), 0, accuracy: 0.01)
        XCTAssertLessThan(AchievementMedalIdle.longhaulHillY(phase: 0.5, size: 100), -10)
        XCTAssertEqual(AchievementMedalIdle.longhaulNosePitch(phase: 0.5), 0, accuracy: 0.01)
        XCTAssertLessThan(AchievementMedalIdle.longhaulNosePitch(phase: 0), -10)
        XCTAssertGreaterThan(AchievementMedalIdle.longhaulNosePitch(phase: 1), 10)
        XCTAssertFalse(AchievementMedalIdle.discTilts(.longhaul))
        XCTAssertTrue(AchievementMedalIdle.glyphOverflows(.longhaul))
        XCTAssertEqual(AchievementMedalIdle.period(for: .longhaul), 2.5, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.loop(at: 0.5, duration: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.loop(at: 1.5, duration: 1), 0.5, accuracy: 0.001)
    }

    func testDistanceTiersShareFamilyAndIncreaseStrength() {
        XCTAssertEqual(AchievementID.distance100.family, .distance)
        XCTAssertEqual(AchievementID.distance1000.family, .distance)
        XCTAssertEqual(AchievementID.distance10000.family, .distance)
        XCTAssertEqual(AchievementID.distance100000.family, .distance)
        XCTAssertLessThan(AchievementID.distance100.familyTier, AchievementID.distance1000.familyTier)
        XCTAssertLessThan(AchievementID.distance1000.familyTier, AchievementID.distance10000.familyTier)
        XCTAssertLessThan(AchievementID.distance10000.familyTier, AchievementID.distance100000.familyTier)
    }

    func testDistanceMaterialsAreMetalLadder() {
        XCTAssertEqual(AchievementID.distance100.medalMaterial, .silver)
        XCTAssertEqual(AchievementID.distance1000.medalMaterial, .gold)
        XCTAssertEqual(AchievementID.distance10000.medalMaterial, .platinum)
        XCTAssertEqual(AchievementID.distance100000.medalMaterial, .diamond)
        XCTAssertNil(AchievementID.firstTrip.medalMaterial)
        XCTAssertNil(AchievementID.business10.medalMaterial)
        XCTAssertNil(AchievementID.nightOwl.medalMaterial)
    }

    func testMedalGlyphsAreWhiteIncludingSilverAndGold() {
        let white = String(describing: Color.white)
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertEqual(
                String(describing: AchievementTheme.medalPalette(for: .distance100, scheme: scheme).glyph),
                white
            )
            XCTAssertEqual(
                String(describing: AchievementTheme.medalPalette(for: .distance1000, scheme: scheme).glyph),
                white
            )
            XCTAssertEqual(
                String(describing: AchievementTheme.medalPalette(for: .distance10000, scheme: scheme).glyph),
                white
            )
            XCTAssertEqual(
                String(describing: AchievementTheme.medalPalette(for: .firstTrip, scheme: scheme).glyph),
                white
            )
        }
    }

    func testPlatinumChromeIsTealNotGray() {
        let accent = AchievementPlatinumSwatch.faceAccentDark
        let red = (accent >> 16) & 0xFF
        let green = (accent >> 8) & 0xFF
        let blue = accent & 0xFF
        XCTAssertGreaterThan(green, red)
        XCTAssertGreaterThan(blue, red)
        XCTAssertGreaterThan(green, 140)
        XCTAssertEqual(AchievementPlatinumSwatch.faceAccentDark, 0x14B2AA)
        XCTAssertEqual(AchievementPlatinumSwatch.faceAccentLight, 0x20C4BC)
    }

    func testDiamondChromeIsPurpleNotIce() {
        let accent = AchievementDiamondSwatch.faceAccentDark
        let red = (accent >> 16) & 0xFF
        let green = (accent >> 8) & 0xFF
        let blue = accent & 0xFF
        XCTAssertGreaterThan(red, green)
        XCTAssertGreaterThan(blue, green)
        XCTAssertGreaterThan(blue, 200)
        XCTAssertEqual(AchievementDiamondSwatch.faceAccentDark, 0xB794F6)
        XCTAssertEqual(AchievementDiamondSwatch.faceAccentLight, 0xC4B5FD)
        XCTAssertTrue(AchievementID.distance100000.listsWhilePredecessorLocked)
        XCTAssertFalse(AchievementID.business50.listsWhilePredecessorLocked)
    }

    func testDistance100000Catalog() {
        XCTAssertEqual(AchievementID.distance100000.rawValue, "distance.100000")
        XCTAssertEqual(AchievementID.distance100000.threshold, 100_000_000)
        XCTAssertEqual(AchievementID.distance100000.predecessor, .distance10000)
        XCTAssertEqual(AchievementID.distance100000.progressKind, .distanceMeters)
        XCTAssertEqual(AchievementID.distance100000.familyTier, 3)
    }

    func testDistance100000CaptionUsesFormattedKilometersNotRawMeters() {
        let text = AchievementProgressCaption.text(
            current: 50_000_000,
            threshold: 100_000_000,
            kind: .distanceMeters
        )
        XCTAssertFalse(text.contains("50000000"))
        XCTAssertFalse(text.contains("100000000"))
        XCTAssertEqual(
            text,
            "\(DateFormatters.formatDistance(50_000_000)) / \(DateFormatters.formatDistance(100_000_000))"
        )
    }

    func testDistanceCaptionUsesFormattedKilometersNotRawMeters() {
        let text = AchievementProgressCaption.text(
            current: 50_000,
            threshold: 100_000,
            kind: .distanceMeters
        )
        XCTAssertFalse(text.contains("50000"))
        XCTAssertFalse(text.contains("100000"))
        XCTAssertTrue(text.contains(" / "))
        XCTAssertEqual(
            text,
            "\(DateFormatters.formatDistance(50_000)) / \(DateFormatters.formatDistance(100_000))"
        )
    }

    func testCountCaptionUsesWholeNumbers() {
        XCTAssertEqual(
            AchievementProgressCaption.text(current: 3.2, threshold: 10, kind: .count),
            "3 / 10"
        )
    }

    func testNightOwlUsesDistanceCaption() {
        XCTAssertEqual(AchievementID.nightOwl.progressKind, .distanceMeters)
        XCTAssertEqual(AchievementID.cities10.progressKind, .count)
    }

    func testLockedOverlayKeepsSaturatedMedal() {
        XCTAssertEqual(AchievementTheme.lockScrimOpacity, 0.45)
        XCTAssertEqual(AchievementMedalLockOverlay.lockGlyphSize(for: 52), max(8, 52 * 0.16))
        XCTAssertEqual(AchievementMedalLockOverlay.lockGlyphSize(for: 48), max(8, 48 * 0.16))
        XCTAssertEqual(AchievementMedalLockOverlay.lockBadgeSize(for: 52), max(14, 52 * 0.28))
        XCTAssertLessThan(AchievementMedalLockOverlay.lockBadgeSize(for: 48), 48 * 0.45)
        XCTAssertFalse(AchievementMedalIdle.discTilts(.firstTrip))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.distance))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.night))
        XCTAssertTrue(AchievementMedalIdle.discTilts(.routes))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.business))
        XCTAssertEqual(AchievementMedalIdle.flagWaveDuration, 0.72, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.flagWaveSwayDegrees, 36, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.flagWaveFold, 0.24, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.flagWaveFlapDegrees, 12, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pathTravelDuration, 1.45, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobDuration, 1.8, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobAmplitude(for: 48), 48 * 0.06, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobAmplitude(for: 20), 2, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobAmplitude(for: 128), 4, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightSparkleDuration, 0.55, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pingPong(at: 0, duration: 1), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pingPong(at: 1, duration: 1), 1, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pingPong(at: 2, duration: 1), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.compactClockFPS, 12)
        XCTAssertEqual(AchievementMedalIdle.compactClockInterval, 1.0 / 12.0, accuracy: 0.0001)
    }

    func testDistancePathTravelsBottomLeftToTopRight() {
        let size = CGSize(width: 100, height: 100)
        let start = AchievementDistancePath.point(at: 0, in: size)
        let end = AchievementDistancePath.point(at: 1, in: size)
        XCTAssertLessThan(start.x, 40)
        XCTAssertGreaterThan(start.y, 60)
        XCTAssertGreaterThan(end.x, 60)
        XCTAssertLessThan(end.y, 40)
        let mid = AchievementDistancePath.point(at: 0.5, in: size)
        XCTAssertEqual(mid.x, 50, accuracy: 18)
        XCTAssertEqual(AchievementDistancePath.point(at: 0, in: size), AchievementDistancePath.start(in: size))
        XCTAssertEqual(AchievementDistancePath.point(at: 1, in: size), AchievementDistancePath.end(in: size))
    }

    func testDistancePathMotionLadder() {
        XCTAssertEqual(AchievementDistancePathMotion.for(.silver), .convoy)
        XCTAssertEqual(AchievementDistancePathMotion.for(.gold), .rendezvous)
        XCTAssertEqual(AchievementDistancePathMotion.for(.platinum), .patrol)
        XCTAssertEqual(AchievementDistancePathMotion.for(.diamond), .bloom)
        XCTAssertLessThan(AchievementDistancePathMotion.convoy.duration, AchievementDistancePathMotion.rendezvous.duration)
        XCTAssertLessThan(AchievementDistancePathMotion.rendezvous.duration, AchievementDistancePathMotion.patrol.duration)
        XCTAssertLessThan(AchievementDistancePathMotion.patrol.duration, AchievementDistancePathMotion.bloom.duration)

        let convoyStart = (
            AchievementDistancePathMotion.convoy.nodeProgress(phase: 0, index: 0),
            AchievementDistancePathMotion.convoy.nodeProgress(phase: 0, index: 1)
        )
        XCTAssertEqual(convoyStart.0, 0, accuracy: 0.001)
        XCTAssertGreaterThan(convoyStart.1, convoyStart.0)
        XCTAssertEqual(AchievementDistancePathMotion.convoy.nodeProgress(phase: 1, index: 0), 1, accuracy: 0.001)

        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0, index: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0, index: 1), 1, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0.5, index: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0.5, index: 1), 0.5, accuracy: 0.001)

        let patrolMid = (
            AchievementDistancePathMotion.patrol.nodeProgress(phase: 1, index: 0),
            AchievementDistancePathMotion.patrol.nodeProgress(phase: 1, index: 1)
        )
        XCTAssertLessThan(patrolMid.0, 0.5)
        XCTAssertGreaterThan(patrolMid.1, 0.5)

        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 0, index: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 0, index: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 1, index: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 1, index: 1), 1, accuracy: 0.001)
    }

    func testGalleryCardsStayCompact() {
        XCTAssertLessThan(AchievementGalleryTokens.cardHeight, 220)
        XCTAssertLessThanOrEqual(AchievementGalleryTokens.bodySlotHeight, 32)
        XCTAssertLessThanOrEqual(AchievementGalleryTokens.medalSize, 48)
        XCTAssertEqual(AchievementGalleryTokens.shareSlotHeight, 44)
    }

    func testGalleryExpandGrowsFromSourceFrame() {
        let source = CGRect(x: 16, y: 240, width: 358, height: 96)
        let overlay = CGRect(x: 0, y: 0, width: 390, height: 844)
        XCTAssertEqual(
            AchievementGalleryExpandLayout.localSurface(sourceGlobal: source, overlayGlobal: overlay, expanded: false),
            source
        )
        XCTAssertEqual(
            AchievementGalleryExpandLayout.localSurface(sourceGlobal: source, overlayGlobal: overlay, expanded: true),
            CGRect(origin: .zero, size: overlay.size)
        )
        XCTAssertEqual(AchievementGalleryExpandLayout.cornerRadius(expanded: false), StatsCardTokens.radius)
        XCTAssertEqual(AchievementGalleryExpandLayout.cornerRadius(expanded: true), 0)
    }

    func testGalleryExpandMissingSourceFillsOverlay() {
        let overlay = CGRect(x: 0, y: -20, width: 390, height: 884)
        let filled = CGRect(origin: .zero, size: overlay.size)
        XCTAssertEqual(
            AchievementGalleryExpandLayout.localSurface(sourceGlobal: .zero, overlayGlobal: overlay, expanded: false),
            filled
        )
        XCTAssertFalse(AchievementGalleryExpandLayout.hasUsableSource(.zero))
        XCTAssertNil(MilehoundMotion.badgeCardExpand(reduceMotion: true))
        XCTAssertNotNil(MilehoundMotion.badgeCardExpand(reduceMotion: false))
    }

    func testGalleryExpandRejectsCardUnderTheStatusBar() {
        let window = CGRect(x: 0, y: 0, width: 390, height: 844)
        let stranded = CGRect(x: 16, y: 4, width: 358, height: 120)
        XCTAssertFalse(
            AchievementGalleryExpandLayout.isOnScreenCard(stranded, windowBounds: window, topInset: 59)
        )
        let onScreen = CGRect(x: 16, y: 240, width: 358, height: 96)
        XCTAssertTrue(
            AchievementGalleryExpandLayout.isOnScreenCard(onScreen, windowBounds: window, topInset: 59)
        )
        let belowFold = CGRect(x: 16, y: 820, width: 358, height: 96)
        XCTAssertFalse(
            AchievementGalleryExpandLayout.isOnScreenCard(belowFold, windowBounds: window, topInset: 59)
        )
        let tallCard = CGRect(x: 16, y: 180, width: 358, height: 900)
        XCTAssertTrue(
            AchievementGalleryExpandLayout.isOnScreenCard(tallCard, windowBounds: window, topInset: 59)
        )
    }

    func testExpandBackSwipeDismissesALeadingFlick() {
        XCTAssertTrue(CardExpandBackSwipe.shouldDismiss(travel: 80, predicted: 80, vertical: 10))
        XCTAssertTrue(CardExpandBackSwipe.shouldDismiss(travel: 30, predicted: 140, vertical: 8))
        XCTAssertFalse(CardExpandBackSwipe.shouldDismiss(travel: 20, predicted: 40, vertical: 4))
        XCTAssertFalse(CardExpandBackSwipe.shouldDismiss(travel: 90, predicted: 120, vertical: 90))
        XCTAssertFalse(CardExpandBackSwipe.shouldDismiss(travel: -40, predicted: -80, vertical: 0))
    }
}
