import SwiftUI

/// Light-theme liquid glass tokens. Dark keeps the existing GlassStyle recipe.
enum LightGlassPalette {
    static let atmosphereTop = ShellPalette.sky.atmosphere(for: .light).top.color
    static let atmosphereMid = ShellPalette.sky.atmosphere(for: .light).mid.color
    static let atmosphereBottom = ShellPalette.sky.atmosphere(for: .light).bottom.color

    static let panelFillOpacity = GlassContrast.panelFrostOpacity
    static let panelRimOpacity = 0.28
    static let panelSheenOpacity = GlassContrast.panelSheenOpacity
    static let chromeFillOpacity = GlassContrast.chromeFrostOpacity
    static let chromeRimOpacity = 0.26
    /// Native `glassEffect` rim — a whisper, not the Material white halo.
    static let nativeRimOpacity = 0.10
    static let nativeIncreasedContrastRimOpacity = 0.18
    static let fieldFillOpacity = GlassContrast.fieldTintOpacity
    /// Light input rim — a thin liquid-glass edge so wells read on the card. Dark draws none.
    static let fieldRimOpacity = 0.42
    static let fieldIncreasedContrastRimOpacity = 0.56
    static let formPanelFillOpacity = GlassContrast.fieldTintOpacity
    static let nativeGlassTintOpacity = GlassContrast.nativeGlassTintOpacity
    static let atmosphereVeilOpacity = GlassContrast.atmosphereVeilOpacity

    static let selectedChipFill = Color.white
    static let unselectedChipFill = Color.white.opacity(0.18)
    static let selectedChipText = Color.white
    static let badgeFill = Color.white.opacity(0.18)
    static let badgeText = Color.white

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(GlassContrast.textSecondaryOpacity)
    static let textTertiary = Color.white.opacity(GlassContrast.textTertiaryOpacity)
    static let textPlaceholder = Color.white.opacity(GlassContrast.textPlaceholderOpacity)
    static let textDisabled = Color.white.opacity(GlassContrast.textDisabledOpacity)

    /// Sky chrome — kept so existing Sky control tests stay pinned.
    static let controlTint = Color(red: 0.090, green: 0.294, blue: 0.561)
    static let nativeGlassTint = Color.white.opacity(0.08)

    static func nativeTint(for palette: ShellPalette, increasedContrast: Bool = false) -> Color {
        GlassContrast.nativeGlassTint(palette: palette).color.opacity(
            GlassContrast.adaptiveNativeTintOpacity(
                palette: palette,
                increasedContrast: increasedContrast
            )
        )
    }

    static func nativeRim(increasedContrast: Bool) -> Color {
        Color.white.opacity(
            increasedContrast ? nativeIncreasedContrastRimOpacity : nativeRimOpacity
        )
    }

    static let increasedContrastTintBoost = GlassContrast.increasedContrastTintBoost
    static let contrastDarken = 0.15

    static let recording = Color(red: 1.00, green: 0.420, blue: 0.420)
    static let paused = Color(red: 1.00, green: 0.702, blue: 0.361)
    static let success = Color(red: 0.482, green: 0.894, blue: 0.584)
    static let destructive = Color(red: 1.00, green: 0.478, blue: 0.478)

    static func darkened(_ color: Color) -> Color {
        color.opacity(1 - contrastDarken)
    }

    static func selectedChipFill(for palette: ShellPalette) -> Color {
        GlassContrast.selectedChipFill(palette: palette).color
    }
}

enum GlassText {
    static func primary(for scheme: ColorScheme, palette _: ShellPalette = .sky) -> Color {
        scheme == .dark ? Color.primary : LightGlassPalette.textPrimary
    }

    static func secondary(for scheme: ColorScheme, palette _: ShellPalette = .sky) -> Color {
        scheme == .dark ? Color.secondary : LightGlassPalette.textSecondary
    }

    static func tertiary(for scheme: ColorScheme, palette _: ShellPalette = .sky) -> Color {
        scheme == .dark ? Color.secondary.opacity(0.8) : LightGlassPalette.textTertiary
    }

    static func placeholder(for scheme: ColorScheme, palette _: ShellPalette = .sky) -> Color {
        scheme == .dark ? Color.secondary.opacity(0.7) : LightGlassPalette.textPlaceholder
    }

    static func disabled(for scheme: ColorScheme, palette _: ShellPalette = .sky) -> Color {
        scheme == .dark ? Color.primary.opacity(0.28) : LightGlassPalette.textDisabled
    }
}

enum GlassSemantic {
    static func recording(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.red : LightGlassPalette.recording
    }

    static func paused(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.orange : LightGlassPalette.paused
    }

    static func success(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.green : LightGlassPalette.success
    }

    static func destructive(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.red : LightGlassPalette.destructive
    }

    /// Unread count on the trips bell. Always iOS system red (`#FF3B30`); never follows Appearance or glass tint.
    static let notificationBadge = Color(red: 1.0, green: 0.231, blue: 0.188)
}

enum GlassControlTint {
    static func toggle(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.tintColor(for: scheme)
    }

    static func control(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.shellTint(for: scheme)
    }

    static func segmented(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.tintColor(for: scheme)
    }

    static func link(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.shellTint(for: scheme)
    }

    /// Compact DatePicker value on glass. Always white on Light; never system blue.
    static func datePickerCompact(for scheme: ColorScheme, palette _: ShellPalette = .sky) -> Color {
        GlassText.primary(for: scheme)
    }

    /// Calendar selected day. White disc, white number — never blue, never black ink.
    static let datePickerSelectedFill = Color.white
    static let datePickerSelectedTitle = Color.white

    /// Row disclosure chevron. Light uses palette chrome (dark ink on open glass);
    /// Dark keeps secondary so it does not compete with `.primary`.
    static func disclosure(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        scheme == .dark ? GlassText.secondary(for: .dark) : palette.chromeColor(for: .light)
    }
}

enum GlassHostBudget {
    /// Screen-local cap. Do not assert this globally — tab lifecycle, sheets, and
    /// off-screen lists would false-positive. Chips share one host via `GlassChipGroup`.
    static let maxNativeHostsPerScreen = 8
}
