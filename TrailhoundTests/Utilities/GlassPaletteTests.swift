import SwiftUI
import UIKit
import XCTest
@testable import Trailhound

final class GlassPaletteTests: XCTestCase {
    func testDarkTextUsesSystemHierarchy() {
        XCTAssertEqual(GlassText.primary(for: .dark), Color.primary)
        XCTAssertEqual(GlassText.secondary(for: .dark), Color.secondary)
    }

    func testLightTextUsesWhiteHierarchy() {
        XCTAssertEqual(GlassText.primary(for: .light), LightGlassPalette.textPrimary)
        XCTAssertEqual(GlassText.secondary(for: .light), LightGlassPalette.textSecondary)
        XCTAssertEqual(GlassText.tertiary(for: .light), LightGlassPalette.textTertiary)
        XCTAssertEqual(GlassText.placeholder(for: .light), LightGlassPalette.textPlaceholder)
        XCTAssertEqual(GlassText.disabled(for: .light), LightGlassPalette.textDisabled)
    }

    func testDarkSemanticsStaySystem() {
        XCTAssertEqual(GlassSemantic.recording(for: .dark), Color.red)
        XCTAssertEqual(GlassSemantic.paused(for: .dark), Color.orange)
        XCTAssertEqual(GlassSemantic.success(for: .dark), Color.green)
        XCTAssertEqual(GlassSemantic.destructive(for: .dark), Color.red)
    }

    func testLightSemanticsUseLiftedPalette() {
        XCTAssertEqual(GlassSemantic.recording(for: .light), LightGlassPalette.recording)
        XCTAssertEqual(GlassSemantic.paused(for: .light), LightGlassPalette.paused)
        XCTAssertEqual(GlassSemantic.success(for: .light), LightGlassPalette.success)
        XCTAssertEqual(GlassSemantic.destructive(for: .light), LightGlassPalette.destructive)
    }

    func testRecordingSegmentThumbUsesPaletteTint() {
        XCTAssertEqual(
            RecordingSegmentChrome.thumb(for: .forest, scheme: .light),
            ShellPalette.forest.tintColor(for: .light)
        )
        XCTAssertNotEqual(
            RecordingSegmentChrome.thumb(for: .forest, scheme: .light),
            RecordingSegmentChrome.thumb(for: .rose, scheme: .light)
        )
        let selected = RecordingSegmentChrome.selectedLabel(palette: .forest, scheme: .light)
        XCTAssertTrue(
            selected == ShellPalette.forest.chromeColor(for: .light) || selected == Color.white
        )
        XCTAssertEqual(
            RecordingSegmentChrome.label(
                isSelected: false,
                palette: .forest,
                scheme: .light,
                reduceTransparency: false
            ),
            LiveFollowHUDInk.secondary(scheme: .light, palette: .forest, reduceTransparency: false)
        )
        XCTAssertEqual(
            LiveFollowHUDInk.primary(scheme: .light, palette: .sky, reduceTransparency: false),
            ShellPalette.sky.chromeColor(for: .light)
        )
        XCTAssertEqual(
            LiveFollowHUDInk.primary(scheme: .light, palette: .sky, reduceTransparency: true),
            Color.white
        )
    }

    func testRecordingCardFillFollowsPalette() {
        let sky = RecordingCardStyle.fillColors(isPaused: false, palette: .sky, scheme: .light)
        let rose = RecordingCardStyle.fillColors(isPaused: false, palette: .rose, scheme: .light)
        XCTAssertNotEqual(sky, rose)
        XCTAssertEqual(sky[1], ShellPalette.sky.tintColor(for: .light))
        XCTAssertEqual(rose[1], ShellPalette.rose.tintColor(for: .light))
    }

    func testNotificationBadgeIsOpaqueSystemRed() {
        XCTAssertEqual(
            GlassSemantic.notificationBadge,
            Color(red: 1.0, green: 0.231, blue: 0.188)
        )
        XCTAssertNotEqual(
            GlassSemantic.notificationBadge,
            LightGlassPalette.destructive
        )
        XCTAssertNotEqual(
            GlassSemantic.notificationBadge,
            ShellPalette.rose.tintColor(for: .light)
        )
    }

    func testAtmosphereTokensMatchSaturatedSkyBlue() {
        XCTAssertEqual(TrailhoundBrandColors.atmosphereTop, LightGlassPalette.atmosphereTop)
        XCTAssertEqual(TrailhoundBrandColors.atmosphereMid, LightGlassPalette.atmosphereMid)
        XCTAssertEqual(TrailhoundBrandColors.atmosphereBottom, LightGlassPalette.atmosphereBottom)
    }

    func testSegmentedTintFollowsPalette() {
        XCTAssertEqual(
            GlassControlTint.segmented(for: .light, palette: .forest),
            ShellPalette.forest.tintColor(for: .light)
        )
        XCTAssertEqual(
            GlassControlTint.segmented(for: .dark, palette: .sunset),
            ShellPalette.sunset.tintColor(for: .dark)
        )
        XCTAssertNotEqual(
            GlassControlTint.segmented(for: .light, palette: .forest),
            GlassControlTint.segmented(for: .light, palette: .sky)
        )
    }

    func testSelectedChipIsWhiteOnPaletteFill() {
        XCTAssertEqual(LightGlassPalette.selectedChipText, Color.white)
        XCTAssertEqual(
            LightGlassPalette.selectedChipFill(for: .sky),
            GlassContrast.selectedChipFill(palette: .sky).color
        )
        XCTAssertNotEqual(
            LightGlassPalette.selectedChipFill(for: .sky),
            ShellPalette.sky.chromeColor(for: .light)
        )
    }

    func testToggleTintIsSaturatedNotWhite() {
        XCTAssertEqual(
            GlassControlTint.toggle(for: .light, palette: .sand),
            ShellPalette.sand.tintColor(for: .light)
        )
        XCTAssertNotEqual(GlassControlTint.toggle(for: .light, palette: .sand), Color.white)
        XCTAssertEqual(
            GlassControlTint.toggle(for: .dark, palette: .sky),
            ShellPalette.sky.tintColor(for: .dark)
        )
    }

    func testMenuPickerControlTintIsWhiteOnLightShell() {
        XCTAssertEqual(GlassControlTint.control(for: .light, palette: .pink), Color.white)
        XCTAssertEqual(GlassControlTint.control(for: .light, palette: .sunset), Color.white)
        XCTAssertEqual(
            GlassControlTint.control(for: .dark, palette: .sky),
            ShellPalette.sky.tintColor(for: .dark)
        )
    }

    func testDatePickerInkIsWhiteNotBlack() {
        XCTAssertEqual(GlassControlTint.datePickerCompact(for: .light), Color.white)
        XCTAssertEqual(GlassControlTint.datePickerSelectedFill, Color.white)
        XCTAssertEqual(GlassControlTint.datePickerSelectedTitle, Color.white)
        XCTAssertNotEqual(
            GlassControlTint.datePickerCompact(for: .light),
            GlassControlTint.segmented(for: .light, palette: .sky)
        )
        XCTAssertTrue(
            GlassDatePickerChrome.isAccentBlue(UIColor(red: 0, green: 0.48, blue: 1, alpha: 1))
        )
        XCTAssertFalse(GlassDatePickerChrome.isAccentBlue(.white))
        XCTAssertFalse(GlassDatePickerChrome.isAccentBlue(.black))
    }

    func testNativeGlassTintFollowsPalette() {
        let sky = LightGlassPalette.nativeTint(for: .sky)
        let magenta = LightGlassPalette.nativeTint(for: .magenta)
        XCTAssertNotEqual(sky, magenta)
        XCTAssertEqual(
            sky,
            GlassContrast.nativeGlassTint(palette: .sky).color.opacity(
                GlassContrast.adaptiveNativeTintOpacity(palette: .sky, increasedContrast: false)
            )
        )
        XCTAssertGreaterThanOrEqual(
            GlassContrast.adaptiveNativeTintOpacity(palette: .sky, increasedContrast: false),
            GlassContrast.nativeGlassTintOpacity
        )
    }

    func testLightFieldRimIsWhiteAndDarkHasNone() {
        XCTAssertEqual(LightGlassPalette.fieldRimOpacity, 0.42)
        XCTAssertEqual(LightGlassPalette.fieldIncreasedContrastRimOpacity, 0.56)
        XCTAssertEqual(GlassTokens.fieldRimWidth, 1)
        XCTAssertEqual(
            GlassTokens.fieldRim(for: .light),
            Color.white.opacity(LightGlassPalette.fieldRimOpacity)
        )
        XCTAssertEqual(
            GlassTokens.fieldRim(for: .light, increasedContrast: true),
            Color.white.opacity(LightGlassPalette.fieldIncreasedContrastRimOpacity)
        )
        XCTAssertEqual(GlassTokens.fieldRim(for: .dark), Color.clear)
        XCTAssertEqual(GlassTokens.fieldRim(for: .dark, increasedContrast: true), Color.clear)
        XCTAssertGreaterThan(LightGlassPalette.fieldRimOpacity, LightGlassPalette.nativeRimOpacity)
        XCTAssertLessThan(LightGlassPalette.fieldRimOpacity, 0.72)
    }

    func testToolbarControlCircleMatchesOverlayHitSize() {
        XCTAssertEqual(GlassTokens.toolbarControlCircleSide, 44)
        XCTAssertEqual(GlassTokens.toolbarFrozenCircleSide, 36)
        XCTAssertEqual(6 + 32 + 6, Int(GlassTokens.toolbarControlCircleSide))
        XCTAssertEqual(GlassTokens.toolbarCircleClusterSpacing, 16)
        XCTAssertEqual(GlassTokens.toolbarSharedClusterSpacing, 8)
        XCTAssertEqual(GlassTokens.toolbarClusterGlyphWidth, 32)
        XCTAssertLessThan(
            GlassTokens.toolbarClusterGlyphWidth + GlassTokens.toolbarSharedClusterSpacing + GlassTokens.toolbarClusterGlyphWidth,
            GlassTokens.toolbarControlCircleSide + GlassTokens.toolbarCircleClusterSpacing + GlassTokens.toolbarControlCircleSide
        )
    }

    func testGlassPlainHitStyleIsAvailable() {
        _ = GlassPlainHitButtonStyle()
        _ = TrailhoundCardPressButtonStyle()
    }
}
