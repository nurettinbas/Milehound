import SwiftUI

/// One chrome for every Stats surface: half-span siblings, full-width cards, nested tiles.
/// Nested tiles are fills — never a second `Material` blur.
enum StatsCardTokens {
    static let radius: CGFloat = GlassTokens.cardRadius
    static let nestedRadius: CGFloat = 12
    static let pairSpacing: CGFloat = 12
    static let contentInset: CGFloat = 14
    /// Compact expand glyph sits in the card’s top-trailing corner, not on the title baseline.
    static let expandGlyphOffset = CGSize(width: 16, height: -18)
    /// Forecast / poster cards have no content inset — pin the same glyph this far from the rim.
    static let expandGlyphPosterInsets = EdgeInsets(top: 2, leading: 0, bottom: 0, trailing: 2)
    static let summaryGridInset: CGFloat = 8
    static let halfMinHeight: CGFloat = 188
    static let listRowVerticalInset: CGFloat = 6
    /// Title + value/trend + previous line, no leftover empty band.
    static let nestedTileHeight: CGFloat = 64
    static let nestedTileTitleRowHeight: CGFloat = 16
    static let nestedTilePreviousLineHeight: CGFloat = 13
    /// Capsule bars inside a Stats card (vehicle-compare share, month-forecast mix).
    static let segmentBarHeight: CGFloat = 6
    /// Recap / forecast overlay poster — copy sits on artwork, not a form stack.
    static let posterHeight: CGFloat = 148
    /// Overlay copy and expand glyph. Artwork ignores this and fills the card.
    static let posterOverlayInsets = EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10)
    /// Forecast expand hero — taller than the Stats-list poster.
    static let posterExpandedHeight: CGFloat = 220
    /// Accessibility / stacked forecast artwork, matching Recap stacked teaser.
    static let posterStackedArtworkHeight: CGFloat = 88
}

/// Portrait chapter cards under the Recap hub Play chip. Frozen Canvas — no extra TimelineView.
enum RecapChapterRailTokens {
    static let cardWidth: CGFloat = 140
    static let cardHeight: CGFloat = 200
    static let peek: CGFloat = 24
    static let spacing: CGFloat = 10
    static let titleInset: CGFloat = 10
    /// Centered chapter glyph — not the story scene.
    static let emblemPointSize: CGFloat = 64
    static let emblemLift: CGFloat = 18
}

/// Distinct mix-bar hues. Stop 0 is the selected shell tint; later stops rotate that hue.
/// Not expense-category colors and not the same tint at lower opacity.
enum StatsSegmentTokens {
    static let spacing: CGFloat = 1
    /// Drive / installments / other. `0` keeps the theme color; `180` / `90` split the wheel.
    static let hueOffsets: [Double] = [0, 180, 90]

    static func fillRGB(index: Int, scheme: ColorScheme, palette: ShellPalette) -> ShellRGB {
        let tint = palette.atmosphere(for: scheme).tint
        let clamped = min(max(index, 0), hueOffsets.count - 1)
        let offset = hueOffsets[clamped]
        guard offset != 0 else { return tint }
        return tint.rotatedInk(degrees: offset, for: scheme)
    }

    static func fill(index: Int, scheme: ColorScheme, palette: ShellPalette) -> Color {
        fillRGB(index: index, scheme: scheme, palette: palette).color
    }
}

/// Recap cost page + forecast mix: estimated fuel is stop 0, logged fuel is stop 1.
enum RecapSpendInk {
    static let fuelStop = 0
    static let expensesStop = 1

    static func fuelRGB(scheme: ColorScheme, palette: ShellPalette) -> ShellRGB {
        StatsSegmentTokens.fillRGB(index: fuelStop, scheme: scheme, palette: palette)
    }

    static func expensesRGB(scheme: ColorScheme, palette: ShellPalette) -> ShellRGB {
        StatsSegmentTokens.fillRGB(index: expensesStop, scheme: scheme, palette: palette)
    }

    static func fuel(scheme: ColorScheme, palette: ShellPalette) -> Color {
        fuelRGB(scheme: scheme, palette: palette).color
    }

    static func expenses(scheme: ColorScheme, palette: ShellPalette) -> Color {
        expensesRGB(scheme: scheme, palette: palette).color
    }
}

/// 8 pt palette capsule matching a `StatsSegmentBar` stop — legend only, not a chip.
struct StatsSegmentSwatch: View {
    let index: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Capsule()
            .fill(StatsSegmentTokens.fill(index: index, scheme: colorScheme, palette: shellPalette))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

enum StatsCardFill {
    static func nested(
        scheme: ColorScheme,
        palette: ShellPalette,
        reduceTransparency: Bool
    ) -> Color {
        if reduceTransparency {
            return palette.opaquePanelFill(for: scheme)
        }
        return scheme == .dark
            ? Color.white.opacity(0.10)
            : palette.glassReadabilityTint(for: .light).opacity(GlassContrast.nestedTileTintOpacity)
    }
}

struct StatsSegment: Identifiable, Equatable {
    let id: String
    let share: Double
    /// Mix-bar stop (`StatsSegmentTokens.hueOffsets`). Survives filtering zero shares.
    let stop: Int
}

/// Small supporting copy on Stats cards uses the shell-wide Light white hierarchy.
enum StatsTextColor {
    static func secondary(for scheme: ColorScheme) -> Color {
        GlassText.secondary(for: scheme)
    }

    static func tertiary(for scheme: ColorScheme) -> Color {
        GlassText.tertiary(for: scheme)
    }
}

private struct StatsNestedTileModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(
                maxWidth: .infinity,
                minHeight: StatsCardTokens.nestedTileHeight,
                maxHeight: StatsCardTokens.nestedTileHeight,
                alignment: .topLeading
            )
            .background {
                RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous)
                    .fill(tileFill)
            }
    }

    private var tileFill: Color {
        StatsCardFill.nested(
            scheme: colorScheme,
            palette: shellPalette,
            reduceTransparency: reduceTransparency
        )
    }
}

private struct StatsNestedPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous)
                    .fill(
                        StatsCardFill.nested(
                            scheme: colorScheme,
                            palette: shellPalette,
                            reduceTransparency: reduceTransparency
                        )
                    )
            }
    }
}

private struct StatsFrostChipModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        StatsCardFill.nested(
                            scheme: colorScheme,
                            palette: shellPalette,
                            reduceTransparency: reduceTransparency
                        )
                    )
            }
    }
}

/// Palette-tint capsule + white type. Same fill as compact Play — not frost, not a second Material.
private struct StatsThemeChipModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(shellPalette.tintColor(for: colorScheme))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                    }
            }
    }
}

/// Distinct-hue capsule mix for composition (month forecast). Vehicle compare uses `StatsShareBar`.
struct StatsSegmentBar: View {
    let segments: [StatsSegment]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let drawnWidth = geo.size.width * progress
            HStack(spacing: StatsSegmentTokens.spacing) {
                ForEach(visibleSegments) { segment in
                    Capsule()
                        .fill(
                            StatsSegmentTokens.fill(
                                index: segment.stop,
                                scheme: colorScheme,
                                palette: shellPalette
                            )
                        )
                        .frame(width: segmentWidth(share: segment.share, drawnWidth: drawnWidth))
                }
            }
        }
        .frame(height: StatsCardTokens.segmentBarHeight)
        .background {
            Capsule()
                .fill(
                    StatsCardFill.nested(
                        scheme: colorScheme,
                        palette: shellPalette,
                        reduceTransparency: reduceTransparency
                    )
                )
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
        .onAppear(perform: reveal)
    }

    private var visibleSegments: [StatsSegment] {
        segments.filter { $0.share > 0 }
    }

    private func segmentWidth(share: Double, drawnWidth: CGFloat) -> CGFloat {
        let raw = drawnWidth * CGFloat(share)
        return raw <= 0 ? 0 : max(raw, 2)
    }

    private var playsMotion: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    private func reveal() {
        if playsMotion {
            progress = 0
            withAnimation(MilehoundMotion.cardSpring) {
                progress = 1
            }
        } else {
            progress = 1
        }
    }
}

/// Single-color capsule scaled to a 0...1 share of the frost track — not Swift Charts.
struct StatsShareBar: View {
    var share: Double
    var fill: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(share, 0), 1)
            let width = geo.size.width * progress * CGFloat(clamped)
            HStack(spacing: 0) {
                Capsule()
                    .fill(fill)
                    .frame(width: width <= 0 ? 0 : max(width, 2))
                Spacer(minLength: 0)
            }
        }
        .frame(height: StatsCardTokens.segmentBarHeight)
        .background {
            Capsule()
                .fill(
                    StatsCardFill.nested(
                        scheme: colorScheme,
                        palette: shellPalette,
                        reduceTransparency: reduceTransparency
                    )
                )
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
        .onAppear(perform: reveal)
    }

    private var playsMotion: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    private func reveal() {
        if playsMotion {
            progress = 0
            withAnimation(MilehoundMotion.cardSpring) {
                progress = 1
            }
        } else {
            progress = 1
        }
    }
}

extension View {
    /// Overlay copy on Recap / forecast posters. Artwork stays edge-to-edge.
    func statsPosterOverlayPadding() -> some View {
        padding(StatsCardTokens.posterOverlayInsets)
    }

    /// Full-width Stats card in a clear List row. Light iOS 26 uses native
    /// `glassEffect` behind the content. Nested tiles stay frost fills.
    /// Pass `frozen:` during morph.
    func statsFullCard(contentInset: CGFloat = StatsCardTokens.contentInset, frozen: Bool = false) -> some View {
        glassCard(
            cornerRadius: StatsCardTokens.radius,
            contentInset: contentInset,
            frozen: frozen
        )
        .statsCardListRow()
    }

    /// Half of a 2-up pair. Fixed minHeight — no GeometryReader in the List row.
    func statsHalfCard() -> some View {
        glassCard(
            cornerRadius: StatsCardTokens.radius,
            contentInset: StatsCardTokens.contentInset
        )
        .frame(
            maxWidth: .infinity,
            minHeight: StatsCardTokens.halfMinHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    func statsCardListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: StatsCardTokens.listRowVerticalInset,
                    leading: GlassTokens.panelHorizontalInset,
                    bottom: StatsCardTokens.listRowVerticalInset,
                    trailing: GlassTokens.panelHorizontalInset
                )
            )
    }

    /// Frost fill inside a Stats card. Not `ultraThinMaterial`.
    func statsNestedTile() -> some View {
        modifier(StatsNestedTileModifier())
    }

    /// Nested-tile frost capsule for trend / confidence labels inside a Stats card.
    func statsFrostChip() -> some View {
        modifier(StatsFrostChipModifier())
    }

    /// Palette-tint capsule + white type for labels on dark Recap chapter plates.
    func statsThemeChip() -> some View {
        modifier(StatsThemeChipModifier())
    }

    /// Variable-height nested frost panel (expand overlays). Same fill as `statsNestedTile`, not a second Material.
    func statsNestedPanel() -> some View {
        modifier(StatsNestedPanelModifier())
    }
}

struct StatsCardPair<Left: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(alignment: .top, spacing: StatsCardTokens.pairSpacing) {
            left()
                .statsHalfCard()
            right()
                .statsHalfCard()
        }
        .frame(minHeight: StatsCardTokens.halfMinHeight)
        .statsCardListRow()
    }
}

/// Two already-chromed cards in one list row. Does not add a second glass plate.
/// On the open fold the gap sits on the window hinge, not on half the row:
/// the side tab makes the trailing card narrower.
struct StatsCardPairRow<Left: View, Right: View>: View {
    @Environment(\.milehoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowWidth: CGFloat = 0

    private var alignsToHinge: Bool {
        layout.usesBookPanes
    }

    private var gap: CGFloat {
        alignsToHinge ? GlassTokens.hingeGutter : StatsCardTokens.pairSpacing
    }

    private var leadingWidth: CGFloat? {
        guard alignsToHinge else { return nil }
        let windowWidth = measuredWindowWidth > 1 ? measuredWindowWidth : layout.size.width
        let contentWidth = contentInWindow.width > 1 ? contentInWindow.width : layout.size.width
        let origin = contentInWindow.width > 1 ? contentInWindow.minX : 0
        guard contentWidth > 1, windowWidth > 1 else { return nil }
        if let fraction = MilehoundLayoutResolver.flatBookLeadingFraction(
            isPhoneBook: layout.isPhoneBook,
            layoutClass: layout.layoutClass,
            isLandscape: layout.isLandscape,
            hingeFullyOpen: MilehoundHingeMonitor.shared.isFullyOpen,
            fraction: MilehoundLayoutResolver.flatStatsLeadingFraction,
            isPadBook: false
        ) {
            return MilehoundLayoutResolver.fractionLeadingPaneWidth(
                contentWidth: contentWidth,
                gutter: gap,
                leadingFraction: fraction
            )
        }
        return MilehoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: origin,
            contentWidth: contentWidth,
            windowWidth: windowWidth,
            gutter: gap,
            listOnVisualLeft: MilehoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection)
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            left()
                .frame(width: leadingWidth, alignment: .top)
                .frame(maxWidth: leadingWidth == nil ? .infinity : nil, maxHeight: .infinity, alignment: .top)
            right()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .statsCardListRow()
        .background {
            if alignsToHinge {
                MilehoundWindowFrameReader { frame, windowSize in
                    guard frame != contentInWindow || windowSize.width != measuredWindowWidth else { return }
                    contentInWindow = frame
                    measuredWindowWidth = windowSize.width
                }
            }
        }
    }
}

/// Placeholder nested tile so the summary grid stays packed while a snapshot loads.
struct StatsSummaryTileSkeleton: View {
    var reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var shimmerPhase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(barFill)
                .frame(width: 76, height: 7)
            Capsule()
                .fill(barFill)
                .frame(width: 52, height: 11)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsNestedTile()
        .overlay {
            if !reduceMotion {
                RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                MilehoundBrandColors.brandBottom.opacity(colorScheme == .dark ? 0.14 : 0.10),
                                Color.clear
                            ],
                            startPoint: shimmerPhase ? .trailing : .leading,
                            endPoint: shimmerPhase ? UnitPoint(x: 1.4, y: 0.5) : UnitPoint(x: 0.4, y: 0.5)
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                shimmerPhase = true
            }
        }
    }

    private var barFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : shellPalette.glassReadabilityTint(for: .light).opacity(0.32)
    }
}
