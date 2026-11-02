import SwiftUI
import UIKit

enum GlassTokens {
    static let cardRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14
    /// Bottom confirmation toast. Same corner family as a glass card, larger than a chip.
    static let toastCornerRadius: CGFloat = cardRadius
    static let toastIconDiscSide: CGFloat = 38
    static let toastMinHeight: CGFloat = 56
    static let toastMaxWidth: CGFloat = 360
    static let toastHorizontalPadding: CGFloat = 16
    static let toastVerticalPadding: CGFloat = 12
    /// Gap between a bottom toast and the top of the tab platter.
    static let toastTabBarGap: CGFloat = 12
    /// Used until the tab platter frame is published.
    static let toastTabBarFallbackClearance: CGFloat = 68
    static let sectionSpacing: CGFloat = 14
    /// `glassCompactRow` vertical padding and minimum height. Six Settings sections fit a landscape phone pane.
    static let compactRowVerticalInset: CGFloat = 7
    static let compactRowMinHeight: CGFloat = 34
    static let compactIndexTopMargin: CGFloat = 8
    /// Distance from screen edge to the glass card rim.
    static let panelHorizontalInset: CGFloat = 16
    /// Padding between the glass card rim and its content (both sides).
    static let cardContentInset: CGFloat = 12
    /// List row content inset from the screen edge (`panel` + inner content padding).
    static var listContentHorizontalInset: CGFloat { panelHorizontalInset + cardContentInset }

    /// Extra side inset for the recording card pinned in the top half of the upright open fold.
    /// The card already pads by `panelHorizontalInset`. Below about 420pt the trip plate is one
    /// more panel inset in; the inner Duo is wider and its list margin is 20pt.
    static func recordingFoldExtraInset(contentWidth: CGFloat) -> CGFloat {
        contentWidth >= 420 ? 20 : panelHorizontalInset
    }

    /// Nested frost tiles inside a glass card (wizard choices, instruction rows).
    static let nestedChoiceRadius: CGFloat = 12
    /// Tinted glyph disc on a featured list row (Settings → Support the developer).
    static let featuredRowDiscSide: CGFloat = 32
    /// Camera-style option circle. The circle is the glass; the caption sits under it.
    static let optionCircleSide: CGFloat = 64
    /// Space between an option circle and the caption under it.
    static let optionCaptionSpacing: CGFloat = 8
    /// Camera-style bottom glass panel (`GlassMorphPanel`): gap to the screen edges.
    static let morphPanelEdgeInset: CGFloat = 8
    /// Concentric with the display corner once inset by `morphPanelEdgeInset`.
    static let morphPanelCornerRadius: CGFloat = 44
    /// Display corner the morph panel matches. A control inset further subtracts its own margin.
    static var displayCornerRadius: CGFloat { morphPanelCornerRadius + morphPanelEdgeInset }

    /// Corner radius that stays concentric with the display when the view is `edgeInset` from the screen.
    static func concentricCornerRadius(edgeInset: CGFloat) -> CGFloat {
        max(0, displayCornerRadius - edgeInset)
    }

    /// Travel detail on the closed landscape cover. Compact stays within a third of the screen.
    enum TravelCornerCardMetrics {
        static let compactMaxWidth: CGFloat = 300
        static let compactMinWidth: CGFloat = 220
        /// The cover card is 1.25 × 1.15 of the third-of-screen base.
        static let compactWidthScale: CGFloat = 1.4375
        /// Gap between the card and the side tab. Tighter than `panelHorizontalInset`.
        static let tabGap: CGFloat = 4
        static let expandedWidthFraction: CGFloat = 0.42
        static let expandedMaxWidth: CGFloat = 360
        /// Grown card stays in the lower portion. The map above it keeps the rest.
        static let expandedMaxHeightFraction: CGFloat = 0.55

        /// A third of the screen, capped at `compactMaxWidth` (the 220 pt floor applies only when a
        /// third is already that wide), then scaled by `compactWidthScale`.
        static func compactWidth(screenWidth: CGFloat) -> CGFloat {
            let third = screenWidth / 3
            let base = third >= compactMinWidth ? min(third, compactMaxWidth) : max(0, third)
            return base * compactWidthScale
        }

        static func expandedWidth(screenWidth: CGFloat) -> CGFloat {
            min(max(0, screenWidth) * expandedWidthFraction, expandedMaxWidth)
        }

        static func expandedHeight(screenHeight: CGFloat) -> CGFloat {
            max(0, screenHeight) * expandedMaxHeightFraction
        }
    }
    /// Panel scale when it starts to grow, and when it finishes shrinking.
    static let morphPanelOpenScale: CGFloat = 0.4
    static let morphPanelCloseScale: CGFloat = 0.55
    /// Content blur at the start of the grow and the end of the shrink.
    static let morphPanelBlur: CGFloat = 14
    /// Drag past this (or flick past twice this) to close.
    static let morphPanelDismissDistance: CGFloat = 90
    /// Inactive horizontal page scale while a carousel is mid-swipe.
    static let carouselPageRestScale: CGFloat = 0.96
    static let carouselPageRestOpacity: CGFloat = 0.62

    /// Compact frozen circle on a live map (Stats overlay collapse).
    static let toolbarFrozenCircleSide: CGFloat = 36
    /// Overlay toolbar circle (Year recap story Share/Close).
    /// Matches camera overlay hit size (`GlassToolbarControlBackground` 44pt).
    static let toolbarControlCircleSide: CGFloat = 44
    /// Gap between independent 44pt toolbar circles (Trip detail Share/collapse, Year recap).
    static let toolbarCircleClusterSpacing: CGFloat = 16
    /// Gap between side-column circles, and between that stack and the tab bar platter.
    static let sideColumnChromeGap: CGFloat = 16
    /// Gap between glyphs that share one system platter (Trips merge+bell).
    static let toolbarSharedClusterSpacing: CGFloat = 8
    /// Width of a glyph inside a shared platter. Height stays `toolbarControlCircleSide`.
    static let toolbarClusterGlyphWidth: CGFloat = 32

    /// Wide-layout tokens. Phone portrait does not read these.
    static let railWidthFraction: CGFloat = 0.36
    static let hingeGutter: CGFloat = 24
    static let padLandscapeGap: CGFloat = 48
    static let floatingPanelWidth: CGFloat = 380
    static let paneCardMaxWidth: CGFloat = 440
    static let paneVerticalRhythm: CGFloat = 22
    static let moduleMinHalf: CGFloat = 160
    static let moduleMaxHalf: CGFloat = 300
    static let featureHeight: CGFloat = 320
    static let readableTextWidth: CGFloat = 440
    static let heroFigureFont = Font.system(size: 44, weight: .light, design: .rounded)
    /// Narrow iPad Split View / Slide Over stays the phone column.
    static let compactWidthCeiling: CGFloat = 520

    static func fieldFill(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.10)
        }
        return palette.glassReadabilityTint(for: .light).opacity(LightGlassPalette.fieldFillOpacity)
    }

    static let fieldRimWidth: CGFloat = 1

    /// Light-only input stroke. Dark returns clear so wells stay unoutlined.
    static func fieldRim(for scheme: ColorScheme, increasedContrast: Bool = false) -> Color {
        guard scheme == .light else { return .clear }
        return Color.white.opacity(
            increasedContrast
                ? LightGlassPalette.fieldIncreasedContrastRimOpacity
                : LightGlassPalette.fieldRimOpacity
        )
    }

    /// Frosted panel look without `Material` (keyboard-friendly forms).
    static func formPanelFill(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.12)
        }
        return palette.glassReadabilityTint(for: .light).opacity(LightGlassPalette.formPanelFillOpacity)
    }

    static func solidFallback(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        if scheme == .dark {
            return Color(.secondarySystemGroupedBackground)
        }
        return palette.opaquePanelFill(for: .light)
    }

    /// Frozen nav chrome over a map: Light is a near-white palette frost, Dark
    /// keeps the grouped solid. Never `Material` — MapKit must not be sampled.
    static func toolbarFrozenFill(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        if scheme == .dark {
            return solidFallback(for: .dark, palette: palette)
        }
        return GlassContrast.toolbarLightFill(palette: palette).color
    }

    static func toolbarFrozenRim(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.28)
        }
        return Color.white.opacity(0.72)
    }

    /// Palette tint for the live-map HUD Liquid Glass. Light enough that HUD ink keeps its contrast over the road.
    static func liveMapGlassTint(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        palette.tintColor(for: scheme).opacity(scheme == .dark ? 0.22 : 0.14)
    }
}

enum GlassDensity {
    case panel
    case chrome

    func material(for scheme: ColorScheme) -> Material {
        .ultraThinMaterial
    }

    func frostOpacity(for scheme: ColorScheme) -> Double {
        switch self {
        case .panel:
            scheme == .dark ? 0.06 : LightGlassPalette.panelFillOpacity
        case .chrome:
            scheme == .dark ? 0.04 : LightGlassPalette.chromeFillOpacity
        }
    }

    func brandTintOpacity(for scheme: ColorScheme, palette: ShellPalette = .sky, increasedContrast: Bool = false) -> Double {
        switch self {
        case .panel:
            scheme == .dark
                ? 0.20
                : GlassContrast.materialTintOpacity(palette: palette, increasedContrast: increasedContrast)
        case .chrome:
            scheme == .dark
                ? 0.14
                : GlassContrast.chromeTintOpacity(palette: palette, increasedContrast: increasedContrast)
        }
    }

    func rimOpacity(for scheme: ColorScheme) -> Double {
        guard scheme == .light else { return 0 }
        switch self {
        case .panel: return LightGlassPalette.panelRimOpacity
        case .chrome: return LightGlassPalette.chromeRimOpacity
        }
    }
}

enum GlassRowPosition {
    case only
    case first
    case middle
    case last

    static func index(_ index: Int, in count: Int) -> GlassRowPosition {
        guard count > 1 else { return .only }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    var topRadius: CGFloat {
        switch self {
        case .only, .first: GlassTokens.cardRadius
        case .middle, .last: 0
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .only, .last: GlassTokens.cardRadius
        case .first, .middle: 0
        }
    }

    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
    }
}

/// Soft color wash behind frosted panels — visible through glass, not a flat blue screen.
struct AtmosphericBackground: View {
    enum Style {
        case full
        case lightweight
        /// System canvas + soft brand glows — for onboarding / surfaces that should follow light/dark, not the blue shell.
        case canvas
    }

    var style: Style = .full

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Group {
            if style == .canvas && colorScheme == .dark {
                Color(.systemBackground)
            } else {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        // Overlay, not a ZStack sibling: the glows are wider than the screen and as siblings
        // they would stretch every container that puts this behind its content.
        .overlay {
            if style == .full || style == .canvas {
                let glowScale = style == .canvas ? 0.45 : 1.0
                ZStack {
                    if colorScheme == .dark {
                        glow(
                            shellPalette.glowColor(for: .dark).opacity(0.38 * glowScale),
                            diameter: 520,
                            offset: CGSize(width: -120, height: -220)
                        )
                        glow(
                            shellPalette.tintColor(for: .dark).opacity(0.32 * glowScale),
                            diameter: 580,
                            offset: CGSize(width: 140, height: 280)
                        )
                        if style == .full {
                            glow(
                                Color(red: 0.95, green: 0.78, blue: 0.92).opacity(0.10),
                                diameter: 380,
                                offset: CGSize(width: 60, height: 40)
                            )
                        }
                    } else {
                        glow(
                            Color.white.opacity(GlassContrast.atmosphereWhiteGlowOpacity * glowScale),
                            diameter: 460,
                            offset: CGSize(width: 88, height: -250)
                        )
                        glow(
                            shellPalette.atmosphere(for: .light).top.color.opacity(0.50 * glowScale),
                            diameter: 520,
                            offset: CGSize(width: 70, height: -200)
                        )
                        glow(
                            shellPalette.atmosphere(for: .light).bottom.color.opacity(0.30 * glowScale),
                            diameter: 560,
                            offset: CGSize(width: -130, height: 300)
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        // Cheap frost: a white veil, not `.blur`. Live blur under glass cards gets
        // resampled by every Material above it (see docs/PERFORMANCE.md).
        .overlay {
            if colorScheme != .dark {
                Color.white.opacity(
                    style == .full
                        ? LightGlassPalette.atmosphereVeilOpacity
                        : LightGlassPalette.atmosphereVeilOpacity * 0.6
                )
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        shellPalette.gradientColors(for: colorScheme)
    }

    /// A soft radial falloff instead of `Circle().blur(...)`. These sit underneath every
    /// frosted row, so each blur pass was being resampled by every material above it.
    private func glow(_ color: Color, diameter: CGFloat, offset: CGSize) -> some View {
        RadialGradient(
            stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(0.55), location: 0.42),
                .init(color: color.opacity(0.16), location: 0.72),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
        .offset(x: offset.width, y: offset.height)
    }
}

struct GlassSurface: View {
    var cornerRadius: CGFloat = GlassTokens.cardRadius
    var topRadius: CGFloat?
    var bottomRadius: CGFloat?
    var density: GlassDensity = .panel
    /// Skip Material blur — used while a sheet/panel is being dragged over a live map.
    var frozen: Bool = false
    /// List rows must not host native Liquid Glass (separate cell hosts).
    var allowsNative: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    private var engine: GlassEngine {
        GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
            allowsNative: allowsNative
        )
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius ?? cornerRadius,
            bottomLeadingRadius: bottomRadius ?? cornerRadius,
            bottomTrailingRadius: bottomRadius ?? cornerRadius,
            topTrailingRadius: topRadius ?? cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                darkLegacySurface
            } else {
                lightSurface
            }
        }
    }

    @ViewBuilder
    private var darkLegacySurface: some View {
        if reduceTransparency || frozen {
            shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
            if frozen, !reduceTransparency {
                shape.fill(
                    shellPalette.tintColor(for: colorScheme).opacity(
                        density.brandTintOpacity(for: colorScheme, palette: shellPalette) * 0.85
                    )
                )
                shape.fill(Color.white.opacity(density.frostOpacity(for: colorScheme) * 0.9))
            }
        } else {
            shape.fill(density.material(for: colorScheme))
            shape.fill(
                shellPalette.tintColor(for: colorScheme).opacity(
                    density.brandTintOpacity(for: colorScheme, palette: shellPalette)
                )
            )
            shape.fill(Color.white.opacity(density.frostOpacity(for: colorScheme)))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(density.frostOpacity(for: colorScheme) * 1.1),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        }
    }

    @ViewBuilder
    private var lightSurface: some View {
        let increased = contrast == .increased
        let frost = density.frostOpacity(for: .light)
        let tintOpacity = density.brandTintOpacity(
            for: .light,
            palette: shellPalette,
            increasedContrast: increased
        )
        let rim = density.rimOpacity(for: .light) + (increased ? 0.10 : 0)
        switch engine {
        case .native:
            shape.fill(Color.clear)
            shape.strokeBorder(LightGlassPalette.nativeRim(increasedContrast: increased), lineWidth: 1)
        case .solid:
            shape.fill(GlassTokens.solidFallback(for: .light, palette: shellPalette))
            shape.strokeBorder(Color.white.opacity(rim), lineWidth: 1)
        case .material:
            shape.fill(density.material(for: .light))
            shape.fill(shellPalette.glassReadabilityTint(for: .light).opacity(tintOpacity))
            shape.fill(Color.white.opacity(frost))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(LightGlassPalette.panelSheenOpacity),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.strokeBorder(Color.white.opacity(rim), lineWidth: 1)
        }
    }
}

struct GlassSectionRowBackground: View {
    let position: GlassRowPosition

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        plate
            .padding(.horizontal, GlassTokens.panelHorizontalInset)
    }

    @ViewBuilder
    private var plate: some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            allowsNative: true
        )
        let shape = position.shape
        if #available(iOS 26.0, *), engine == .native {
            Color.clear
                .modifier(
                    NativeGlassBackgroundModifier(
                        shape: shape,
                        palette: shellPalette,
                        increasedContrast: contrast == .increased
                    )
                )
        } else {
            GlassSurface(
                topRadius: position.topRadius,
                bottomRadius: position.bottomRadius,
                density: .panel,
                allowsNative: false
            )
        }
    }
}

/// Solid grouped rows for keyboard-heavy forms (no per-row material blur).
struct FormSolidSectionRowBackground: View {
    let position: GlassRowPosition

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: position.topRadius,
            bottomLeadingRadius: position.bottomRadius,
            bottomTrailingRadius: position.bottomRadius,
            topTrailingRadius: position.topRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
            if !reduceTransparency, colorScheme == .dark {
                shape.fill(shellPalette.tintColor(for: .dark).opacity(0.10))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        }
        .padding(.horizontal, GlassTokens.panelHorizontalInset)
    }
}

/// Native Liquid Glass with the mid-family tint plate. The plate is clipped
/// to the card; content is not, so labels in the corners stay whole.
private struct NativeGlassBackgroundModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var palette: ShellPalette
    var increasedContrast: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(Color.clear)
                        .glassEffect(
                            .regular.tint(
                                LightGlassPalette.nativeTint(
                                    for: palette,
                                    increasedContrast: increasedContrast
                                )
                            ),
                            in: shape
                        )
                        .clipShape(shape)
                        .mask(shape)
                }
                .overlay {
                    shape.strokeBorder(
                        LightGlassPalette.nativeRim(increasedContrast: increasedContrast),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}

/// Floating tab bar: Light is one Capsule `.clear` native glass; Dark keeps the
/// thin Material platter. Native `.regular` in Dark reads as a heavy black plate
/// over the atmosphere, so the tab bar is not a `glassCircleChrome` exception.
private struct GlassTabBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            allowsNative: true
        )
        let shape = Capsule(style: .continuous)
        if #available(iOS 26.0, *), engine == .native {
            content
                .background {
                    shape
                        .fill(Color.clear)
                        .glassEffect(
                            .clear.tint(
                                GlassContrast.nativeGlassTint(palette: shellPalette).color.opacity(
                                    GlassContrast.tabBarClearGlassTintOpacity
                                )
                            )
                            .interactive(),
                            in: shape
                        )
                        .clipShape(shape)
                        .mask(shape)
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LightGlassPalette.nativeRim(increasedContrast: contrast == .increased),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
        } else if engine == .solid {
            content.background(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassTokens.cardRadius
    var density: GlassDensity = .panel
    var contentInset: CGFloat = GlassTokens.cardContentInset
    var frozen: Bool = false
    var allowsNative: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.glassForcesSolidPlate) private var glassForcesSolidPlate

    func body(content: Content) -> some View {
        let plateFrozen = frozen || glassForcesSolidPlate
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: plateFrozen,
            allowsNative: allowsNative
        )
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let padded = content
            .padding(.horizontal, contentInset)
            .padding(.vertical, contentInset)

        if #available(iOS 26.0, *), engine == .native {
            padded.modifier(
                NativeGlassBackgroundModifier(
                    shape: shape,
                    palette: shellPalette,
                    increasedContrast: contrast == .increased
                )
            )
        } else {
            padded
                .background {
                    GlassSurface(
                        cornerRadius: cornerRadius,
                        density: density,
                        frozen: plateFrozen,
                        allowsNative: allowsNative
                    )
                }
        }
    }
}

/// One Liquid Glass card anchored in a screen corner. The corner that meets the display
/// uses a radius concentric with that display; the other three use `cardRadius`.
struct GlassCornerCard<Content: View>: View {
    /// Bottom-trailing in left-to-right. Bottom-leading when false.
    var anchorsTrailing: Bool = true
    var contentInset: CGFloat = GlassTokens.cardContentInset
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.glassForcesSolidPlate) private var glassForcesSolidPlate

    private var outerRadius: CGFloat {
        GlassTokens.concentricCornerRadius(edgeInset: GlassTokens.panelHorizontalInset)
    }

    private var shape: UnevenRoundedRectangle {
        let inner = GlassTokens.cardRadius
        let outer = outerRadius
        if anchorsTrailing {
            return UnevenRoundedRectangle(
                topLeadingRadius: inner,
                bottomLeadingRadius: inner,
                bottomTrailingRadius: outer,
                topTrailingRadius: inner,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: inner,
            bottomLeadingRadius: outer,
            bottomTrailingRadius: inner,
            topTrailingRadius: inner,
            style: .continuous
        )
    }

    var body: some View {
        let plateFrozen = glassForcesSolidPlate
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: plateFrozen,
            allowsNative: true
        )
        let padded = content()
            .padding(.horizontal, contentInset)
            .padding(.vertical, contentInset)

        if #available(iOS 26.0, *), engine == .native {
            padded.modifier(
                NativeGlassBackgroundModifier(
                    shape: shape,
                    palette: shellPalette,
                    increasedContrast: contrast == .increased
                )
            )
        } else {
            padded
                .background {
                    GlassSurface(
                        cornerRadius: outerRadius,
                        density: .panel,
                        frozen: plateFrozen
                    )
                }
                .clipShape(shape)
        }
    }
}

struct GlassChromeModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassTokens.chipRadius
    var frozen: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.glassForcesSolidPlate) private var glassForcesSolidPlate

    func body(content: Content) -> some View {
        let plateFrozen = frozen || glassForcesSolidPlate
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: plateFrozen,
            allowsNative: true
        )
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *), engine == .native {
            content.modifier(
                NativeGlassBackgroundModifier(
                    shape: shape,
                    palette: shellPalette,
                    increasedContrast: contrast == .increased
                )
            )
        } else {
            content
                .background {
                    GlassSurface(cornerRadius: cornerRadius, density: .chrome, frozen: plateFrozen)
                }
                .clipShape(shape)
        }
    }
}

/// 44pt Liquid Glass circle for overlay toolbar glyphs (Stats expand collapse).
struct GlassCircleChromeModifier: ViewModifier {
    var side: CGFloat = GlassTokens.toolbarControlCircleSide
    var frozen: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shaped = content
            .frame(width: side, height: side)
            .contentShape(Circle())
        // Same circle as the system toolbar item (Trip/Travel back): native
        // Liquid Glass in Light *and* Dark. Do not use GlassEngineResolver here —
        // Dark would pick Material and paint an opaque plate over the map.
        if reduceTransparency || frozen {
            shaped
                .background {
                    GlassToolbarControlBackground(shape: Circle(), frozen: true)
                }
        } else if #available(iOS 26.0, *) {
            shaped
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            shaped
                .background {
                    GlassToolbarControlBackground(shape: Circle(), frozen: false)
                }
        }
    }
}

/// Vertical Liquid Glass capsule. Same rule as `GlassCircleChromeModifier`:
/// native glass in Light and Dark. The caller sizes the content (44pt hits).
/// The glass sits behind the glyphs so a badge is not clipped by the capsule.
struct GlassCapsuleChromeModifier: ViewModifier {
    var frozen: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = Capsule()
        if reduceTransparency || frozen {
            content.background {
                GlassToolbarControlBackground(shape: shape, frozen: true)
            }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background {
                GlassToolbarControlBackground(shape: shape, frozen: false)
            }
        }
    }
}

struct GlassFieldModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GlassTokens.fieldFill(for: colorScheme, palette: shellPalette))
            }
    }
}

/// Thin white liquid-glass rim on Light input wells. Dark draws nothing.
struct GlassFieldLightRimModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if colorScheme == .light {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        GlassTokens.fieldRim(
                            for: .light,
                            increasedContrast: contrast == .increased
                        ),
                        lineWidth: GlassTokens.fieldRimWidth
                    )
                    .allowsHitTesting(false)
            }
        }
    }
}

struct GlassInputWellModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .glassField(cornerRadius: cornerRadius)
            .modifier(GlassFieldLightRimModifier(cornerRadius: cornerRadius))
    }
}

struct GlassInputFieldModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassInputWell(cornerRadius: cornerRadius)
    }
}

/// Backwards-compatible alias for section panels.
struct GlassListRowBackground: View {
    var cornerRadius: CGFloat = GlassTokens.cardRadius
    var verticalInset: CGFloat = 5

    var body: some View {
        GlassSectionRowBackground(position: .only)
            .padding(.vertical, verticalInset)
    }
}

/// Filter chip — Light selected = palette chrome + white type; unselected = frost + white.
struct GlassFilterChip: View {
    enum Size {
        case regular
        /// Slightly tighter padding/type for stacked trip-list filter rows.
        case compact

        var font: Font { self == .compact ? .caption2 : .caption }
        var horizontalPadding: CGFloat { self == .compact ? 10 : 12 }
        var verticalPadding: CGFloat { self == .compact ? 5 : 7 }
        var avatarSize: CGFloat { self == .compact ? 12 : 16 }
    }

    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    var highlightID: String = "glassFilterChipHighlight"
    var expands: Bool = false
    var size: Size = .regular
    /// Optional vehicle identity mark (photo thumb or SF Symbol).
    var avatarSystemImage: String? = nil
    var avatarPhotoFileName: String? = nil
    var avatarIsElectric: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    private var usesNativeChip: Bool {
        isSelected
            && GlassEngineResolver.resolve(
                scheme: colorScheme,
                reduceTransparency: reduceTransparency,
                frozen: false,
                allowsNative: true
            ) == .native
    }

    private var labelColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white : Color.primary
        }
        return Color.white
    }

    private var selectionFill: Color {
        colorScheme == .dark
            ? shellPalette.tintColor(for: .dark)
            : LightGlassPalette.selectedChipFill(for: shellPalette)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let avatarSystemImage {
                    VehicleAvatarView(
                        systemImage: avatarSystemImage,
                        photoFileName: avatarPhotoFileName,
                        size: size.avatarSize,
                        cornerRadius: size.avatarSize * 0.28,
                        isElectricAccent: avatarIsElectric,
                        symbolColor: labelColor,
                        showsSymbolPlate: false,
                        symbolFitsFrame: true
                    )
                }
                Text(title)
                    .font(size.font.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: expands ? .infinity : nil)
            .foregroundStyle(labelColor)
            .background {
                if usesNativeChip {
                    Color.clear
                } else {
                    chipBackground
                }
            }
            .modifier(NativeFilterChipGlass(isSelected: isSelected, highlightID: highlightID, namespace: namespace))
            .contentShape(Capsule())
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(selectionFill)
                .matchedGeometryEffect(id: highlightID, in: namespace)
        } else {
            Capsule()
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.white.opacity(0.22)
                )
                .overlay {
                    if colorScheme == .light {
                        Capsule().fill(shellPalette.tintColor(for: .light).opacity(0.14))
                    }
                }
        }
    }
}

private struct NativeFilterChipGlass: ViewModifier {
    let isSelected: Bool
    let highlightID: String
    let namespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            allowsNative: true
        )
        // Unselected chips stay frost fills so a horizontal scroller can clip
        // them at the card edge. Native glass on every chip unions off-screen
        // pills and paints past the trailing corner.
        if #available(iOS 26.0, *), engine == .native, isSelected {
            content
                .glassEffect(
                    .regular.tint(selectedTint).interactive(),
                    in: Capsule()
                )
                .glassEffectID(highlightID, in: namespace)
        } else {
            content
        }
    }

    private var selectedTint: Color {
        colorScheme == .dark
            ? shellPalette.tintColor(for: .dark)
            : LightGlassPalette.selectedChipFill(for: shellPalette)
    }
}

/// Shared material/tint/rim treatment for custom toolbar and overlay controls.
/// Never uses native `glassEffect` — live maps and camera previews must not
/// resample Liquid Glass every frame (`allowsNative` stays off).
struct GlassToolbarControlBackground<ControlShape: InsettableShape>: View {
    let shape: ControlShape
    var frozen: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let useSolid = reduceTransparency || frozen
        ZStack {
            if useSolid {
                shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
                if colorScheme == .dark {
                    shape.fill(shellPalette.tintColor(for: .dark).opacity(0.22))
                }
            } else {
                shape.fill(.ultraThinMaterial)
                if colorScheme == .dark {
                    shape.fill(shellPalette.tintColor(for: .dark).opacity(0.22))
                } else {
                    shape.fill(
                        shellPalette.glassReadabilityTint(for: .light).opacity(
                            GlassContrast.chromeTintOpacity(palette: shellPalette, increasedContrast: false)
                        )
                    )
                }
            }
            shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
    }
}

/// Frozen map-toolbar plate. Light stays a pale frost so palette glyphs read;
/// overlay chrome (`GlassToolbarControlBackground`) is unchanged.
struct GlassToolbarFrozenPlate<ControlShape: InsettableShape>: View {
    let shape: ControlShape

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        ZStack {
            shape.fill(GlassTokens.toolbarFrozenFill(for: colorScheme, palette: shellPalette))
            shape.strokeBorder(
                GlassTokens.toolbarFrozenRim(for: colorScheme, palette: shellPalette),
                lineWidth: 1
            )
        }
    }
}

/// Localized Save / Cancel label. Defaults to the system toolbar platter.
struct GlassToolbarSaveButton: View {
    let title: String
    var sampling: GlassToolbarSampling = .system

    var body: some View {
        GlassToolbarTitle(title: title, sampling: sampling)
    }
}

/// Back chevron. The action is on the whole 44pt Liquid Glass circle, not the glyph.
struct GlassToolbarBackButton: View {
    var sampling: GlassToolbarSampling = .system
    var action: () -> Void

    @ViewBuilder
    var body: some View {
        if sampling == .system {
            GlassToolbarCircleButton(systemName: "chevron.backward", action: action)
                .accessibilityLabel(Text("onboarding.back"))
        } else {
            Button(action: action) {
                GlassToolbarSymbol(systemName: "chevron.backward", sampling: sampling)
            }
            .buttonStyle(.glassPlainHit)
            .contentShape(Circle())
            .accessibilityLabel(Text("onboarding.back"))
        }
    }
}

/// Empty list state that matches the glass shell instead of the system white card.
struct GlassEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    var bounceTrigger: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(GlassText.primary(for: colorScheme).opacity(0.85))
                .symbolEffect(.bounce, value: reduceMotion ? false : bounceTrigger)

            Text(title)
                .font(.headline)
                .foregroundStyle(GlassText.primary(for: colorScheme))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Persistent caption above an input so glass rows read as editable fields, not static text.
struct GlassFieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlassText.secondary(for: colorScheme))
            content()
                .glassInputField()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlassSegmentedStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .pickerStyle(.segmented)
            .tint(GlassControlTint.segmented(for: colorScheme, palette: shellPalette))
            .background {
                GlassSegmentedUIKitBridge(
                    tint: TrailhoundTabBarTheme.selectedUIColor(palette: shellPalette, scheme: colorScheme),
                    selectedFill: selectedFill,
                    selectedTitle: selectedTitle,
                    normalTitle: unselectedTitle
                )
            }
    }

    private var selectedFill: UIColor {
        if colorScheme == .dark {
            return TrailhoundTabBarTheme.selectedUIColor(palette: shellPalette, scheme: .dark)
        }
        return TrailhoundTabBarTheme.uiColor(GlassContrast.selectedChipFill(palette: shellPalette))
    }

    private var selectedTitle: UIColor {
        .white
    }

    /// Glass segmented labels stay white; tab-bar unselected ink is a separate system capsule.
    private var unselectedTitle: UIColor {
        if colorScheme == .dark {
            return UIColor.secondaryLabel
        }
        return UIColor.white.withAlphaComponent(CGFloat(GlassContrast.textSecondaryOpacity))
    }
}

/// Paints the system segmented control with the shell palette. SwiftUI `.tint` is ignored on iOS 26.
private struct GlassSegmentedUIKitBridge: UIViewRepresentable {
    var tint: UIColor
    var selectedFill: UIColor
    var selectedTitle: UIColor
    var normalTitle: UIColor

    func makeUIView(context: Context) -> GlassSegmentedProbeView {
        let view = GlassSegmentedProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: GlassSegmentedProbeView, context: Context) {
        uiView.paletteTint = tint
        uiView.selectedFill = selectedFill
        uiView.selectedTitle = selectedTitle
        uiView.normalTitle = normalTitle
        uiView.applySoon()
    }
}

final class GlassSegmentedProbeView: UIView {
    var paletteTint: UIColor = .systemBlue
    var selectedFill: UIColor = .white
    var selectedTitle: UIColor = .label
    var normalTitle: UIColor = .secondaryLabel

    func applySoon() {
        apply()
        DispatchQueue.main.async { [weak self] in
            self?.apply()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySoon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    func apply() {
        guard let control = findSegmentedControl() else { return }
        control.selectedSegmentTintColor = selectedFill
        control.tintColor = paletteTint
        control.setTitleTextAttributes([.foregroundColor: normalTitle], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: selectedTitle], for: .selected)
    }

    private func findSegmentedControl() -> UISegmentedControl? {
        var ancestor: UIView? = superview
        for _ in 0..<8 {
            guard let current = ancestor else { return nil }
            if let found = search(current) { return found }
            ancestor = current.superview
        }
        return nil
    }

    private func search(_ root: UIView) -> UISegmentedControl? {
        if let control = root as? UISegmentedControl { return control }
        for child in root.subviews {
            if let found = search(child) { return found }
        }
        return nil
    }
}

/// Frost fill inside a glass card. Light selection is a rim, not a second tint slab.
private struct GlassNestedChoiceModifier: ViewModifier {
    var isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: GlassTokens.nestedChoiceRadius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        if showsSelectionRim {
                            RoundedRectangle(cornerRadius: GlassTokens.nestedChoiceRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                        }
                    }
            }
    }

    /// Light shells are already a saturated wash. A mid-family fill there is the
    /// same hue as the atmosphere and the primary capsule, so the row reads as
    /// another button. Dark keeps the deep tint slab.
    private var showsSelectionRim: Bool {
        isSelected && colorScheme == .light
    }

    private var fill: Color {
        if isSelected, colorScheme == .dark {
            return shellPalette.tintColor(for: .dark)
        }
        if reduceTransparency {
            return shellPalette.opaquePanelFill(for: colorScheme)
        }
        let frost = colorScheme == .dark
            ? Color.white.opacity(0.10)
            : shellPalette.glassReadabilityTint(for: .light).opacity(GlassContrast.nestedTileTintOpacity)
        if isSelected, colorScheme == .light {
            return shellPalette.glassReadabilityTint(for: .light).opacity(
                min(0.42, GlassContrast.nestedTileTintOpacity + 0.12)
            )
        }
        return frost
    }
}

/// Batches chip glass into one render pass on iOS 26 without changing HStack spacing.
/// Put this around the chip `HStack` inside a `ScrollView`, never around the scroller
/// itself — `GlassEffectContainer` otherwise sizes to every off-screen pill.
struct GlassChipGroup<Content: View>: View {
    var spacing: CGFloat
    var content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct GlassEffectGroupingModifier: ViewModifier {
    var spacing: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// Hides the iOS 26 full-width nav blur that appears on scroll. Toolbar
/// capsules (Start, back, Save, bell) stay; the extra plate does not.
/// Do not pair this with `toolbarColorScheme(.light)` — that reintroduces
/// a white bar over MapKit.
private struct GlassNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .scrollEdgeEffectStyle(.hard, for: .all)
                .scrollEdgeEffectHidden(true, for: .all)
                .background(GlassNavigationBarEdgeHider())
        } else if #available(iOS 18.0, *) {
            content
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            content.toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

/// SwiftUI’s `scrollEdgeEffectHidden` often applies only after the push
/// animation, so Trip/Travel detail flashes a cream title plate over MapKit.
/// Set transparent bar appearances and hide scroll-edge effects as soon as
/// the hosting controller appears.
///
/// Do **not** hide `_UIBarBackground` / scroll-pocket UIViews. iOS 26 draws
/// Start, merge, bell, back, and share inside those layers — hiding them
/// leaves empty capsules on Trips and kills detail toolbar buttons.
private struct GlassNavigationBarEdgeHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.apply()
    }

    final class Controller: UIViewController {
        private var edgePassCount = 0

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            view.isAccessibilityElement = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            edgePassCount = 0
            UIView.performWithoutAnimation {
                apply()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard edgePassCount < 12 else { return }
            edgePassCount += 1
            hideScrollEdgeEffects()
        }

        func apply() {
            applyTransparentBarAppearance()
            hideScrollEdgeEffects()
        }

        private func applyTransparentBarAppearance() {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.shadowColor = .clear
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil

            if let item = parent?.navigationItem {
                item.standardAppearance = appearance
                item.scrollEdgeAppearance = appearance
                item.compactAppearance = appearance
                item.compactScrollEdgeAppearance = appearance
            }
        }

        private func hideScrollEdgeEffects() {
            guard #available(iOS 26.0, *) else { return }
            UIView.performWithoutAnimation {
                hideScrollEdgeEffects(in: parent?.view)
                hideScrollEdgeEffects(in: navigationController?.view)
            }
        }

        @available(iOS 26.0, *)
        private func hideScrollEdgeEffects(in view: UIView?) {
            guard let view else { return }
            if let scrollView = view as? UIScrollView {
                let effects = [
                    scrollView.topEdgeEffect,
                    scrollView.bottomEdgeEffect,
                    scrollView.leftEdgeEffect,
                    scrollView.rightEdgeEffect
                ]
                for effect in effects where !effect.isHidden {
                    effect.isHidden = true
                }
            }
            for subview in view.subviews {
                hideScrollEdgeEffects(in: subview)
            }
        }
    }
}

/// MapKit is not a SwiftUI `ScrollView`, so the nav-chrome edge hide may
/// miss it. Apply on `Map` so the white title plate does not sit on the map.
private struct GlassMapTopEdgeHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectHidden(true, for: .top)
                .background(GlassMapEdgeEffectProbe())
        } else {
            content
        }
    }
}

/// MapKit builds its scroll view after the nav-chrome passes run, and a split pane
/// lays the map out later still. The bar then paints a hard band over the map top.
/// This probe hides that edge in the navigation view whenever the map resizes.
@available(iOS 26.0, *)
private struct GlassMapEdgeEffectProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe {
        Probe()
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.setNeedsLayout()
    }

    final class Probe: UIView {
        private var lastSize: CGSize = .zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleHide()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != lastSize else { return }
            lastSize = bounds.size
            scheduleHide()
        }

        private func scheduleHide() {
            guard window != nil else { return }
            hideEdges()
            DispatchQueue.main.async { [weak self] in self?.hideEdges() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.hideEdges() }
        }

        private func hideEdges() {
            guard let root = navigationRoot else { return }
            UIView.performWithoutAnimation {
                Self.hideTopEdge(in: root)
            }
        }

        private var navigationRoot: UIView? {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let controller = next as? UIViewController {
                    return controller.navigationController?.view ?? controller.view
                }
                responder = next
            }
            return nil
        }

        private static func hideTopEdge(in view: UIView) {
            if let scrollView = view as? UIScrollView, !scrollView.topEdgeEffect.isHidden {
                scrollView.topEdgeEffect.isHidden = true
            }
            for subview in view.subviews {
                hideTopEdge(in: subview)
            }
        }
    }
}

extension View {
    /// Segmented pickers inside glass cards — palette selection instead of AccentColor.
    func glassSegmentedStyle() -> some View {
        modifier(GlassSegmentedStyleModifier())
    }

    func glassCard(
        cornerRadius: CGFloat = GlassTokens.cardRadius,
        density: GlassDensity = .panel,
        contentInset: CGFloat = GlassTokens.cardContentInset,
        frozen: Bool = false,
        allowsNative: Bool = true
    ) -> some View {
        modifier(
            GlassCardModifier(
                cornerRadius: cornerRadius,
                density: density,
                contentInset: contentInset,
                frozen: frozen,
                allowsNative: allowsNative
            )
        )
    }

    @ViewBuilder
    func glassChrome(
        cornerRadius: CGFloat = GlassTokens.chipRadius,
        frozen: Bool = false,
        enabled: Bool = true
    ) -> some View {
        if enabled {
            modifier(GlassChromeModifier(cornerRadius: cornerRadius, frozen: frozen))
        } else {
            self
        }
    }

    /// 44pt Liquid Glass circle — overlay collapse (Badges, Frequent routes, month forecast).
    func glassCircleChrome(
        side: CGFloat = GlassTokens.toolbarControlCircleSide,
        frozen: Bool = false
    ) -> some View {
        modifier(GlassCircleChromeModifier(side: side, frozen: frozen))
    }

    /// One vertical Liquid Glass capsule for the upright-Duo bell and Trips action.
    func glassCapsuleChrome(frozen: Bool = false) -> some View {
        modifier(GlassCapsuleChromeModifier(frozen: frozen))
    }

    /// Floating tab bar platter — Light Capsule `.clear` glass, Dark thin Material.
    func glassTabBar() -> some View {
        modifier(GlassTabBarModifier())
    }

    /// Nested frost inside a glass card. Selected = chip chrome; unselected = nested tint fill.
    func glassNestedChoice(isSelected: Bool) -> some View {
        modifier(GlassNestedChoiceModifier(isSelected: isSelected))
    }

    /// Inline inputs on glass panels — frosted tint instead of system grouped black/white.
    func glassField(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassFieldModifier(cornerRadius: cornerRadius))
    }

    /// Frosted input well + Light-only white rim. Search HStacks use this; buttons keep `glassField`.
    func glassInputWell(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassInputWellModifier(cornerRadius: cornerRadius))
    }

    /// Standard frosted text field — matches trip detail place/address inputs.
    func glassInputField(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassInputFieldModifier(cornerRadius: cornerRadius))
    }

    func glassRow(position: GlassRowPosition) -> some View {
        listRowBackground(GlassSectionRowBackground(position: position))
            .listRowInsets(rowInsets(for: position))
            .listRowSeparator(.hidden)
    }

    /// Short glass row for a section index beside a form (Settings on the book split).
    func glassCompactRow(position: GlassRowPosition) -> some View {
        let horizontal = GlassTokens.listContentHorizontalInset
        let vertical = GlassTokens.compactRowVerticalInset
        return listRowBackground(GlassSectionRowBackground(position: position))
            .listRowInsets(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
            .listRowSeparator(.hidden)
    }

    /// Section index list that fits the pane: short rows, a small top margin, and no bounce
    /// when every row is visible. Large Dynamic Type still scrolls once the rows overflow.
    func glassCompactIndexList() -> some View {
        environment(\.defaultMinListRowHeight, GlassTokens.compactRowMinHeight)
            .contentMargins(.top, GlassTokens.compactIndexTopMargin, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
    }

    /// Single-row glass panel (banners, one-off cards in lists).
    func glassListRow() -> some View {
        glassRow(position: .only)
    }

    /// Groups chip `glassEffect` hosts on iOS 26. Do not wrap a `List`.
    func glassEffectGrouping(spacing: CGFloat = GlassTokens.sectionSpacing) -> some View {
        modifier(GlassEffectGroupingModifier(spacing: spacing))
    }

    /// Horizontal chip scroller inside a glass card. `ScrollView` in an `HStack`
    /// otherwise keeps its content width, and native chip glass paints past the
    /// trailing corner. Apply to the scroller, not the whole card (labels stay whole).
    func glassChipScroller() -> some View {
        self
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipShape(Rectangle())
            .mask(Rectangle())
    }

    /// Light opacity/scale while a horizontal page is leaving the viewport.
    func glassCarouselPage() -> some View {
        modifier(GlassCarouselPageModifier())
    }

    func glassListChrome(showsAtmosphere: Bool = true) -> some View {
        scrollContentBackground(.hidden)
            .background {
                if showsAtmosphere {
                    AtmosphericBackground(style: .full)
                        .ignoresSafeArea()
                }
            }
            .listSectionSpacing(GlassTokens.sectionSpacing)
            .glassNavigationChrome()
            .onGlassShell()
    }

    /// Lighter shell for text-heavy forms (gradient only, solid section rows).
    func glassFormChrome() -> some View {
        scrollContentBackground(.hidden)
            .background {
                AtmosphericBackground(style: .lightweight)
                    .ignoresSafeArea()
            }
            .listSectionSpacing(GlassTokens.sectionSpacing)
            .glassNavigationChrome()
            .onGlassShell()
    }

    func glassFormRow(position: GlassRowPosition) -> some View {
        listRowBackground(FormSolidSectionRowBackground(position: position))
            .listRowInsets(rowInsets(for: position))
            .listRowSeparator(.hidden)
    }

    func glassFormListRow() -> some View {
        glassFormRow(position: .only)
    }

    /// Detail back. iOS 26 uses the system Liquid Glass back button and its own swipe-back,
    /// including the full-screen content pop. Older systems keep the custom glass circle and
    /// the edge-swipe enabler. The vehicle editor does not use this. On iOS 26 it keeps this
    /// system button until there are unsaved edits, then hides it. Older systems always use
    /// the custom circle and block the pop while edits are unsaved.
    @ViewBuilder
    func glassDetailBackNavigation(action: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .navigationBarBackButtonHidden(true)
                .background(NavigationInteractivePopEnabler())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        GlassToolbarBackButton(action: action)
                    }
                    .hideSharedToolbarBackgroundIfAvailable()
                }
        }
    }

    /// Keeps the nav bar visually merged with the atmospheric shell. Only the
    /// system toolbar *items* keep Liquid Glass — not a full-width scroll-edge plate.
    func glassNavigationChrome() -> some View {
        modifier(GlassNavigationChromeModifier())
    }

    /// Hides the iOS 26 white scroll-edge plate on MapKit (Trip / Travel detail).
    func glassMapTopEdgeHidden() -> some View {
        modifier(GlassMapTopEdgeHidden())
    }

    /// Destructive actions stay red even when the app shell uses brand-blue tint.
    func destructiveTint() -> some View {
        tint(.red)
    }

    private func rowInsets(for position: GlassRowPosition) -> EdgeInsets {
        let horizontal = GlassTokens.listContentHorizontalInset
        switch position {
        case .only:
            return EdgeInsets(top: 14, leading: horizontal, bottom: 14, trailing: horizontal)
        case .first:
            return EdgeInsets(top: 14, leading: horizontal, bottom: 10, trailing: horizontal)
        case .middle:
            return EdgeInsets(top: 10, leading: horizontal, bottom: 10, trailing: horizontal)
        case .last:
            return EdgeInsets(top: 10, leading: horizontal, bottom: 14, trailing: horizontal)
        }
    }
}

/// Informational / caution note inside a glass card or sheet (receipt OCR warning).
/// Nested frost (`glassNestedChoice(isSelected: false)`) — not a second Material, not a banner plate.
struct GlassNoticeCallout: View {
    enum Tone {
        case info
        case caution
    }

    let systemImage: String
    let title: String
    var message: String? = nil
    var tone: Tone = .caution

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .glassSecondaryInk()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassNestedChoice(isSelected: false)
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch tone {
        case .info: return GlassText.primary(for: colorScheme)
        case .caution: return GlassSemantic.paused(for: colorScheme)
        }
    }
}

/// Palette-tinted glyph disc (featured rows, glass zoom panels). White glyph, 0.72 white rim.
struct GlassPaletteDisc: View {
    let systemImage: String
    var side: CGFloat = GlassTokens.featuredRowDiscSide

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(width: side, height: side)
            .background {
                Circle()
                    .fill(shellPalette.tintColor(for: colorScheme))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.72), lineWidth: 1) }
            }
            .accessibilityHidden(true)
    }
}

/// One standout row in a plain glass list: palette disc + white glyph, semibold title,
/// optional footnote, trailing chevron. Use as a `Button` label; the row stays `glassRow`.
struct GlassFeaturedRowLabel: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            GlassPaletteDisc(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .glassPrimaryInk()
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .glassSecondaryInk()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .glassSecondaryInk()
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Raised option tile inside a glass card (Support the developer tips): nested frost
/// lifted by a soft shadow. Pair with a prominent button inside; not a second Material.
private struct GlassElevatedTileModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .glassNestedChoice(isSelected: true)
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.16),
                radius: 10,
                y: 5
            )
    }
}

extension View {
    func glassElevatedTile() -> some View {
        modifier(GlassElevatedTileModifier())
    }
}

/// 64 pt Liquid Glass circle with a caption and an optional detail line under it.
/// The circle reuses `.glassCircleChrome` (Reduce Transparency and iOS 17–18 fall back there).
struct GlassOptionCircle: View {
    let systemImage: String
    var caption: String
    var detail: String? = nil
    var isLoading: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        VStack(spacing: GlassTokens.optionCaptionSpacing) {
            circle
            VStack(spacing: 2) {
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .glassSecondaryInk()
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(shellPalette.tintColor(for: colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var circle: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(shellPalette.tintColor(for: colorScheme))
            } else {
                Image(systemName: systemImage)
                    .font(.title.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(shellPalette.tintColor(for: colorScheme))
                    .contentTransition(.identity)
            }
        }
        .glassCircleChrome(side: GlassTokens.optionCircleSide)
    }
}

/// Centered option circles, including a short last row. On iOS 26 the circles share one glass pass.
struct GlassOptionGrid<Content: View>: View {
    var columns: Int
    var spacing: CGFloat
    private let content: Content

    init(
        columns: Int = 3,
        spacing: CGFloat = GlassTokens.sectionSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = max(1, columns)
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassCenteredGridLayout(columns: columns, spacing: spacing) {
            content
        }
        .glassEffectGrouping(spacing: spacing)
    }
}

/// Root presenter for `GlassMorphPanel`. The host sits on the app root (above the tab bar), in the
/// same hierarchy as the screen that opened it, so that screen keeps rendering while the panel moves.
@MainActor
@Observable
final class GlassMorphPanelPresenter {
    static let shared = GlassMorphPanelPresenter()

    struct Presentation: Identifiable {
        let id = UUID()
        let accessibilityID: String
        let content: AnyView
        let onWillDismiss: () -> Void
        let onDismissed: () -> Void
    }

    private(set) var presentation: Presentation?

    func present<Content: View>(
        accessibilityID: String,
        onWillDismiss: @escaping () -> Void = {},
        onDismissed: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        guard presentation == nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = Presentation(
                accessibilityID: accessibilityID,
                content: AnyView(content()),
                onWillDismiss: onWillDismiss,
                onDismissed: onDismissed
            )
        }
    }

    fileprivate func finish(_ id: UUID) {
        guard presentation?.id == id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = nil
        }
    }
}

private struct GlassMorphPanelHostModifier: ViewModifier {
    @Bindable private var presenter = GlassMorphPanelPresenter.shared

    func body(content: Content) -> some View {
        content.overlay {
            if let presentation = presenter.presentation {
                GlassMorphPanel(
                    accessibilityID: presentation.accessibilityID,
                    onWillDismiss: presentation.onWillDismiss,
                    onDismissed: {
                        presenter.finish(presentation.id)
                        presentation.onDismissed()
                    }
                ) {
                    presentation.content
                }
                .id(presentation.id)
                .transition(.identity)
            }
        }
    }
}

extension View {
    /// Root host for `GlassMorphPanelPresenter`. Apply once on the app root, under `toastHost`.
    func glassMorphPanelHost() -> some View {
        modifier(GlassMorphPanelHostModifier())
    }
}

/// Camera-style bottom Liquid Glass panel, normally shown through `GlassMorphPanelPresenter`.
/// The panel runs its own grow and shrink. Tap outside, drag down, or the VoiceOver escape
/// gesture closes it. `onWillDismiss` fires when the source should sharpen back (0.12 s into a
/// tap-close, at once after a drag); `onDismissed` fires at the end.
/// Idle cost is one glass shape: motion runs only while opening, dragging, or closing.
struct GlassMorphPanel<Content: View>: View {
    var accessibilityID: String
    var onWillDismiss: () -> Void
    var onDismissed: () -> Void
    private let content: Content

    @State private var isShown = false
    @State private var isClosing = false
    @State private var dragY: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        accessibilityID: String,
        onWillDismiss: @escaping () -> Void = {},
        onDismissed: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityID = accessibilityID
        self.onWillDismiss = onWillDismiss
        self.onDismissed = onDismissed
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let inset = GlassTokens.morphPanelEdgeInset
            let bottomClearance = max(proxy.safeAreaInsets.bottom - inset, 12)
            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                panel(bottomClearance: bottomClearance)
                    .frame(maxWidth: GlassTokens.paneCardMaxWidth)
                    .frame(maxHeight: (proxy.size.height + proxy.safeAreaInsets.top) * 0.82, alignment: .bottom)
                    .padding(.horizontal, inset)
                    .padding(.bottom, inset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
        }
        .task {
            try? await Task.sleep(for: TrailhoundMotion.glassPanelOpenDelay)
            withAnimation(TrailhoundMotion.glassPanelOpen(reduceMotion: reduceMotion)) {
                isShown = true
            }
        }
    }

    private func panel(bottomClearance: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.morphPanelCornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            Capsule()
                .frame(width: 36, height: 5)
                .glassSecondaryInk()
                .opacity(0.55)
                .padding(.top, 8)
                .accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.bottom, bottomClearance)
            .blur(radius: isShown ? 0 : (reduceMotion ? 0 : GlassTokens.morphPanelBlur))
        }
        .frame(maxWidth: .infinity)
        .background { GlassMorphPanelBackground(shape: shape) }
        .contentShape(shape)
        .scaleEffect(scale, anchor: .bottom)
        .offset(y: dragOffset)
        .opacity(isShown ? 1 : 0)
        .gesture(dragToClose)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityAction(.escape) { close() }
    }

    private var scale: CGFloat {
        let resting: CGFloat
        if isShown || reduceMotion {
            resting = 1
        } else {
            resting = isClosing ? GlassTokens.morphPanelCloseScale : GlassTokens.morphPanelOpenScale
        }
        let pull = dragY > 0 ? min(dragY / 2000, 0.05) : 0
        return resting * (1 - pull)
    }

    /// Down follows the finger; up rubber-bands.
    private var dragOffset: CGFloat {
        dragY >= 0 ? dragY : -sqrt(-dragY) * 2
    }

    private var dragToClose: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isClosing else { return }
                dragY = value.translation.height
            }
            .onEnded { value in
                guard !isClosing else { return }
                let distance = GlassTokens.morphPanelDismissDistance
                if value.translation.height > distance || value.predictedEndTranslation.height > distance * 2 {
                    close(fromDrag: true)
                } else {
                    withAnimation(TrailhoundMotion.glassPanelOpen(reduceMotion: reduceMotion)) {
                        dragY = 0
                    }
                }
            }
    }

    private func close(fromDrag: Bool = false) {
        guard !isClosing else { return }
        isClosing = true
        if fromDrag || reduceMotion {
            onWillDismiss()
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: TrailhoundMotion.glassPanelSourceReturnDelay)
                onWillDismiss()
            }
        }
        withAnimation(TrailhoundMotion.glassPanelClose(reduceMotion: reduceMotion)) {
            isShown = false
        } completion: {
            onDismissed()
        }
    }
}

/// Native Liquid Glass panel in Light and Dark (Light carries the palette tint so white type reads).
/// Reduce Transparency and iOS 17–18 use `GlassToolbarControlBackground`.
private struct GlassMorphPanelBackground<PanelShape: InsettableShape>: View {
    let shape: PanelShape

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        if reduceTransparency {
            GlassToolbarControlBackground(shape: shape, frozen: true)
        } else if #available(iOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(glass, in: shape)
        } else {
            GlassToolbarControlBackground(shape: shape, frozen: false)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        guard colorScheme == .light else { return .regular }
        return .regular.tint(
            LightGlassPalette.nativeTint(for: shellPalette, increasedContrast: contrast == .increased)
        )
    }
}

/// Equal cells. A row with fewer items than `columns` is centered in the full row.
private struct GlassCenteredGridLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        metrics(proposal: proposal, subviews: subviews).total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = metrics(proposal: proposal, subviews: subviews)
        let cols = metrics.columns
        guard cols > 0, !subviews.isEmpty else { return }
        let cell = ProposedViewSize(width: metrics.cell.width, height: metrics.cell.height)
        var index = 0
        let rows = Int(ceil(Double(subviews.count) / Double(cols)))
        for row in 0..<rows {
            let count = min(cols, subviews.count - index)
            let rowWidth = metrics.cell.width * CGFloat(count) + spacing * CGFloat(max(0, count - 1))
            var x = bounds.minX + (metrics.total.width - rowWidth) / 2
            let y = bounds.minY + CGFloat(row) * (metrics.cell.height + spacing)
            for _ in 0..<count {
                subviews[index].place(
                    at: CGPoint(x: x + metrics.cell.width / 2, y: y + metrics.cell.height / 2),
                    anchor: .center,
                    proposal: cell
                )
                x += metrics.cell.width + spacing
                index += 1
            }
        }
    }

    private struct Metrics {
        var columns: Int
        var cell: CGSize
        var total: CGSize
    }

    private func metrics(proposal: ProposedViewSize, subviews: Subviews) -> Metrics {
        let count = subviews.count
        guard count > 0 else {
            return Metrics(columns: 0, cell: .zero, total: .zero)
        }
        let cols = min(max(1, columns), count)
        let rows = Int(ceil(Double(count) / Double(cols)))
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealW = ideals.map(\.width).max() ?? 0
        let idealH = ideals.map(\.height).max() ?? 0
        let cellW: CGFloat
        if let proposed = proposal.width, proposed.isFinite, proposed > 0 {
            let slots = (proposed - spacing * CGFloat(max(0, cols - 1))) / CGFloat(cols)
            cellW = min(idealW, max(0, slots))
        } else {
            cellW = idealW
        }
        let cell = CGSize(width: cellW, height: idealH)
        let total = CGSize(
            width: cell.width * CGFloat(cols) + spacing * CGFloat(max(0, cols - 1)),
            height: cell.height * CGFloat(rows) + spacing * CGFloat(max(0, rows - 1))
        )
        return Metrics(columns: cols, cell: cell, total: total)
    }
}

/// Receipt / document photo tile. Rounded nested radius + thin white rim; a frost
/// placeholder with a document glyph while the image loads.
struct ReceiptThumbnailTile: View {
    let image: UIImage?
    var width: CGFloat = 72
    var height: CGFloat = 96

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.nestedChoiceRadius, style: .continuous)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                shape
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.16))
                Image(systemName: "doc.text.image")
                    .font(.title3.weight(.semibold))
                    .glassSecondaryInk()
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.56), lineWidth: 1)
        }
    }
}

/// Pinned section title. Docks at the top of the scroll — words only, no chip
/// slider and no frost plate. The next section title pushes this one off.
struct GlassStickySectionHeader<Trailing: View>: View {
    let title: String
    var accessibilityIdentifier: String
    var trailing: Trailing

    /// Caption is 12 pt. The section title is 20% smaller and still follows Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var titlePointSize = 9.6

    init(
        title: String,
        accessibilityIdentifier: String = "",
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.localizedCapitalized)
                .font(.system(size: titlePointSize, weight: .semibold))
                .glassSecondaryInk()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

extension GlassStickySectionHeader where Trailing == EmptyView {
    init(title: String, accessibilityIdentifier: String = "") {
        self.init(title: title, accessibilityIdentifier: accessibilityIdentifier) { EmptyView() }
    }
}

/// Scroll-linked collapse. The title stays at the top of the card; the body
/// scrolls up under that title and the glass bottom edge rises with it.
enum GlassCollapsingLayout {
    static let scrollSpace = "glass.collapsing.scroll"

    static func stuckOffset(minY: CGFloat, pinY: CGFloat = 0) -> CGFloat {
        max(0, pinY - minY)
    }

    static func visibleHeight(fullHeight: CGFloat, stuckOffset: CGFloat) -> CGFloat {
        max(0, fullHeight - stuckOffset)
    }

    /// A poster can pass a body inset of 0 so the artwork fills the plate.
    /// The section title still uses the standard card inset: a continuous
    /// corner clips the first letters when the title sits on the rim.
    static func titleChromeInset(contentInset: CGFloat, applyCard: Bool) -> CGFloat {
        guard applyCard else { return 0 }
        return max(contentInset, StatsCardTokens.contentInset)
    }

    /// Collapse until `minHeight`. Further scrolling fades that strip out where
    /// it sits; scrolling back fades it in. It does not travel off the pin.
    static func placement(
        natural: CGFloat,
        stuck: CGFloat,
        minHeight: CGFloat,
        titleBand: CGFloat
    ) -> GlassCollapsePlacement {
        let floor = min(max(minHeight, 0), max(natural, 0))
        let raw = visibleHeight(fullHeight: natural, stuckOffset: stuck)
        let exiting = stuck > 0 && natural > floor && raw < floor
        let plate = exiting ? floor : raw
        let exit = exiting ? max(0, stuck - (natural - floor)) : 0
        let opacity = exiting && floor > 0 ? max(0, 1 - exit / floor) : 1
        return GlassCollapsePlacement(
            plateHeight: plate,
            titleOffset: stuck,
            contentShown: exiting ? 0 : max(0, plate - titleBand),
            pinCompensation: exit,
            opacity: opacity,
            isExiting: exiting
        )
    }
}

struct GlassCollapsePlacement: Equatable {
    var plateHeight: CGFloat
    var titleOffset: CGFloat
    var contentShown: CGFloat
    /// How far the strip would have slid past the pin. The view holds it with
    /// layout padding (`titleOffset`) instead of a render offset, so the fade
    /// is not clipped away.
    var pinCompensation: CGFloat
    var opacity: CGFloat
    var isExiting: Bool
}

/// Title + body in one glass card. Scrolling lifts the body under the title.
/// The plate is only as tall as the part still on screen — bottom edge rises.
struct GlassCollapsingCard<Content: View, Trailing: View>: View {
    let title: String
    var accessibilityIdentifier: String
    var contentInset: CGFloat
    var applyCard: Bool
    var pinsCornerGlyph: Bool
    var trailing: Trailing
    var content: Content

    @State private var stuck: CGFloat = 0
    @State private var natural: CGFloat = 0
    @State private var titleHeight: CGFloat = 0

    init(
        title: String,
        accessibilityIdentifier: String = "",
        contentInset: CGFloat = StatsCardTokens.contentInset,
        applyCard: Bool = true,
        pinsCornerGlyph: Bool = true,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.contentInset = contentInset
        self.applyCard = applyCard
        self.pinsCornerGlyph = pinsCornerGlyph
        self.trailing = trailing()
        self.content = content()
    }

    private var titleChromeInset: CGFloat {
        GlassCollapsingLayout.titleChromeInset(contentInset: contentInset, applyCard: applyCard)
    }

    private var titleBand: CGFloat {
        titleHeight + titleChromeInset
    }

    /// Title row plus the card’s bottom inset. Further scrolling fades this strip out.
    private var minHeight: CGFloat {
        titleBand + (applyCard ? contentInset : 0)
    }

    private var placement: GlassCollapsePlacement {
        GlassCollapsingLayout.placement(
            natural: natural,
            stuck: stuck,
            minHeight: minHeight,
            titleBand: titleBand
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassStickySectionHeader(title: title)
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { titleHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, height in
                                titleHeight = height
                            }
                    }
                }
            content
        }
        .padding(applyCard ? contentInset : 0)
        // Full-bleed posters keep side artwork at the rim. The title still needs
        // the standard inset, so the extra top padding is only the difference.
        .padding(.top, max(0, titleChromeInset - (applyCard ? contentInset : 0)))
        .glassCollapsingPlate(
            stuck: $stuck,
            natural: $natural,
            titleBand: titleBand,
            minHeight: minHeight,
            showsGlass: applyCard
        )
        .overlay(alignment: .top) {
            sectionHeader
                .padding(.horizontal, titleChromeInset)
                .padding(.top, titleChromeInset + placement.titleOffset)
                .padding(.trailing, cornerClearance)
                .opacity(Double(placement.opacity))
                .allowsHitTesting(placement.opacity > 0.05)
        }
        .overlay(alignment: .topTrailing) {
            trailing
                .padding(.top, StatsCardTokens.expandGlyphPosterInsets.top + placement.titleOffset)
                .padding(.trailing, StatsCardTokens.expandGlyphPosterInsets.trailing)
                .opacity(Double(placement.opacity))
                .allowsHitTesting(placement.opacity > 0.05)
        }
    }

    /// Keeps a corner glyph from covering the last words of the section title.
    private var cornerClearance: CGFloat {
        pinsCornerGlyph ? 28 : 0
    }

    private var sectionHeader: some View {
        GlassStickySectionHeader(
            title: title,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

extension GlassCollapsingCard where Trailing == EmptyView {
    init(
        title: String,
        accessibilityIdentifier: String = "",
        contentInset: CGFloat = StatsCardTokens.contentInset,
        applyCard: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            accessibilityIdentifier: accessibilityIdentifier,
            contentInset: contentInset,
            applyCard: applyCard,
            pinsCornerGlyph: false,
            trailing: { EmptyView() },
            content: content
        )
    }
}

extension View {
    /// Named space for `GlassCollapsingCard`. Put this on the `ScrollView`.
    func glassCollapsingScroll() -> some View {
        coordinateSpace(name: GlassCollapsingLayout.scrollSpace)
    }

    /// Bottom-aligned short glass. Body scrolls up under `titleBand`; the plate
    /// bottom stays on the content bottom, so the card shrinks upward.
    func glassCollapsingPlate(
        stuck: Binding<CGFloat>,
        natural: Binding<CGFloat>,
        titleBand: CGFloat = 0,
        minHeight: CGFloat = 0,
        showsGlass: Bool = true
    ) -> some View {
        modifier(
            GlassCollapsingPlateModifier(
                stuck: stuck,
                natural: natural,
                titleBand: titleBand,
                minHeight: minHeight,
                showsGlass: showsGlass
            )
        )
    }
}

private struct GlassCollapseFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.height > 1 {
            value = next
        }
    }
}

private struct GlassCollapsingPlateModifier: ViewModifier {
    @Binding var stuck: CGFloat
    @Binding var natural: CGFloat
    var titleBand: CGFloat
    var minHeight: CGFloat
    var showsGlass: Bool

    func body(content: Content) -> some View {
        let placement = natural > 1
            ? GlassCollapsingLayout.placement(
                natural: natural,
                stuck: stuck,
                minHeight: minHeight,
                titleBand: titleBand
            )
            : nil
        let fade = placement?.opacity ?? 1
        let heldTop = placement?.titleOffset ?? 0
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GlassCollapseFrameKey.self,
                        value: geo.frame(in: .named(GlassCollapsingLayout.scrollSpace))
                    )
                }
            }
            .onPreferenceChange(GlassCollapseFrameKey.self) { frame in
                apply(minY: frame.minY, height: frame.height)
            }
            .mask(alignment: .bottom) {
                Rectangle().frame(height: placement?.contentShown ?? 8_000)
            }
            .background(alignment: .top) {
                if showsGlass, let placement, placement.plateHeight > 1 {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: placement.plateHeight)
                        .statsFullCard(contentInset: 0)
                        .padding(.top, heldTop)
                }
            }
            .opacity(Double(fade))
            .allowsHitTesting(fade > 0.05)
    }

    private func apply(minY: CGFloat, height: CGFloat) {
        guard height > 1 else { return }
        let nextStuck = GlassCollapsingLayout.stuckOffset(minY: minY)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if stuck != nextStuck {
                stuck = nextStuck
            }
            if natural != height {
                natural = height
            }
        }
    }
}

extension View {
    /// Marks the control a sheet zooms out of. Pair with `.glassSheetZoom(from:in:)` on the sheet.
    @ViewBuilder
    func glassSheetZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// The sheet grows out of its source control and shrinks back into it on dismiss, including
    /// the interactive swipe. iOS 17 keeps the system slide-up.
    @ViewBuilder
    func glassSheetZoom(from id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

private struct GlassCarouselPageModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : GlassTokens.carouselPageRestOpacity)
                    .scaleEffect(phase.isIdentity ? 1 : GlassTokens.carouselPageRestScale)
            }
        }
    }
}
