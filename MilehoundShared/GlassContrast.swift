import SwiftUI

/// Light glass compositing. Cards stay in the atmosphere mid family — chrome is
/// not painted onto Light panels to chase a WCAG ratio. Device screenshots are
/// the visual source of truth; Increased Contrast raises tint, not white frost.
public enum GlassContrast {
    public static let white = ShellRGB(1, 1, 1)
    public static let bodyContrast: Double = 4.5
    public static let supportingContrast: Double = 3.0

    public static let panelFrostOpacity = 0.03
    public static let panelSheenOpacity = 0.03
    public static let chromeFrostOpacity = 0.03
    public static let atmosphereVeilOpacity = 0.06
    public static let atmosphereWhiteGlowOpacity = 0.22

    /// Light glass tint is mid mixed slightly toward bottom — not chrome.
    public static let glassTintBottomMix = 0.22
    public static let panelTintOpacity = 0.22
    public static let panelIncreasedContrastTintOpacity = 0.34
    public static let chromeDensityTintOpacity = 0.16
    public static let chromeIncreasedContrastTintOpacity = 0.26
    public static let nativeGlassTintOpacity = 0.50
    public static let nativeIncreasedContrastTintOpacity = 0.62
    /// Native `glassEffect` already supplies white frost — mix further toward
    /// atmosphere bottom so cards read as colored glass, not ice.
    public static let nativeTintBottomMix = 0.42
    /// Light floating tab bar — one step past the system white frost, still glass.
    public static let tabBarGlassTintOpacity = 0.28
    /// System `UITabBar` `UIGlassEffect.tintColor` — unused on Light (system default).
    public static let tabBarSystemGlassTintOpacity = 0.05
    /// Clear tab-bar glass: same hue as cards, more open than card native 0.50.
    public static let tabBarClearGlassTintOpacity = 0.22
    public static let fieldTintOpacity = 0.18
    public static let nestedTileTintOpacity = 0.16
    public static let recordingWashOpacity = 0.34
    public static let recordingFrostOpacity = 0.06
    public static let increasedContrastTintBoost = 0.12
    public static let solidBottomMix = 0.28
    public static let selectedChipBottomMix = 0.32

    public static let textPrimaryOpacity = 1.0
    public static let textSecondaryOpacity = 0.88
    public static let textTertiaryOpacity = 0.70
    public static let textPlaceholderOpacity = 0.64
    public static let textDisabledOpacity = 0.50

    public static func wcagRelativeLuminance(_ rgb: ShellRGB) -> Double {
        0.2126 * linearize(rgb.r) + 0.7152 * linearize(rgb.g) + 0.0722 * linearize(rgb.b)
    }

    public static func contrastRatio(_ a: ShellRGB, _ b: ShellRGB) -> Double {
        let lighter = max(wcagRelativeLuminance(a), wcagRelativeLuminance(b))
        let darker = min(wcagRelativeLuminance(a), wcagRelativeLuminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func overlay(_ source: ShellRGB, alpha: Double, on destination: ShellRGB) -> ShellRGB {
        let alpha = min(max(alpha, 0), 1)
        return ShellRGB(
            source.r * alpha + destination.r * (1 - alpha),
            source.g * alpha + destination.g * (1 - alpha),
            source.b * alpha + destination.b * (1 - alpha)
        )
    }

    public static func translucentForeground(_ source: ShellRGB, opacity: Double, on background: ShellRGB) -> ShellRGB {
        overlay(source, alpha: opacity, on: background)
    }

    public static func glassTint(palette: ShellPalette) -> ShellRGB {
        let atmosphere = palette.atmosphere(for: .light)
        return overlay(atmosphere.bottom, alpha: glassTintBottomMix, on: atmosphere.mid)
    }

    public static func materialTintOpacity(
        palette _: ShellPalette,
        increasedContrast: Bool
    ) -> Double {
        increasedContrast ? panelIncreasedContrastTintOpacity : panelTintOpacity
    }

    public static func adaptiveNativeTintOpacity(
        palette _: ShellPalette,
        increasedContrast: Bool
    ) -> Double {
        increasedContrast ? nativeIncreasedContrastTintOpacity : nativeGlassTintOpacity
    }

    public static func chromeTintOpacity(
        palette _: ShellPalette,
        increasedContrast: Bool
    ) -> Double {
        increasedContrast ? chromeIncreasedContrastTintOpacity : chromeDensityTintOpacity
    }

    public static func materialPanelFill(
        palette: ShellPalette,
        increasedContrast: Bool
    ) -> ShellRGB {
        let atmosphere = palette.atmosphere(for: .light)
        let veiled = overlay(white, alpha: atmosphereVeilOpacity, on: atmosphere.mid)
        var panel = overlay(
            glassTint(palette: palette),
            alpha: materialTintOpacity(palette: palette, increasedContrast: increasedContrast),
            on: veiled
        )
        panel = overlay(white, alpha: panelFrostOpacity, on: panel)
        return overlay(white, alpha: panelSheenOpacity * 0.5, on: panel)
    }

    public static func nativeGlassTint(palette: ShellPalette) -> ShellRGB {
        let atmosphere = palette.atmosphere(for: .light)
        return overlay(atmosphere.bottom, alpha: nativeTintBottomMix, on: atmosphere.mid)
    }

    public static func nativePanelFill(palette: ShellPalette, increasedContrast: Bool) -> ShellRGB {
        let atmosphere = palette.atmosphere(for: .light)
        let veiled = overlay(white, alpha: atmosphereVeilOpacity, on: atmosphere.mid)
        return overlay(
            nativeGlassTint(palette: palette),
            alpha: adaptiveNativeTintOpacity(palette: palette, increasedContrast: increasedContrast),
            on: veiled
        )
    }

    public static func solidPanelFill(palette: ShellPalette) -> ShellRGB {
        let atmosphere = palette.atmosphere(for: .light)
        return overlay(atmosphere.bottom, alpha: solidBottomMix, on: atmosphere.mid)
    }

    /// Opaque Light toolbar frost (map chrome). Same whisper as the tab bar —
    /// not the mid-family solid panel, which reads as a dark plate over a map.
    public static func toolbarLightFill(palette: ShellPalette) -> ShellRGB {
        overlay(
            glassTint(palette: palette),
            alpha: tabBarGlassTintOpacity,
            on: white
        )
    }

    public static func fieldFill(palette: ShellPalette) -> ShellRGB {
        overlay(
            glassTint(palette: palette),
            alpha: fieldTintOpacity,
            on: materialPanelFill(palette: palette, increasedContrast: false)
        )
    }

    public static func nestedTileFill(palette: ShellPalette) -> ShellRGB {
        overlay(
            glassTint(palette: palette),
            alpha: nestedTileTintOpacity,
            on: materialPanelFill(palette: palette, increasedContrast: false)
        )
    }

    public static func selectedChipFill(palette: ShellPalette) -> ShellRGB {
        let atmosphere = palette.atmosphere(for: .light)
        return overlay(atmosphere.bottom, alpha: selectedChipBottomMix, on: atmosphere.mid)
    }

    private static func linearize(_ channel: Double) -> Double {
        let channel = min(max(channel, 0), 1)
        if channel <= 0.04045 { return channel / 12.92 }
        return pow((channel + 0.055) / 1.055, 2.4)
    }
}

public extension ShellPalette {
    /// Light glass overlay: mid family, slightly deeper than the wallpaper. Never body text.
    func glassReadabilityTintRGB(for scheme: ColorScheme) -> ShellRGB {
        scheme == .dark ? atmosphere(for: .dark).tint : GlassContrast.glassTint(palette: self)
    }

    func glassReadabilityTint(for scheme: ColorScheme) -> Color {
        glassReadabilityTintRGB(for: scheme).color
    }

    func opaquePanelFillRGB(for scheme: ColorScheme) -> ShellRGB {
        scheme == .dark ? atmosphere(for: .dark).mid : GlassContrast.solidPanelFill(palette: self)
    }

    func opaquePanelFill(for scheme: ColorScheme) -> Color {
        opaquePanelFillRGB(for: scheme).color
    }
}
