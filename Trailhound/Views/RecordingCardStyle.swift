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
/// The plates are pale frozen frost, so the selected segment can carry the palette
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

/// Compact map plate. Material lets the road show through. No live `glassEffect`.
/// Snapshots force the frozen frost so the blur does not change between runtimes.
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

extension View {
    /// Frost track for a two-option control on the recording HUD. No `glassEffect`.
    func recordingSegmentTrack() -> some View {
        modifier(RecordingSegmentTrackModifier())
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
/// No destination: "Destination". Otherwise remaining distance and estimated arrival, or the route state.
struct RecordingRouteChip: View {
    enum Content: Equatable {
        case setDestination
        case loading
        case offline
        case failed
        case estimate(distance: String, arrival: String)
    }

    let content: Content
    let action: () -> Void
    /// Live HUD: the row fills the shared route card.
    var wide: Bool = false
    /// The route card draws the plate. The row itself stays flat.
    var embedded: Bool = false

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

    var body: some View {
        Button {
            TrailhoundHaptics.selection()
            action()
        } label: {
            HStack(spacing: 4) {
                leading
                Text(title)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, wide ? 12 : 8)
            .padding(.vertical, embedded ? 8 : (wide ? 5 : 3))
            .frame(maxWidth: wide ? .infinity : nil)
            .background {
                if !embedded {
                    LiveMapHUDPlate(shape: Capsule())
                }
            }
            .contentShape(embedded ? AnyShape(Rectangle()) : AnyShape(Capsule()))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .tint(ink)
        case .offline:
            Image(systemName: "wifi.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlassSemantic.paused(for: colorScheme))
        case .estimate:
            Image(systemName: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
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
        case let .estimate(distance, arrival):
            return String(format: L10n.string("recording.live_map.route.eta"), distance, arrival)
        }
    }

    private var accessibilityText: String {
        if case let .estimate(distance, arrival) = content {
            return String(format: L10n.string("recording.live_map.route.eta.accessibility"), distance, arrival)
        }
        return title
    }
}

private struct RecordingSegmentTrackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(2)
            .frame(height: 28)
            .background {
                LiveMapHUDPlate(shape: Capsule())
            }
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

struct LiveFollowHUDSample: Equatable {
    var duration: String
    var speed: String
    var distance: String
}

/// Live-map cluster: tool capsules, route chip, three stat plates, Pause and Stop.
/// Plates are frozen map frost. Pass `stats` in snapshots; nil reads the recording service.
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
    @ViewBuilder var route: () -> Route

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            statStack
                .fixedSize(horizontal: true, vertical: true)
            route()
                .frame(minWidth: 0, maxWidth: .infinity)
            controlColumn
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statStack: some View {
        if let stats {
            LiveFollowHUDStatRow(tight: tight, sample: stats)
        } else {
            LiveFollowHUDLiveStats(tight: tight)
        }
    }

    private var controlColumn: some View {
        VStack(spacing: 4) {
            dimensionToggle
                .disabled(isPaused)
                .opacity(isPaused ? 0.38 : 1)
                .allowsHitTesting(!isPaused)
            followToggle
                .disabled(isPaused)
                .opacity(isPaused ? 0.38 : 1)
                .allowsHitTesting(!isPaused)
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
        .recordingSegmentTrack()
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
        .recordingSegmentTrack()
    }

    private func dimensionSegment(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !selected else { return }
            TrailhoundHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 22)
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
            TrailhoundHaptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 22)
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
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { LiveMapHUDPlate(shape: columnShape) }
            .contentShape(columnShape)
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityIdentifier(identifier)
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
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            LiveMapHUDPlate(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
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
