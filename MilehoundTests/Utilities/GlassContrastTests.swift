import SwiftUI
import XCTest
@testable import Milehound

final class GlassContrastTests: XCTestCase {
    func testLinearizationDiffersFromGammaMix() {
        let sandMid = ShellPalette.sand.atmosphere(for: .light).mid
        XCTAssertNotEqual(
            sandMid.relativeLuminance,
            GlassContrast.wcagRelativeLuminance(sandMid),
            accuracy: 0.001
        )
    }

    func testAllPalettesLightPanelsAreBrighterThanChrome() {
        for palette in ShellPalette.allCases {
            let chrome = palette.atmosphere(for: .light).chrome
            let chromeLum = GlassContrast.wcagRelativeLuminance(chrome)
            for panel in [
                GlassContrast.materialPanelFill(palette: palette, increasedContrast: false),
                GlassContrast.nativePanelFill(palette: palette, increasedContrast: false),
                GlassContrast.solidPanelFill(palette: palette)
            ] {
                XCTAssertGreaterThan(
                    GlassContrast.wcagRelativeLuminance(panel),
                    chromeLum,
                    palette.rawValue
                )
            }
        }
    }

    func testGlassTintIsMidFamilyNotChrome() {
        for palette in ShellPalette.allCases {
            let atmosphere = palette.atmosphere(for: .light)
            let tint = GlassContrast.glassTint(palette: palette)
            XCTAssertNotEqual(tint, atmosphere.chrome, palette.rawValue)
            XCTAssertEqual(
                palette.glassReadabilityTintRGB(for: .light),
                tint,
                palette.rawValue
            )
            let tintLum = GlassContrast.wcagRelativeLuminance(tint)
            let midLum = GlassContrast.wcagRelativeLuminance(atmosphere.mid)
            let chromeLum = GlassContrast.wcagRelativeLuminance(atmosphere.chrome)
            XCTAssertLessThan(abs(tintLum - midLum), abs(tintLum - chromeLum), palette.rawValue)
        }
    }

    func testForestAndMintPanelsStayNearAtmosphereMid() {
        for palette: ShellPalette in [.forest, .mint] {
            let mid = palette.atmosphere(for: .light).mid
            let panel = GlassContrast.materialPanelFill(palette: palette, increasedContrast: false)
            let midLum = GlassContrast.wcagRelativeLuminance(mid)
            let panelLum = GlassContrast.wcagRelativeLuminance(panel)
            XCTAssertLessThan(abs(panelLum - midLum), 0.12, palette.rawValue)
            XCTAssertGreaterThan(
                panelLum,
                GlassContrast.wcagRelativeLuminance(palette.atmosphere(for: .light).chrome),
                palette.rawValue
            )
        }
    }

    func testSolidFallbackIsNotSystemWhiteOrChromePlate() {
        for palette in ShellPalette.allCases {
            let solid = palette.opaquePanelFillRGB(for: .light)
            XCTAssertEqual(solid, GlassContrast.solidPanelFill(palette: palette), palette.rawValue)
            XCTAssertNotEqual(solid, ShellRGB(1, 1, 1), palette.rawValue)
            XCTAssertNotEqual(solid, palette.atmosphere(for: .light).chrome, palette.rawValue)
            XCTAssertGreaterThan(
                GlassContrast.wcagRelativeLuminance(solid),
                GlassContrast.wcagRelativeLuminance(palette.atmosphere(for: .light).chrome),
                palette.rawValue
            )
        }
    }

    func testIncreasedContrastDoesNotIncreaseWhiteFrost() {
        XCTAssertEqual(LightGlassPalette.panelFillOpacity, GlassContrast.panelFrostOpacity)
        for palette in ShellPalette.allCases {
            let standard = GlassContrast.materialTintOpacity(palette: palette, increasedContrast: false)
            let boosted = GlassContrast.materialTintOpacity(palette: palette, increasedContrast: true)
            XCTAssertGreaterThan(boosted, standard, palette.rawValue)
            XCTAssertEqual(standard, GlassContrast.panelTintOpacity, palette.rawValue)
            let standardPanel = GlassContrast.materialPanelFill(palette: palette, increasedContrast: false)
            let contrastPanel = GlassContrast.materialPanelFill(palette: palette, increasedContrast: true)
            XCTAssertLessThanOrEqual(
                GlassContrast.wcagRelativeLuminance(contrastPanel),
                GlassContrast.wcagRelativeLuminance(standardPanel) + 0.001,
                palette.rawValue
            )
        }
    }

    func testTintOpacitiesStayLight() {
        XCTAssertEqual(GlassContrast.panelTintOpacity, 0.22)
        XCTAssertEqual(GlassContrast.nativeGlassTintOpacity, 0.50)
        XCTAssertEqual(GlassContrast.nativeIncreasedContrastTintOpacity, 0.62)
        XCTAssertEqual(GlassContrast.nativeTintBottomMix, 0.42)
        XCTAssertGreaterThan(GlassContrast.nativeGlassTintOpacity, GlassContrast.panelTintOpacity)
        XCTAssertGreaterThan(GlassContrast.nativeTintBottomMix, GlassContrast.glassTintBottomMix)
        for palette in ShellPalette.allCases {
            XCTAssertLessThan(
                GlassContrast.wcagRelativeLuminance(GlassContrast.nativeGlassTint(palette: palette)),
                GlassContrast.wcagRelativeLuminance(GlassContrast.glassTint(palette: palette)),
                palette.rawValue
            )
            XCTAssertNotEqual(
                GlassContrast.nativeGlassTint(palette: palette),
                palette.atmosphere(for: .light).chrome,
                palette.rawValue
            )
        }
        XCTAssertEqual(GlassContrast.tabBarGlassTintOpacity, 0.28)
        XCTAssertEqual(GlassContrast.tabBarSystemGlassTintOpacity, 0.05)
        XCTAssertEqual(GlassContrast.tabBarClearGlassTintOpacity, 0.22)
        XCTAssertLessThan(GlassContrast.tabBarSystemGlassTintOpacity, GlassContrast.tabBarClearGlassTintOpacity)
        XCTAssertLessThan(GlassContrast.tabBarClearGlassTintOpacity, GlassContrast.nativeGlassTintOpacity)
        XCTAssertLessThan(LightGlassPalette.nativeRimOpacity, LightGlassPalette.panelRimOpacity)
        XCTAssertEqual(LightGlassPalette.nativeRimOpacity, 0.10)
        XCTAssertLessThan(GlassContrast.panelTintOpacity, 0.40)
        XCTAssertLessThan(GlassContrast.tabBarGlassTintOpacity, 0.40)
        XCTAssertLessThan(GlassContrast.recordingWashOpacity, 0.45)
        for palette in ShellPalette.allCases {
            XCTAssertEqual(
                GlassContrast.materialTintOpacity(palette: palette, increasedContrast: false),
                GlassContrast.panelTintOpacity,
                palette.rawValue
            )
        }
    }

    func testSelectedChipIsOpenPaletteFillWithWhiteType() {
        XCTAssertEqual(LightGlassPalette.selectedChipText, Color.white)
        XCTAssertEqual(
            LightGlassPalette.selectedChipFill(for: .forest),
            GlassContrast.selectedChipFill(palette: .forest).color
        )
        XCTAssertNotEqual(
            LightGlassPalette.selectedChipFill(for: .forest),
            ShellPalette.forest.chromeColor(for: .light)
        )
        XCTAssertGreaterThan(
            GlassContrast.wcagRelativeLuminance(GlassContrast.selectedChipFill(palette: .forest)),
            GlassContrast.wcagRelativeLuminance(ShellPalette.forest.atmosphere(for: .light).chrome)
        )
    }

    func testStatsTextColorIsGlassText() {
        XCTAssertEqual(StatsTextColor.secondary(for: .light), GlassText.secondary(for: .light))
        XCTAssertEqual(StatsTextColor.tertiary(for: .light), GlassText.tertiary(for: .light))
        XCTAssertNotEqual(StatsTextColor.secondary(for: .light), Color.black.opacity(0.72))
        XCTAssertEqual(GlassText.primary(for: .light), Color.white)
    }

    func testToolbarLightFillIsLighterThanSolidPanel() {
        for palette in ShellPalette.allCases {
            let frost = GlassContrast.toolbarLightFill(palette: palette)
            let panel = palette.opaquePanelFillRGB(for: .light)
            XCTAssertGreaterThan(
                GlassContrast.wcagRelativeLuminance(frost),
                GlassContrast.wcagRelativeLuminance(panel),
                palette.rawValue
            )
            XCTAssertNotEqual(frost, GlassContrast.white, palette.rawValue)
        }
    }

    func testHostBudgetConstant() {
        XCTAssertEqual(GlassHostBudget.maxNativeHostsPerScreen, 8)
    }
}
