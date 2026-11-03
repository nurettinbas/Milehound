import SwiftUI

enum RecordingCardStyle {
    static let cornerRadius: CGFloat = GlassTokens.cardRadius

    static func fillColors(
        isPaused: Bool,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> [Color] {
        let atm = palette.atmosphere(for: scheme)
        if isPaused {
            return [atm.mid.color.opacity(0.72), atm.bottom.color.opacity(0.88)]
        }
        return [atm.glow.color, atm.tint.color]
    }

    static func background(
        isPaused: Bool,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> LinearGradient {
        LinearGradient(
            colors: fillColors(isPaused: isPaused, palette: palette, scheme: scheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Glass recording hero: material + palette tint.
    @ViewBuilder
    static func glassSurface(isPaused: Bool) -> some View {
        RecordingGlassSurface(isPaused: isPaused)
    }

    /// Scroll-friendly surface for the trips list (no live material blur).
    @ViewBuilder
    static func listSurface(isPaused: Bool) -> some View {
        RecordingListSurface(isPaused: isPaused)
    }
}

/// 2D/3D and overview/follow on the live-map HUD.
///
/// The plates are pale palette glass, so the selected segment can carry the palette
/// tint. Its label is whichever of white or the light chrome ink contrasts with that tint.
/// Unselected labels use the plate’s secondary ink.
enum RecordingSegmentChrome {
    static func thumb(for palette: ShellPalette, scheme: ColorScheme) -> Color {
        palette.tintColor(for: scheme)
    }

    static func label(
        isSelected: Bool,
        palette: ShellPalette,
        scheme: ColorScheme,
        reduceTransparency: Bool
    ) -> Color {
        if isSelected {
            return selectedLabel(palette: palette, scheme: scheme)
        }
        return LiveFollowHUDInk.secondary(
            scheme: scheme,
            palette: palette,
            reduceTransparency: reduceTransparency
        )
    }

    /// White when the tint is dark; light-chrome ink when the tint is light.
    static func selectedLabel(palette: ShellPalette, scheme: ColorScheme) -> Color {
        let tint = palette.atmosphere(for: scheme).tint.relativeLuminance
        let chrome = palette.atmosphere(for: .light).chrome.relativeLuminance
        let whiteContrast = contrastRatio(tint, 1)
        let chromeContrast = contrastRatio(tint, chrome)
        if chromeContrast >= whiteContrast {
            return palette.chromeColor(for: .light)
        }
        return Color.white
    }

    private static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Ink on the live-map frost. Light plates use the palette’s deep chrome.
/// Dark plates and Reduce Transparency use the shell foreground.
enum LiveFollowHUDInk {
    static func primary(
        scheme: ColorScheme,
        palette: ShellPalette,
        reduceTransparency: Bool
    ) -> Color {
        if reduceTransparency {
            return palette.shellForeground(for: scheme)
        }
        if scheme == .dark {
            return Color.primary
        }
        return palette.chromeColor(for: .light)
    }

    static func secondary(
        scheme: ColorScheme,
        palette: ShellPalette,
        reduceTransparency: Bool
    ) -> Color {
        primary(scheme: scheme, palette: palette, reduceTransparency: reduceTransparency)
            .opacity(0.62)
    }
}

/// Compact map plate behind HUD content. iOS 26 live glass goes through `.liveMapHUDPlate(_:)`
/// instead, because a `glassEffect` on a background view draws over the labels inside a grouping.
/// Snapshots force the frozen frost so the glass does not change between runtimes.
struct LiveMapHUDPlate<ControlShape: InsettableShape>: View {
    let shape: ControlShape

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.glassForcesSolidPlate) private var glassForcesSolidPlate

    var body: some View {
        if reduceTransparency {
            shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
        } else if glassForcesSolidPlate {
            GlassToolbarFrozenPlate(shape: shape)
        } else {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.18))
            shape.fill(shellPalette.tintColor(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.10))
            shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.5)
        }
    }
}

/// iOS 26: palette-tinted Liquid Glass on the content itself, so labels stay on top of the glass.
/// Only inside `LiveFollowHUD`, whose `glassEffectGrouping` renders every plate as one glass host.
private struct LiveMapHUDPlateModifier<ControlShape: InsettableShape>: ViewModifier {
    let shape: ControlShape
    var interactive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.glassForcesSolidPlate) private var glassForcesSolidPlate

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, !glassForcesSolidPlate {
            let glass = Glass.regular.tint(
                GlassTokens.liveMapGlassTint(for: colorScheme, palette: shellPalette)
            )
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content.background { LiveMapHUDPlate(shape: shape) }
        }
    }
}

extension View {
    /// Live-map HUD plate. `interactive` adds press feedback for plates that are themselves the button.
    func liveMapHUDPlate<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(LiveMapHUDPlateModifier(shape: shape, interactive: interactive))
    }

    /// `LiveMapHUDPlate` track for a two-option control on the recording HUD.
    func recordingSegmentTrack(height: CGFloat = 28, inset: CGFloat = 2) -> some View {
        modifier(RecordingSegmentTrackModifier(height: height, inset: inset))
    }

    /// White thumb behind a selected live-map segment. `namespace` is nil when Reduce Motion is on.
    func recordingSegmentThumb(
        isSelected: Bool,
        morphID: String,
        namespace: Namespace.ID?
    ) -> some View {
        modifier(
            RecordingSegmentThumbModifier(
                isSelected: isSelected,
                morphID: morphID,
                namespace: namespace
            )
        )
    }
}

/// Live-map route chip. Same frozen plate and ink as the rest of the live-map HUD.
/// No destination: "Destination". Otherwise remaining distance and a red minute countdown, or the route state.
struct RecordingRouteChip: View {
    enum Content: Equatable {
        case setDestination
        case loading
        case offline
        case failed
        case estimate(distance: String, countdown: String, arrival: String)
    }

    /// Remaining minutes on the destination row and the collapsed route chip.
    static let countdownInk = Color(red: 1, green: 0.32, blue: 0.32)

    let content: Content
    let action: () -> Void
    /// Live HUD: the row fills the shared route card.
    var wide: Bool = false
    /// Inside the route card the row is a full-width theme capsule, so it reads as the button.
    var embedded: Bool = false
    /// 1 keeps the compact chip. The top route card passes 1.25.
    var heightScale: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    private var ink: Color {
        LiveFollowHUDInk.primary(
            scheme: colorScheme,
            palette: shellPalette,
            reduceTransparency: reduceTransparency
        )
    }

    private var rowInk: Color {
        embedded ? Color.white : ink
    }

    var body: some View {
        Button {
            MilehoundHaptics.selection()
            action()
        } label: {
            HStack(spacing: embedded ? 6 : 4) {
                leading
                titleLabel
                if embedded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * heightScale, weight: .bold))
                        .foregroundStyle(Color.white)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, (embedded ? 14 : (wide ? 12 : 8)) * heightScale)
            .padding(.vertical, (embedded ? 7 : (wide ? 5 : 3)) * heightScale)
            .fixedSize(horizontal: embedded, vertical: false)
            .frame(maxWidth: wide && !embedded ? .infinity : nil)
            .chipPlate(embedded: embedded)
            .compositingGroup()
            .shadow(
                color: embedded ? Color.black.opacity(colorScheme == .dark ? 0.45 : 0.22) : .clear,
                radius: embedded ? 7 : 0,
                y: embedded ? 3 : 0
            )
            .contentShape(AnyShape(Capsule()))
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(
            content == .setDestination ? "" : L10n.string("recording.live_map.destination.change")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(content == .setDestination ? "liveMap.destination" : "liveMap.eta")
    }

    @ViewBuilder
    private var leading: some View {
        switch content {
        case .setDestination:
            Image(systemName: "flag.fill")
                .font(.system(size: 12 * heightScale, weight: .semibold))
                .foregroundStyle(rowInk)
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(heightScale)
                .tint(rowInk)
        case .offline:
            Image(systemName: "wifi.slash")
                .font(.system(size: 12 * heightScale, weight: .semibold))
                .foregroundStyle(rowInk)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12 * heightScale, weight: .semibold))
                .foregroundStyle(GlassSemantic.paused(for: colorScheme))
        case .estimate:
            Image(systemName: "flag.checkered")
                .font(.system(size: 12 * heightScale, weight: .semibold))
                .foregroundStyle(rowInk)
        }
    }

    private var title: String {
        switch content {
        case .setDestination:
            return L10n.string("recording.live_map.destination")
        case .loading:
            return L10n.string("recording.live_map.route.loading")
        case .offline:
            return L10n.string("recording.live_map.route.offline")
        case .failed:
            return L10n.string("recording.live_map.route.failed")
        case let .estimate(distance, countdown, arrival):
            return String(format: L10n.string("recording.live_map.route.eta"), distance, "\(countdown) · ~\(arrival)")
        }
    }

    /// Distance and the arrival clock stay the row ink. The remaining minutes are red.
    @ViewBuilder
    private var titleLabel: some View {
        if case let .estimate(distance, countdown, arrival) = content {
            HStack(spacing: 0) {
                Text(distance)
                    .foregroundStyle(rowInk)
                Text(" · ")
                    .foregroundStyle(rowInk)
                Text(countdown)
                    .foregroundStyle(Self.countdownInk)
                Text(" · ~\(arrival)")
                    .foregroundStyle(rowInk)
            }
            .font(.system(size: 12 * heightScale, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text(title)
                .font(.system(size: 12 * heightScale, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(rowInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var accessibilityText: String {
        if case let .estimate(distance, countdown, arrival) = content {
            return String(
                format: L10n.string("recording.live_map.route.eta.accessibility"),
                distance,
                countdown,
                arrival
            )
        }
        return title
    }
}

private extension View {
    /// Embedded in the route card: theme capsule. Standalone: the HUD glass capsule is the button.
    @ViewBuilder
    func chipPlate(embedded: Bool) -> some View {
        if embedded {
            background { MilehoundTintCapsule() }
        } else {
            liveMapHUDPlate(Capsule(), interactive: true)
        }
    }
}

/// Sheet-style handle at the foot of a live-map plate. The whole strip is the
/// hit area; the bar itself stays a quiet 36×4 in HUD ink.
struct LiveMapGrabber: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LiveFollowHUDInk.primary(
                    scheme: colorScheme,
                    palette: shellPalette,
                    reduceTransparency: reduceTransparency
                )
                .opacity(0.32)
            )
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
    }
}

private struct RecordingSegmentTrackModifier: ViewModifier {
    var height: CGFloat = 28
    var inset: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .frame(height: height)
            .liveMapHUDPlate(Capsule())
    }
}

private struct RecordingSegmentThumbModifier: ViewModifier {
    var isSelected: Bool
    var morphID: String
    var namespace: Namespace.ID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                RecordingSegmentChrome.label(
                    isSelected: isSelected,
                    palette: shellPalette,
                    scheme: colorScheme,
                    reduceTransparency: reduceTransparency
                )
            )
            .background {
                if isSelected {
                    Capsule()
                        .fill(RecordingSegmentChrome.thumb(for: shellPalette, scheme: colorScheme))
                        .matchedGeometryEffectIfAvailable(
                            stringID: morphID,
                            namespace: namespace,
                            isSource: true
                        )
                }
            }
    }
}

private struct RecordingGlassSurface: View {
    let isPaused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
        let wash = RecordingCardStyle.background(
            isPaused: isPaused,
            palette: shellPalette,
            scheme: colorScheme
        )
        ZStack {
            if reduceTransparency {
                wash
            } else {
                shape.fill(.ultraThinMaterial)
                wash.opacity(colorScheme == .dark ? 0.72 : GlassContrast.recordingWashOpacity)
                shape.fill(Color.white.opacity(colorScheme == .dark ? 0.08 : GlassContrast.recordingFrostOpacity))
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0 : 0.30), lineWidth: 1)
            }
        }
    }
}

private struct RecordingListSurface: View {
    let isPaused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
            .fill(
                RecordingCardStyle.background(
                    isPaused: isPaused,
                    palette: shellPalette,
                    scheme: colorScheme
                )
            )
    }
}

/// Map-mode switches used to match the Pause brick (~64×28). They are 50% larger.
private enum LiveFollowModeSwitchMetrics {
    static let scale: CGFloat = 1.5
    static let trackHeight: CGFloat = 28 * scale
    static let trackInset: CGFloat = 2 * scale
    static let segmentMinHeight: CGFloat = 22 * scale
    static let iconSize: CGFloat = 12 * scale
    static let labelSize: CGFloat = 11 * scale
    static let capsuleWidth: CGFloat = 64 * scale
    static let pairWidth: CGFloat = capsuleWidth * 2 + 6
}

/// Route slot stays put. The card itself is `fraction` of that width and stays centered.
private struct LiveFollowRouteCardWidth: ViewModifier {
    var fraction: CGFloat

    func body(content: Content) -> some View {
        LiveFollowRouteCardWidthLayout(fraction: fraction) {
            content
        }
    }
}

private struct LiveFollowRouteCardWidthLayout: Layout {
    var fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let offered = proposal.width, let child = subviews.first else {
            return subviews.first?.sizeThatFits(.unspecified) ?? .zero
        }
        let childWidth = offered * fraction
        let size = child.sizeThatFits(ProposedViewSize(width: childWidth, height: proposal.height))
        return CGSize(width: offered, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let childWidth = bounds.width * fraction
        let size = child.sizeThatFits(ProposedViewSize(width: childWidth, height: proposal.height))
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.maxY),
            anchor: .bottom,
            proposal: ProposedViewSize(width: childWidth, height: size.height)
        )
    }
}

/// Stats at the leading edge, Pause and Stop at the trailing edge, the middle slot
/// takes the gap between them. The row is never wider than it is offered.
private struct LiveFollowHUDRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = measure(proposal: proposal, subviews: subviews)
        let height = measured.height
        if let offered = proposal.width {
            return CGSize(width: offered, height: height)
        }
        return CGSize(width: measured.stats + measured.switches + measured.controls + spacing * 2, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 3 else { return }
        let measured = measure(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        let statsSize = subviews[0].sizeThatFits(ProposedViewSize(width: measured.stats, height: nil))
        let controlsSize = subviews[2].sizeThatFits(ProposedViewSize(width: measured.controls, height: nil))
        let switchSize = subviews[1].sizeThatFits(ProposedViewSize(width: measured.switches, height: nil))
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(width: statsSize.width, height: statsSize.height)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.maxX, y: bounds.maxY),
            anchor: .bottomTrailing,
            proposal: ProposedViewSize(width: controlsSize.width, height: controlsSize.height)
        )
        let gapMin = bounds.minX + statsSize.width + spacing
        let gapMax = bounds.maxX - controlsSize.width - spacing
        let gap = max(0, gapMax - gapMin)
        let switchX = gapMin + max(0, (gap - measured.switches) / 2)
        subviews[1].place(
            at: CGPoint(x: switchX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(width: measured.switches, height: switchSize.height)
        )
    }

    private func measure(proposal: ProposedViewSize, subviews: Subviews) -> (stats: CGFloat, switches: CGFloat, controls: CGFloat, height: CGFloat) {
        guard subviews.count >= 3 else { return (0, 0, 0, 0) }
        let stats = subviews[0].sizeThatFits(.unspecified)
        let controls = subviews[2].sizeThatFits(.unspecified)
        let available = proposal.width
            ?? (stats.width + subviews[1].sizeThatFits(.unspecified).width + controls.width + spacing * 2)
        let columns = LiveFollowPresentation.hudColumns(
            availableWidth: available,
            statsWidth: stats.width,
            controlsWidth: controls.width,
            spacing: spacing
        )
        let switches = subviews[1].sizeThatFits(ProposedViewSize(width: columns.switches, height: proposal.height))
        let height = max(stats.height, switches.height, controls.height)
        return (columns.stats, columns.switches, columns.controls, height)
    }
}

struct LiveFollowHUDSample: Equatable {
    var duration: String
    var speed: String
    var distance: String
}

/// Live-map cluster: tool capsules, route chip, three stat plates, Pause and Stop.
/// Plates are `LiveMapHUDPlate` glass in one grouping. Pass `stats` in snapshots; nil reads the recording service.
struct LiveFollowHUD<Route: View>: View {
    var tight: Bool
    var isPaused: Bool
    var uses3D: Bool
    var isFollowing: Bool
    var stats: LiveFollowHUDSample?
    var onPause: () -> Void
    var onStop: () -> Void
    var onSelectDimension: (Bool) -> Void
    var onOverview: () -> Void
    var onRecenter: () -> Void
    /// Closed landscape Duo cover: lift Pause and Stop off the trailing corner camera.
    var trailingColumnLift: CGFloat = 0
    @ViewBuilder var route: () -> Route

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        LiveFollowHUDRow {
            statStack
                .fixedSize(horizontal: true, vertical: true)
            VStack(spacing: 6) {
                mapModeSwitches
                route()
            }
            .modifier(LiveFollowRouteCardWidth(fraction: 0.85))
            controlColumn
                .padding(.bottom, trailingColumnLift)
                .fixedSize(horizontal: true, vertical: true)
        }
        .glassEffectGrouping(spacing: 0)
    }

    @ViewBuilder
    private var statStack: some View {
        if let stats {
            LiveFollowHUDStatRow(tight: tight, sample: stats)
        } else {
            LiveFollowHUDLiveStats(tight: tight)
        }
    }

    /// 2D/3D and overview/follow, side by side and centered on the destination card.
    /// One and a half times the old trailing-column size so each half is easier to tap.
    private var mapModeSwitches: some View {
        HStack(spacing: 6) {
            dimensionToggle
                .frame(maxWidth: .infinity)
            followToggle
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: LiveFollowModeSwitchMetrics.pairWidth)
        .frame(maxWidth: .infinity)
        .disabled(isPaused)
        .opacity(isPaused ? 0.38 : 1)
        .allowsHitTesting(!isPaused)
    }

    private var controlColumn: some View {
        VStack(spacing: 4) {
            brickButton(
                title: isPaused ? L10n.resume : L10n.pause,
                systemImage: isPaused ? "play.fill" : "pause.fill",
                tint: GlassSemantic.paused(for: colorScheme),
                identifier: "liveMap.pause"
            ) { onPause() }
            brickButton(
                title: L10n.stop,
                systemImage: "stop.fill",
                tint: GlassSemantic.destructive(for: colorScheme),
                identifier: "liveMap.stop",
                role: .destructive
            ) { onStop() }
        }
    }

    private var dimensionToggle: some View {
        HStack(spacing: 0) {
            dimensionSegment(title: "2D", selected: !uses3D) { onSelectDimension(false) }
            dimensionSegment(title: "3D", selected: uses3D) { onSelectDimension(true) }
        }
        .recordingSegmentTrack(
            height: LiveFollowModeSwitchMetrics.trackHeight,
            inset: LiveFollowModeSwitchMetrics.trackInset
        )
    }

    private var followToggle: some View {
        HStack(spacing: 0) {
            iconSegment(
                systemName: "arrow.up.left.and.arrow.down.right",
                selected: !isFollowing,
                ignoreIfSelected: false,
                accessibilityLabel: L10n.string("recording.live_map.overview")
            ) { onOverview() }
            iconSegment(
                systemName: isFollowing ? "location.north.line.fill" : "location.north.line",
                selected: isFollowing,
                ignoreIfSelected: true,
                accessibilityLabel: L10n.string("recording.live_map.recenter")
            ) { onRecenter() }
        }
        .recordingSegmentTrack(
            height: LiveFollowModeSwitchMetrics.trackHeight,
            inset: LiveFollowModeSwitchMetrics.trackInset
        )
    }

    private func dimensionSegment(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !selected else { return }
            MilehoundHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(.system(size: LiveFollowModeSwitchMetrics.labelSize, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: LiveFollowModeSwitchMetrics.segmentMinHeight)
                .recordingSegmentThumb(isSelected: selected, morphID: "live.dimension", namespace: nil)
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(
            title == "2D"
                ? L10n.string("recording.live_map.switch_2d")
                : L10n.string("recording.live_map.switch_3d")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func iconSegment(
        systemName: String,
        selected: Bool,
        ignoreIfSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if ignoreIfSelected, selected { return }
            MilehoundHaptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: LiveFollowModeSwitchMetrics.iconSize, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: LiveFollowModeSwitchMetrics.segmentMinHeight)
                .recordingSegmentThumb(isSelected: selected, morphID: "live.follow", namespace: nil)
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func brickButton(
        title: String,
        systemImage: String,
        tint: Color,
        identifier: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                brickTitle(title, tint: tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .liveMapHUDPlate(columnShape, interactive: true)
            .contentShape(columnShape)
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityIdentifier(identifier)
    }

    /// Pause, Resume, and Stop share one width, so a longer translation does not
    /// make one brick wider than the other.
    private func brickTitle(_ title: String, tint: Color) -> some View {
        ZStack {
            Text(L10n.pause).hidden()
            Text(L10n.resume).hidden()
            Text(L10n.stop).hidden()
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var columnShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var ink: Color {
        LiveFollowHUDInk.primary(
            scheme: colorScheme,
            palette: shellPalette,
            reduceTransparency: reduceTransparency
        )
    }

}

private struct LiveFollowHUDLiveStats: View {
    var tight: Bool

    @Environment(TripRecordingService.self) private var recordingService

    var body: some View {
        LiveFollowHUDStatRow(
            tight: tight,
            sample: LiveFollowHUDSample(
                duration: DateFormatters.formatDuration(recordingService.displayElapsedTime),
                speed: RecordingAccessibility.speedText(speedMps: recordingService.displaySpeedMps),
                distance: DateFormatters.formatDistance(recordingService.displayDistanceMeters)
            )
        )
    }
}

private struct LiveFollowHUDStatRow: View {
    var tight: Bool
    var sample: LiveFollowHUDSample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            stat(
                icon: "clock.fill",
                label: L10n.duration,
                value: sample.duration,
                identifier: "liveMap.duration"
            )
            stat(
                icon: "speedometer",
                label: L10n.liveMapSpeed,
                value: sample.speed,
                identifier: "liveMap.speed"
            )
            stat(
                icon: "location.fill",
                label: L10n.labelDistance,
                value: sample.distance,
                identifier: "liveMap.distance"
            )
        }
    }

    private func stat(icon: String, label: String, value: String, identifier: String) -> some View {
        LiveFollowHUDStat(tight: tight, icon: icon, label: label, value: value)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
            .accessibilityIdentifier(identifier)
    }
}

private struct LiveFollowHUDStat: View {
    var tight: Bool
    var icon: String
    var label: String
    var value: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let primary = LiveFollowHUDInk.primary(
            scheme: colorScheme,
            palette: shellPalette,
            reduceTransparency: reduceTransparency
        )
        let secondary = LiveFollowHUDInk.secondary(
            scheme: colorScheme,
            palette: shellPalette,
            reduceTransparency: reduceTransparency
        )
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(shellPalette.tintColor(for: colorScheme))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
                .numericTextAnimation(value: value)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liveMapHUDPlate(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ZStack {
        AtmosphericBackground()
        RecordingCardStyle.glassSurface(isPaused: false)
            .frame(height: 140)
            .overlay {
                RecordingCarAnimationView()
                    .padding(.horizontal)
            }
            .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
            .padding()
    }
}
