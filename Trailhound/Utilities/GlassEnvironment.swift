import SwiftUI

private struct ShellPaletteKey: EnvironmentKey {
    static let defaultValue: ShellPalette = .sky
}

private struct GlassForcesSolidPlateKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var shellPalette: ShellPalette {
        get { self[ShellPaletteKey.self] }
        set { self[ShellPaletteKey.self] = newValue }
    }

    /// Snapshot and raster hosts set this so cards use the solid plate instead of
    /// native Liquid Glass or Material. Those shaders do not match across simulator runtimes.
    var glassForcesSolidPlate: Bool {
        get { self[GlassForcesSolidPlateKey.self] }
        set { self[GlassForcesSolidPlateKey.self] = newValue }
    }
}

private struct OnGlassShellModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        // One chain in Light and Dark. An if/else here rebuilds the tab stack on a theme
        // change and pops Settings back to the top.
        let tint = colorScheme == .light && !GlassEngineResolver.lightAvoidsWhiteChromeTint
            ? shellPalette.shellTint(for: .light)
            : nil
        content
            .foregroundStyle(shellPalette.shellForeground(for: colorScheme))
            .tint(tint)
    }
}

extension View {
    /// Light glass shell: white type on the atmosphere. iOS 26 does not apply
    /// white `.tint` — that fills toolbar/tab liquid with a second white plate.
    /// Dark uses the primary label color. The modifier chain does not branch,
    /// so a theme change keeps the open Settings page.
    func onGlassShell() -> some View {
        modifier(OnGlassShellModifier())
    }

    /// Palette accent in dark; white (or chrome tint) on the light glass shell.
    func glassAccentForeground() -> some View {
        modifier(GlassAccentForegroundModifier())
    }

    func glassPrimaryInk() -> some View {
        modifier(GlassPrimaryInkModifier())
    }

    func glassSecondaryInk() -> some View {
        modifier(GlassSecondaryInkModifier())
    }

    func glassTertiaryInk() -> some View {
        modifier(GlassTertiaryInkModifier())
    }

    /// Palette chrome on Light glass; secondary in Dark. Use for row `>` chevrons.
    func glassDisclosureInk() -> some View {
        modifier(GlassDisclosureInkModifier())
    }

    /// Drops the system NavigationLink `>` so a `GlassDisclosureChevron` can own the color.
    func glassHidesNavigationLinkIndicator() -> some View {
        modifier(GlassHidesNavigationLinkIndicator())
    }
}

private struct GlassPrimaryInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassText.primary(for: colorScheme))
    }
}

private struct GlassSecondaryInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassText.secondary(for: colorScheme))
    }
}

private struct GlassTertiaryInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassText.tertiary(for: colorScheme))
    }
}

private struct GlassDisclosureInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassControlTint.disclosure(for: colorScheme, palette: shellPalette))
    }
}

private struct GlassHidesNavigationLinkIndicator: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationLinkIndicatorVisibility(.hidden)
        } else {
            content
        }
    }
}

private struct GlassAccentForegroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassControlTint.link(for: colorScheme, palette: shellPalette))
    }
}
