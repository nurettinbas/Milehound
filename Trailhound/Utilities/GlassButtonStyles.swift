import SwiftUI

private struct TrailhoundProminentButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.buttonStyle(
            LightChromeProminentButtonStyle(
                chrome: shellPalette.glassReadabilityTint(for: colorScheme),
                tint: shellPalette.tintColor(for: colorScheme),
                reduceMotion: reduceMotion
            )
        )
    }
}

/// Saturated shell: tint pill + white label.
private struct LightChromeProminentButtonStyle: ButtonStyle {
    var chrome: Color
    var tint: Color
    var reduceMotion: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(tint)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                    }
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect((configuration.isPressed && !reduceMotion && isEnabled) ? 0.97 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: configuration.isPressed)
    }
}

/// Saturated theme capsule. White label sits on it. Shared by the compact CTA and the live-map destination row.
struct TrailhoundTintCapsule: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Capsule(style: .continuous)
            .fill(shellPalette.tintColor(for: colorScheme))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
            }
    }
}

/// Soft tint wave that rolls out from a collapsed control's edge, then rests — says "tap me" without a badge.
/// Draws outside the control and never takes hits. Reduce Motion shows nothing.
private struct TrailhoundTapRipple<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var travel: Double { 1.6 }
    private static var period: Double { 2.8 }
    private static var spread: CGFloat { 9 }

    func body(content: Content) -> some View {
        content.background {
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.period) / Self.travel
                    let progress = CGFloat(min(t, 1))
                    let eased = 1 - (1 - progress) * (1 - progress)
                    shape
                        .stroke(shellPalette.tintColor(for: colorScheme), lineWidth: 1.5)
                        .padding(-Self.spread * eased)
                        .opacity(0.55 * Double(1 - progress))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Tap-affordance wave around a collapsed glass control. Pass the control's own shape.
    func trailhoundTapRipple<S: Shape>(_ shape: S) -> some View {
        modifier(TrailhoundTapRipple(shape: shape))
    }
}

/// Intrinsic-width tint capsule for in-card CTAs (recap Play). Same recipe in Light and Dark.
private struct TrailhoundCompactProminentChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .fixedSize(horizontal: true, vertical: false)
            .background { TrailhoundTintCapsule() }
            .padding(6)
            .contentShape(Capsule(style: .continuous))
    }
}

private struct TrailhoundGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.buttonStyle(.bordered)
        } else if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .tint(shellPalette.shellTint(for: .light))
        } else {
            content
                .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
                .tint(shellPalette.shellTint(for: .light))
        }
    }
}

/// Solid system-red fill lives in `makeBody` so the capsule — not the title glyphs — is the control.
private struct TrailhoundDestructiveButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(compact ? 0.8 : 1)
            .padding(.horizontal, compact ? 12 : 0)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 32 : 34)
            .fixedSize(horizontal: compact, vertical: false)
            .background {
                Capsule(style: .continuous)
                    .fill(GlassSemantic.notificationBadge)
            }
            .contentShape(Capsule(style: .continuous))
            .compositingGroup()
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

/// `.plain` hit-tests Text / SF Symbol glyphs only. Same look; the **label bounds** fire the action.
struct GlassPlainHitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

extension View {
    func trailhoundProminentButton() -> some View {
        modifier(TrailhoundProminentButtonModifier())
    }

    /// Compact tint capsule (~32 pt visual, 44 pt hit). Intrinsic width — never truncates.
    func trailhoundCompactProminentButton() -> some View {
        modifier(TrailhoundCompactProminentChromeModifier())
    }

    func trailhoundGlassButton() -> some View {
        modifier(TrailhoundGlassButtonModifier())
    }

    /// Solid system-red fill — never glass-prominent, never Appearance tint.
    func trailhoundDestructiveButton() -> some View {
        buttonStyle(TrailhoundDestructiveButtonStyle())
    }

    /// Same red capsule, intrinsic width, slightly smaller title. For a label beside other content.
    func trailhoundCompactDestructiveButton() -> some View {
        buttonStyle(TrailhoundDestructiveButtonStyle(compact: true))
    }

    /// Icon-only control in a compact field (search clear). Expands the glyph to a hittable square.
    func glassGlyphHit(minSide: CGFloat = 32) -> some View {
        frame(minWidth: minSide, minHeight: minSide, alignment: .center)
            .contentShape(Rectangle())
    }

    /// Scale-press for a whole glass / Stats card. Not a second chrome recipe.
    func trailhoundCardPress() -> some View {
        buttonStyle(.trailhoundCardPress)
    }
}

/// Soft 0.96 press on a tappable card. Reduce Motion keeps scale at 1.
struct TrailhoundCardPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPlainHitButtonStyle {
    static var glassPlainHit: GlassPlainHitButtonStyle { GlassPlainHitButtonStyle() }
}

extension ButtonStyle where Self == TrailhoundCardPressButtonStyle {
    static var trailhoundCardPress: TrailhoundCardPressButtonStyle {
        TrailhoundCardPressButtonStyle()
    }
}
