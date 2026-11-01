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
/// The card is already a saturated palette wash, so a tinted selection pill
/// disappears into it. The selected segment is an opaque white thumb; its label
/// uses the palette’s light chrome (deep ink). Unselected labels stay white.
enum RecordingSegmentChrome {
    static let thumb = Color.white

    static func trackFill(for scheme: ColorScheme) -> Color {
        Color.white.opacity(scheme == .dark ? 0.14 : 0.20)
    }

    static func trackRim(for scheme: ColorScheme) -> Color {
        Color.white.opacity(scheme == .dark ? 0.22 : 0.42)
    }

    static func label(isSelected: Bool, palette: ShellPalette) -> Color {
        if isSelected {
            return palette.chromeColor(for: .light)
        }
        return Color.white.opacity(0.78)
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

/// Live-map top chip for the planned route. Same `glassChrome(cornerRadius: 14)` capsule and
/// caption ink as the recording status chip; the whole chip is the button.
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

    @Environment(\.colorScheme) private var colorScheme

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
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassChrome(cornerRadius: 14)
            .contentShape(Capsule())
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
                .foregroundStyle(GlassText.primary(for: colorScheme))
        case .loading:
            ProgressView()
                .controlSize(.mini)
        case .offline:
            Image(systemName: "wifi.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlassText.primary(for: colorScheme))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlassSemantic.paused(for: colorScheme))
        case .estimate:
            Image(systemName: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlassText.primary(for: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(2)
            .frame(height: 33)
            .background {
                Capsule()
                    .fill(RecordingSegmentChrome.trackFill(for: colorScheme))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                RecordingSegmentChrome.trackRim(for: colorScheme),
                                lineWidth: 1
                            )
                    }
            }
    }
}

private struct RecordingSegmentThumbModifier: ViewModifier {
    var isSelected: Bool
    var morphID: String
    var namespace: Namespace.ID?

    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                RecordingSegmentChrome.label(isSelected: isSelected, palette: shellPalette)
            )
            .background {
                if isSelected {
                    Capsule()
                        .fill(RecordingSegmentChrome.thumb)
                        .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
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
