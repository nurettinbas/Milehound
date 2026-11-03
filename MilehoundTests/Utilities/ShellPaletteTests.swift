import SwiftUI
import XCTest
@testable import Milehound

final class ShellPaletteTests: XCTestCase {
    func testTwentyCuratedHues() {
        XCTAssertEqual(ShellPalette.allCases.count, 20)
        XCTAssertEqual(ShellPalette.default, .sky)
        XCTAssertEqual(ShellPalette.storageKey, "shellPalette")
    }

    func testSkyLightMatchesBrandAtmosphere() {
        let sky = ShellPalette.sky.atmosphere(for: .light)
        XCTAssertEqual(sky.top.color, MilehoundBrandColors.atmosphereTop)
        XCTAssertEqual(sky.mid.color, MilehoundBrandColors.atmosphereMid)
        XCTAssertEqual(sky.bottom.color, MilehoundBrandColors.atmosphereBottom)
        XCTAssertEqual(sky.tint.color, MilehoundBrandColors.brandBottom)
        XCTAssertEqual(sky.chrome.color, LightGlassPalette.controlTint)
    }

    func testLightAtmosphereIsSoftenedWithoutWeakeningControls() {
        let sky = ShellPalette.sky.atmosphere(for: .light)
        XCTAssertEqual(sky.top.r, 0.5257, accuracy: 0.000_001)
        XCTAssertEqual(sky.mid.g, 0.6373, accuracy: 0.000_001)
        XCTAssertEqual(sky.bottom.b, 0.8047, accuracy: 0.000_001)
        XCTAssertEqual(sky.tint, ShellRGB(0.23, 0.56, 0.85))
        XCTAssertEqual(sky.chrome, ShellRGB(0.090, 0.294, 0.561))
    }

    func testSkyDarkKeepsLegacyNavy() {
        let sky = ShellPalette.sky.atmosphere(for: .dark)
        XCTAssertEqual(sky.top, ShellRGB(0.03, 0.07, 0.14))
        XCTAssertEqual(sky.mid, ShellRGB(0.07, 0.13, 0.24))
        XCTAssertEqual(sky.bottom, ShellRGB(0.04, 0.10, 0.20))
    }

    func testEveryPaletteResolvesBothSchemes() {
        for palette in ShellPalette.allCases {
            let light = palette.atmosphere(for: .light)
            let dark = palette.atmosphere(for: .dark)
            XCTAssertEqual(light.gradientColors.count, 3)
            XCTAssertEqual(dark.gradientColors.count, 3)
            XCTAssertLessThan(
                dark.mid.relativeLuminance,
                light.mid.relativeLuminance,
                "\(palette.rawValue) dark mid should be darker than light mid"
            )
            XCTAssertLessThan(dark.mid.relativeLuminance, 0.25, palette.rawValue)
            XCTAssertFalse(
                palette.usesLightChrome(for: .light),
                "\(palette.rawValue) light type is white on the saturated shell"
            )
        }
    }

    func testLightTypeIsWhiteOnEveryPalette() {
        XCTAssertEqual(ShellPalette.sky.shellForeground(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.sand.shellForeground(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.gold.shellForeground(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.sky.shellTint(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.sky.toolbarColorScheme(for: .light), .light)
        XCTAssertEqual(ShellPalette.sky.toolbarColorScheme(for: .dark), .dark)
    }

    func testStoredFallsBackToSky() {
        let suiteName = "test.milehound.shellPalette.stored.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ShellPalette.stored(in: defaults), .sky)
        defaults.set("not-a-color", forKey: ShellPalette.storageKey)
        XCTAssertEqual(ShellPalette.stored(in: defaults), .sky)
        defaults.set("ember", forKey: ShellPalette.storageKey)
        XCTAssertEqual(ShellPalette.stored(in: defaults), .ember)
    }

    func testComplementaryInkOpposesWarmAndCoolPalettes() {
        let goldInk = ShellPalette.gold.atmosphere(for: .light).mid.complementaryInk(for: .light)
        XCTAssertGreaterThan(goldInk.b, goldInk.r)
        let skyInk = ShellPalette.sky.atmosphere(for: .light).mid.complementaryInk(for: .light)
        XCTAssertGreaterThan(skyInk.r, skyInk.b)
        XCTAssertNotEqual(goldInk, skyInk)
        XCTAssertEqual(
            ShellPalette.sky.atmosphere(for: .light).mid.rotatedInk(degrees: 180, for: .light),
            skyInk
        )
    }

    func testForecastMixStopsUseDistinctHuesAndThemeTint() {
        func hueDistance(_ a: Double, _ b: Double) -> Double {
            let delta = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(delta, 360 - delta)
        }

        for palette in ShellPalette.allCases {
            let drive = StatsSegmentTokens.fillRGB(index: 0, scheme: .light, palette: palette)
            let installments = StatsSegmentTokens.fillRGB(index: 1, scheme: .light, palette: palette)
            let other = StatsSegmentTokens.fillRGB(index: 2, scheme: .light, palette: palette)
            XCTAssertEqual(drive, palette.atmosphere(for: .light).tint, palette.rawValue)
            XCTAssertEqual(drive, RecapSpendInk.fuelRGB(scheme: .light, palette: palette), palette.rawValue)
            XCTAssertEqual(installments, RecapSpendInk.expensesRGB(scheme: .light, palette: palette), palette.rawValue)
            XCTAssertGreaterThan(hueDistance(drive.hsl.h, installments.hsl.h), 40, palette.rawValue)
            XCTAssertGreaterThan(hueDistance(drive.hsl.h, other.hsl.h), 40, palette.rawValue)
            XCTAssertGreaterThan(hueDistance(installments.hsl.h, other.hsl.h), 40, palette.rawValue)
        }
    }

    /// The cost-card figure must stay primary glass ink. Fuel stop 0 is the shell tint, and the frozen Light plate is that same family.
    func testRecapFuelInkDisappearsOnLightCostPlate() {
        for palette in ShellPalette.allCases {
            let ink = RecapSpendInk.fuelRGB(scheme: .light, palette: palette)
            let plate = palette.opaquePanelFillRGB(for: .light)
            XCTAssertLessThan(
                GlassContrast.contrastRatio(ink, plate),
                GlassContrast.supportingContrast,
                palette.rawValue
            )
        }
    }

    func testOrangeLightIsNotNavy() {
        let orange = ShellPalette.orange.atmosphere(for: .light)
        XCTAssertNotEqual(orange.mid.color, MilehoundBrandColors.atmosphereMid)
        XCTAssertGreaterThan(orange.mid.r, orange.mid.b)
    }

    func testDonutSliceLeadColorFollowsPaletteTint() {
        let forest = StatsChartTheme.sliceColor(
            forStableKey: "a",
            durationStyle: false,
            domainKeys: ["a"],
            palette: .forest,
            scheme: .light
        )
        let sky = StatsChartTheme.sliceColor(
            forStableKey: "a",
            durationStyle: false,
            domainKeys: ["a"],
            palette: .sky,
            scheme: .light
        )
        XCTAssertEqual(forest, ShellPalette.forest.tintColor(for: .light))
        XCTAssertEqual(sky, ShellPalette.sky.tintColor(for: .light))
        XCTAssertNotEqual(forest, sky)
    }

    func testVehicleSliceColorsDifferAcrossStableKeys() {
        let keys = ["puma", "vespa"]
        let puma = StatsChartTheme.sliceColor(
            forStableKey: "puma",
            durationStyle: false,
            domainKeys: keys,
            palette: .sky,
            scheme: .light
        )
        let vespa = StatsChartTheme.sliceColor(
            forStableKey: "vespa",
            durationStyle: false,
            domainKeys: keys,
            palette: .sky,
            scheme: .light
        )
        XCTAssertNotEqual(puma, vespa)
    }

    func testAppTabBarIndexMatchesTabViewOrder() {
        XCTAssertEqual(AppTab.trips.tabBarIndex, 0)
        XCTAssertEqual(AppTab.pairing.tabBarIndex, 1)
        XCTAssertEqual(AppTab.stats.tabBarIndex, 2)
        XCTAssertEqual(AppTab.year.tabBarIndex, 3)
        XCTAssertEqual(AppTab.settings.tabBarIndex, 4)
    }

    func testTabBarSelectionFollowsPaletteTint() {
        let forest = MilehoundTabBarTheme.selectedUIColor(palette: .forest, scheme: .light)
        let sunset = MilehoundTabBarTheme.selectedUIColor(palette: .sunset, scheme: .light)
        let sky = MilehoundTabBarTheme.selectedUIColor(palette: .sky, scheme: .light)
        XCTAssertNotEqual(forest, sunset)
        XCTAssertNotEqual(forest, sky)

        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        forest.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        XCTAssertGreaterThan(fg, fr)
        XCTAssertGreaterThan(fg, fb)

        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        sunset.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        XCTAssertGreaterThan(sr, sb)
    }

    func testTabBarPagePlateFollowsAtmosphereMid() {
        let pink = MilehoundTabBarTheme.pagePlateUIColor(palette: .pink, scheme: .light)
        let expected = MilehoundTabBarTheme.uiColor(ShellPalette.pink.atmosphere(for: .light).mid)
        XCTAssertEqual(pink, expected)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        pink.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(r, 0.5)
        XCTAssertGreaterThan((r + g + b) / 3, 0.4)
    }

    func testHomeScreenIconFillMatchesAlternateIconRecipes() {
        XCTAssertEqual(
            ShellPalette.sand.homeScreenIconFillRGB(for: .light),
            ShellPalette.sand.atmosphere(for: .light).tint
        )
        XCTAssertEqual(
            ShellPalette.sand.homeScreenIconFillRGB(for: .dark),
            ShellPalette.sand.atmosphere(for: .dark).mid
        )
        XCTAssertEqual(
            ShellPalette.forest.homeScreenIconFillRGB(for: .light),
            ShellRGB(0.16, 0.48, 0.24)
        )
        XCTAssertEqual(
            ShellPalette.forest.homeScreenIconFillRGB(for: .dark),
            ShellRGB(0.07, 0.16, 0.08)
        )
        XCTAssertEqual(
            ShellPalette.sky.homeScreenIconFill(for: .light),
            MilehoundBrandColors.brandBottom
        )
        XCTAssertGreaterThan(
            ShellPalette.orange.homeScreenIconFillRGB(for: .light).relativeLuminance,
            ShellPalette.orange.homeScreenIconFillRGB(for: .dark).relativeLuminance
        )
    }

    func testTabBarSelectedGlyphMatchesAppearanceTint() {
        for palette in ShellPalette.allCases {
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let expected = MilehoundTabBarTheme.uiColor(palette.atmosphere(for: scheme).tint)
                XCTAssertEqual(
                    MilehoundTabBarTheme.selectionTintUIColor(palette: palette, scheme: scheme),
                    expected,
                    "\(palette.rawValue) \(scheme)"
                )
                XCTAssertEqual(
                    MilehoundTabBarTheme.selectedGlyphUIColor(palette: palette, scheme: scheme),
                    expected,
                    "\(palette.rawValue) \(scheme)"
                )
            }
        }
        XCTAssertNotEqual(
            MilehoundTabBarTheme.selectionTintUIColor(palette: .ocean, scheme: .light),
            MilehoundTabBarTheme.selectionTintUIColor(palette: .ocean, scheme: .dark)
        )
        XCTAssertNotEqual(
            MilehoundTabBarTheme.selectionTintUIColor(palette: .forest, scheme: .light),
            MilehoundTabBarTheme.selectionTintUIColor(palette: .sunset, scheme: .light)
        )
        XCTAssertNotEqual(
            MilehoundTabBarTheme.selectedGlyphUIColor(palette: .sky, scheme: .light),
            UIColor.white
        )
    }

    func testTabBarLightSelectedMatchesDarkVividTint() {
        for palette in ShellPalette.allCases {
            XCTAssertEqual(
                MilehoundTabBarTheme.selectedUIColor(palette: palette, scheme: .light),
                MilehoundTabBarTheme.selectedUIColor(palette: palette, scheme: .dark),
                palette.rawValue
            )
        }
        let lime = MilehoundTabBarTheme.selectedUIColor(palette: .lime, scheme: .light)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        lime.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(g, r)
        XCTAssertGreaterThan(g, 0.5)
    }

    func testTabBarClearGlassTintMatchesCardFamilyAtLowerOpacity() {
        let pink = MilehoundTabBarTheme.clearGlassTintUIColor(palette: .pink)
        let expected = MilehoundTabBarTheme.uiColor(
            GlassContrast.nativeGlassTint(palette: .pink),
            alpha: CGFloat(GlassContrast.tabBarClearGlassTintOpacity)
        )
        XCTAssertEqual(pink, expected)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        pink.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Double(a), GlassContrast.tabBarClearGlassTintOpacity, accuracy: 0.001)
        XCTAssertGreaterThan(r, b)
        XCTAssertNotEqual(
            MilehoundTabBarTheme.clearGlassTintUIColor(palette: .pink),
            MilehoundTabBarTheme.clearGlassTintUIColor(palette: .sky)
        )
    }

    @MainActor
    func testSelectedTabSymbolKeepsSize() {
        let tint = UIColor(red: 0.90, green: 0.28, blue: 0.22, alpha: 1)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        for symbol in MilehoundTabBarTheme.itemSymbols {
            let source = UIImage(systemName: symbol.fill, withConfiguration: config)
            XCTAssertNotNil(source, symbol.fill)
            let image = MilehoundTabBarCompact.tintedSelectionImage(source!, tint: tint)
            XCTAssertEqual(image.size, source!.size, symbol.fill)
            XCTAssertEqual(image.scale, source!.scale, symbol.fill)
            XCTAssertEqual(image.renderingMode, .alwaysTemplate, symbol.fill)
        }
    }

    func testRecapTabFillSymbolExists() {
        XCTAssertEqual(MilehoundTabBarTheme.itemSymbols.count, 5)
        XCTAssertEqual(MilehoundTabBarTheme.itemSymbols[3].outline, "star")
        XCTAssertEqual(MilehoundTabBarTheme.itemSymbols[3].fill, "star.fill")
        XCTAssertNotNil(UIImage(systemName: "star.fill"))
        for symbol in MilehoundTabBarTheme.itemSymbols {
            XCTAssertNotNil(UIImage(systemName: symbol.outline), symbol.outline)
            XCTAssertNotNil(UIImage(systemName: symbol.fill), symbol.fill)
        }
    }
}
