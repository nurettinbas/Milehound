import CoreLocation
import SwiftUI
import UIKit

enum TrailhoundMotion {
    static let snappy = Animation.snappy(duration: 0.28)
    /// Day/night knob, sun-to-crescent cut, cloud, and stars. One spring, no loop.
    static let dayNightSwitch = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Full-window snapshot fade after a theme, language, or text-size change.
    static let appearanceCrossfadeDuration: TimeInterval = 0.28
    /// Settings row title and subtitle swap. Shorter than the window fade.
    static let settingsLabelSwap = Animation.easeOut(duration: 0.18)
    /// Tab content switch.
    static let tabSwitch = Animation.easeOut(duration: 0.15)
    /// Notifications playback switch thumb — short snappy slide, no mush.
    static let recordingToggle = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.22)
    static let cardSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Recording card ↔ list row morph / stop settle.
    static let recordingMorph = Animation.spring(response: 0.26, dampingFraction: 0.9)
    /// Recording card entrance — card rise + car drive-in.
    static let coldOpenFade = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// Cold-launch hound intro budgets. Frames are Core Animation, not SwiftUI.
    static let launchIntroDuration: TimeInterval = 1.715
    static let launchIntroLowPowerDuration: TimeInterval = 1.19
    static let launchIntroReduceMotionDuration: TimeInterval = 0.25
    static let launchIntroSkipDuration: TimeInterval = 0.25
    /// One gallop stride of the launch hound’s legs (`LaunchIntroHoundRig`).
    static let launchIntroGallopStride: TimeInterval = 0.42
    /// App underneath settles from this scale to 1 as the plate closes into the icon.
    static let launchIntroContentSettleScale: CGFloat = 1.04
    /// Same curve and length as the plate closing, so the app and the icon move as one.
    static let launchIntroContentSettle = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.56)
    /// Soft sheet rise for TripDetail panel.
    static let sheetRise = Animation.spring(response: 0.55, dampingFraction: 0.88)
    /// Trip detail: panel recedes + camera opens as one beat (no sheet modal).
    static let mapExpand = Animation.timingCurve(0.18, 0.82, 0.16, 1.0, duration: 1.40)
    /// Return to details — still slow, slightly quicker so it feels decisive.
    static let mapCollapse = Animation.timingCurve(0.22, 0.80, 0.24, 1.0, duration: 1.10)
    /// Map clarity / dark→clear open.
    static let mapClear = Animation.easeOut(duration: 0.9)
    /// Pin pop with a bit of overshoot.
    static let pinPop = Animation.spring(response: 0.36, dampingFraction: 0.72)
    /// Toast card rise from the bottom — soft overshoot, matches pinPop energy.
    static let toastSpring = Animation.spring(response: 0.44, dampingFraction: 0.76)
    /// Toast card exit — quick ease down and fade.
    static let toastDismiss = Animation.easeIn(duration: 0.22)
    /// `VehicleInspectLoader` magnifier pass over the car (one way; the loop autoreverses).
    static let inspectSweepDuration: TimeInterval = 1.6
    static let inspectSweep = Animation.easeInOut(duration: inspectSweepDuration)
    /// `VehicleInspectLoader` road dash drift — linear so the loop has no seam.
    static let inspectRoadDrift = Animation.linear(duration: 0.9)
    /// Recording card live-map CTA popout (label expands from the map chip).
    static let liveMapHintPop = Animation.spring(response: 0.48, dampingFraction: 0.72)
    /// Live-map CTA collapse back to the icon chip.
    static let liveMapHintCollapse = Animation.spring(response: 0.40, dampingFraction: 0.86)
    /// Vehicle photo framing settle (rotate / expand inline controls).
    static let photoSettle = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Side actions spawn from the photo hero.
    static let photoActionsReveal = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Source dialog → camera/gallery: sheet stretches upward as one filled surface.
    static let photoSheetExpand = Animation.spring(response: 1.1, dampingFraction: 0.86)
    /// Live follow open/close hero flight + map opacity (keep map + hero in lockstep).
    static let liveFollowReveal = Animation.easeInOut(duration: 1.05)
    /// Alias used by close / shared call sites.
    static let liveFollowExpand = liveFollowReveal
    /// Hero ↔ MapKit puck crossfade at the end of open / start of close.
    static let liveFollowHandoff = Animation.easeInOut(duration: 0.34)
    static let liveFollowHandoffDuration: TimeInterval = 0.34
    /// Gallery/camera fade inside the grown card.
    static let photoSheetReveal = Animation.easeOut(duration: 0.56)
    /// Pure fade — no offset (offset reads as a new sheet rising).
    static var photoSheetRevealTransition: AnyTransition { .opacity }
    /// Avatar remove → empty add control (soft shrink out / rise in).
    static let photoRemove = Animation.spring(response: 0.4, dampingFraction: 0.84)
    /// Camera-style glass panel grows from 40 % with a blur dissolve (~0.2 s), overshoots slightly, settles (~0.45 s).
    static let glassPanelOpen = Animation.spring(response: 0.72, dampingFraction: 0.8)
    /// Panel shrinks to 55 % and blurs away on an accelerating curve (~0.2 s).
    static let glassPanelClose = Animation.timingCurve(0.32, 0, 0.67, 0, duration: 0.22)
    /// The source control dissolves before the panel grows and sharpens back as it closes.
    static let glassPanelSourceDissolve = Animation.easeOut(duration: 0.12)
    /// Source dissolve leads the panel by this much on open.
    static let glassPanelOpenDelay: Duration = .milliseconds(90)
    /// After a tap-to-close the source starts to sharpen this far into the shrink, so no gap shows.
    /// A drag-to-close has already carried the panel off the source, so it returns at once.
    static let glassPanelSourceReturnDelay: Duration = .milliseconds(120)

    static func glassPanelOpen(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : glassPanelOpen
    }

    static func glassPanelClose(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeIn(duration: 0.16) : glassPanelClose
    }

    static func glassPanelSourceDissolve(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : glassPanelSourceDissolve
    }

    /// Recap card expand uses the glass-panel open. No separate spring.
    static func recapCardExpandOpen(reduceMotion: Bool) -> Animation {
        glassPanelOpen(reduceMotion: reduceMotion)
    }

    /// Recap card collapse uses the glass-panel close.
    static func recapCardExpandClose(reduceMotion: Bool) -> Animation {
        glassPanelClose(reduceMotion: reduceMotion)
    }

    /// Soft rise (fade + slight upward settle).
    static var softRiseTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity
        )
    }

    /// Soft slide in from the leading edge.
    static var softSlideFromLeadingTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: -28)),
            removal: .opacity
        )
    }

    /// Scale in 0.92 → 1 (no overshoot).
    static var softScaleInTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92)),
            removal: .opacity
        )
    }

    /// Rise from below (buttons / bottom chrome).
    static var softRiseFromBottomTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)),
            removal: .opacity
        )
    }

    /// Photo hero swap: remove shrinks away; empty add rises in.
    static var photoHeroTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.88))
                .combined(with: .offset(y: 10)),
            removal: .opacity
                .combined(with: .scale(scale: 0.82))
                .combined(with: .offset(y: -8))
        )
    }

    /// Edit / Change / Delete spawn from the photo (leading = toward hero).
    static var photoActionsTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.55))
                .combined(with: .offset(x: -18)),
            removal: .opacity
                .combined(with: .scale(scale: 0.7))
                .combined(with: .offset(x: -12))
        )
    }

    static func photoActionsRevealAnimation(delay: Double, reduceMotion: Bool) -> Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.12).delay(delay * 0.25)
        }
        return photoActionsReveal.delay(delay)
    }

    /// Curtain / clip-reveal transition (progress 0 → 1).
    static func clipRevealTransition(edge: Edge = .top) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ClipRevealEffect(progress: 0, edge: edge),
                identity: ClipRevealEffect(progress: 1, edge: edge)
            ),
            removal: .opacity
        )
    }

    static func cardAppearTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.98)),
            removal: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.96))
        )
    }

    static func recapPage(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.86)
    }

    /// Full-bleed scene push — next from trailing, back from leading.
    static func recapSceneTransition(reduceMotion: Bool, advancing: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insert: Edge = advancing ? .trailing : .leading
        let remove: Edge = advancing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insert).combined(with: .opacity),
            removal: .move(edge: remove).combined(with: .opacity)
        )
    }

    /// Overlay copy / medals settle in from below as the scene pushes.
    static func recapCopyTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 28))
                .combined(with: .scale(scale: 0.92)),
            removal: .opacity
                .combined(with: .offset(y: -16))
                .combined(with: .scale(scale: 1.04))
        )
    }

    /// Intro title card uses a staged fade, not the copy push (year has its own scale).
    static func recapIntroCopyTransition(reduceMotion _: Bool) -> AnyTransition {
        .opacity
    }

    static func recapCountUp(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 1.15)
    }

    static func recapHold(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    static func recapSegmentFill(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: RecapStoryPlayback.pageDuration)
    }

    static func badgeUnlock(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
    }

    /// Swap one unlock card for the next — short scale, not a long crossfade.
    static func badgeUnlockCardTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.86)),
            removal: .opacity.combined(with: .scale(scale: 0.94))
        )
    }

    /// Stats badges card grows up and down from its own frame (not a sheet).
    static func badgeCardExpand(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.76, dampingFraction: 0.90)
    }

    /// Fold, rotate, and pane changes. Same spring as the badge card.
    /// Reduce Motion uses a short fade instead of a flight.
    static func layoutReflow(reduceMotion: Bool) -> Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return badgeCardExpand(reduceMotion: false)
    }

    /// Wide-book care form. Covers the trailing pane from the trailing edge.
    /// Back and Save run the same move in reverse.
    static func panePush(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.22, 0.86, 0.18, 1, duration: 0.42)
    }

    static func panePushCover(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .trailing)
        )
    }

    /// The list under a pane push. It shifts off the leading edge as the form covers it.
    static func panePushRecede(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .leading),
            removal: .move(edge: .leading)
        )
    }

    /// Gallery content fade after the card has grown — no vertical offset.
    static func badgeGalleryAppear(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    static func fadeScaleTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .opacity.combined(with: .scale(scale: 0.98))
    }

    /// Toast card: rise from below and settle; leave downward with fade.
    static func toastTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 28))
                .combined(with: .scale(scale: 0.90, anchor: .bottom)),
            removal: .opacity
                .combined(with: .offset(y: 16))
                .combined(with: .scale(scale: 0.94, anchor: .bottom))
        )
    }
}

/// Title-card choreography for the year recap intro page. Times are page-local seconds.
enum RecapIntroReveal {
    static let kickerStart: TimeInterval = 0
    static let kickerEnd: TimeInterval = 0.35
    static let yearStart: TimeInterval = 0.15
    static let yearEnd: TimeInterval = 0.80
    static let whisperStart: TimeInterval = 0.55
    static let whisperEnd: TimeInterval = 1.20
    static let yearScaleFrom: CGFloat = 0.92
    static let settledElapsed: TimeInterval = whisperEnd

    static func kickerOpacity(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        Double(eased(progress(elapsed: elapsed, start: kickerStart, end: kickerEnd, reduceMotion: reduceMotion)))
    }

    static func yearOpacity(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        Double(eased(progress(elapsed: elapsed, start: yearStart, end: yearEnd, reduceMotion: reduceMotion)))
    }

    static func yearScale(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        let p = eased(progress(elapsed: elapsed, start: yearStart, end: yearEnd, reduceMotion: reduceMotion))
        return yearScaleFrom + (1 - yearScaleFrom) * p
    }

    static func whisperOpacity(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        Double(eased(progress(elapsed: elapsed, start: whisperStart, end: whisperEnd, reduceMotion: reduceMotion)))
    }

    static func progress(
        elapsed: TimeInterval,
        start: TimeInterval,
        end: TimeInterval,
        reduceMotion: Bool
    ) -> CGFloat {
        guard !reduceMotion else { return 1 }
        guard end > start else { return elapsed >= end ? 1 : 0 }
        let t = (elapsed - start) / (end - start)
        return CGFloat(min(1, max(0, t)))
    }

    static func eased(_ linear: CGFloat) -> CGFloat {
        1 - pow(1 - linear, 3)
    }
}

@MainActor
enum TrailhoundHaptics {
    static func recordingStarted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func recordingPaused() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func recordingResumed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func recordingStopped() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func pairingSucceeded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func badgeUnlocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// One soft tap as the cold-launch road hands off to the app.
    static func launchSettled() {
        guard !UITestSupport.isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func destructive() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// One haptic phrase per toast. Compound styles stagger so the impact is not swallowed by the notification.
    static func playToast(_ style: ToastHapticStyle) {
        switch style {
        case .success:
            playImpact(.soft, then: .success)
        case .destructive:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .merge:
            playImpact(.medium, then: .success)
        case .automation:
            playImpact(.rigid, then: .success)
        case .personalRecord:
            playImpact(.heavy, then: .success)
        }
    }

    private static func playImpact(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle,
        then notification: UINotificationFeedbackGenerator.FeedbackType
    ) {
        let impact = UIImpactFeedbackGenerator(style: style)
        impact.prepare()
        impact.impactOccurred()
        let note = UINotificationFeedbackGenerator()
        note.prepare()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(45))
            note.notificationOccurred(notification)
        }
    }
}

private struct NumericTextAnimationModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: value)
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion, !UITestSupport.isEnabled {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.35),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                }
            }
    }
}

/// One-shot diagonal sun/glint for vehicle photo hero — overlay removed when finished.
private struct PhotoEntranceGlintModifier: ViewModifier {
    let cornerRadius: CGFloat
    let glintID: String
    var isEnabled: Bool = true
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    @State private var finished = false
    @State private var playedID: String?

    private let duration: TimeInterval = 0.85

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled, playsMotion, !finished {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.45),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geometry.size.width * 0.42, height: geometry.size.height * 1.55)
                        .rotationEffect(.degrees(22))
                        .offset(x: -geometry.size.width + phase * geometry.size.width * 2.15)
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .onAppear(perform: playIfNeeded)
            .onChange(of: glintID) { _, _ in
                finished = false
                phase = 0
                playedID = nil
                playIfNeeded()
            }
            .onChange(of: isEnabled) { _, _ in
                playIfNeeded()
            }
    }

    private var playsMotion: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    private func playIfNeeded() {
        guard isEnabled else {
            finished = true
            return
        }
        guard playsMotion else {
            finished = true
            onFinished?()
            return
        }
        guard playedID != glintID else { return }
        playedID = glintID
        finished = false
        phase = 0

        Task { @MainActor in
            withAnimation(.easeOut(duration: duration)) {
                phase = 1
            }
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 40))
            finished = true
            phase = 0
            onFinished?()
        }
    }
}

/// One-shot diagonal glint for list avatars — overlay removed after the sweep.
private struct PhotoIdleShineModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shineID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    @State private var finished = false
    @State private var playedID: String?

    private let sweepDuration: TimeInterval = 0.75

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion, !finished {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.4),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geometry.size.width * 0.42, height: geometry.size.height * 1.55)
                        .rotationEffect(.degrees(22))
                        .offset(x: -geometry.size.width + phase * geometry.size.width * 2.15)
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .task(id: shineID) {
                guard !reduceMotion else {
                    finished = true
                    return
                }
                guard playedID != shineID else { return }
                playedID = shineID
                finished = false
                phase = 0

                var hasher = Hasher()
                hasher.combine(shineID)
                let staggerMs = abs(hasher.finalize()) % 400
                try? await Task.sleep(for: .milliseconds(staggerMs))
                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: sweepDuration)) {
                    phase = 1
                }
                try? await Task.sleep(for: .milliseconds(Int(sweepDuration * 1000) + 40))
                guard !Task.isCancelled else { return }

                finished = true
                phase = 0
            }
    }
}

/// Curtain wipe — reveals content by expanding a clip from an edge.
struct ClipRevealEffect: ViewModifier, Animatable {
    var progress: CGFloat
    var edge: Edge

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = min(1, max(0, progress))
        let p = max(clamped, 0.001)
        let horizontal = (edge == .leading || edge == .trailing)
        content
            .mask(alignment: clipAlignment) {
                Rectangle()
                    .scaleEffect(
                        x: horizontal ? p : 1,
                        y: horizontal ? 1 : p,
                        anchor: clipAnchor
                    )
            }
            .opacity(Double(min(1, clamped * 1.2)))
    }

    private var clipAnchor: UnitPoint {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        @unknown default: .top
        }
    }

    private var clipAlignment: Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        @unknown default: .top
        }
    }
}

extension View {
    func clipReveal(progress: CGFloat, edge: Edge = .top) -> some View {
        modifier(ClipRevealEffect(progress: progress, edge: edge))
    }

    func numericTextAnimation<V: Equatable>(value: V) -> some View {
        modifier(NumericTextAnimationModifier(value: value))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    /// One-shot entrance glint; overlay is removed after the sweep finishes.
    func photoEntranceGlint(
        cornerRadius: CGFloat,
        id: String,
        onFinished: (() -> Void)? = nil
    ) -> some View {
        glassEntranceGlint(cornerRadius: cornerRadius, id: id, onFinished: onFinished)
    }

    /// One-shot glass sheen for Stats / photo heroes. Reduce Motion and UI tests skip it.
    func glassEntranceGlint(
        cornerRadius: CGFloat,
        id: String,
        isEnabled: Bool = true,
        onFinished: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PhotoEntranceGlintModifier(
                cornerRadius: cornerRadius,
                glintID: id,
                isEnabled: isEnabled,
                onFinished: onFinished
            )
        )
    }

    /// One-shot photo shine for list cells; overlay is removed after the sweep.
    func photoIdleShine(cornerRadius: CGFloat, id: String) -> some View {
        modifier(PhotoIdleShineModifier(cornerRadius: cornerRadius, shineID: id))
    }

    func trailhoundCardTransition(reduceMotion: Bool) -> some View {
        transition(TrailhoundMotion.cardAppearTransition(reduceMotion: reduceMotion))
    }

    @ViewBuilder
    func matchedGeometryEffectIfAvailable(
        id: UUID?,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let id, let namespace {
            matchedGeometryEffect(id: id, in: namespace, properties: .frame, isSource: isSource)
        } else {
            self
        }
    }

    @ViewBuilder
    func matchedGeometryEffectIfAvailable(
        stringID: String?,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let stringID, let namespace {
            matchedGeometryEffect(id: stringID, in: namespace, properties: .frame, isSource: isSource)
        } else {
            self
        }
    }

    /// The control that opens a `GlassMorphPanel` blurs away while the panel is up.
    func glassMorphPanelSource(isHidden: Bool) -> some View {
        blur(radius: isHidden ? 8 : 0)
            .opacity(isHidden ? 0 : 1)
            .scaleEffect(isHidden ? 0.96 : 1)
    }
}

/// Soft press feedback for bordered controls (Pause / Resume, etc.).
struct SoftPressBorderedButtonStyle: PrimitiveButtonStyle {
    var reduceMotion: Bool = false
    var pressedScale: CGFloat = 0.96
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SoftPressBorderedPrimitive(
            configuration: configuration,
            reduceMotion: reduceMotion,
            pressedScale: pressedScale,
            prominent: prominent
        )
    }
}

private struct SoftPressBorderedPrimitive: View {
    let configuration: PrimitiveButtonStyleConfiguration
    var reduceMotion: Bool
    var pressedScale: CGFloat
    var prominent: Bool

    @GestureState private var isPressed = false

    var body: some View {
        borderedBody
            .scaleEffect((isPressed && !reduceMotion) ? pressedScale : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
    }

    @ViewBuilder
    private var borderedBody: some View {
        if prominent {
            BorderedProminentButtonStyle()
                .makeBody(configuration: configuration)
        } else {
            BorderedButtonStyle()
                .makeBody(configuration: configuration)
        }
    }
}

// MARK: - Route path reveal

enum RoutePathReveal {
    /// Returns a polyline prefix for `progress` in `0...1`, with an interpolated tip.
    static func prefix(
        _ coordinates: [CLLocationCoordinate2D],
        progress: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }
        let clamped = min(1, max(0, progress))
        if clamped <= 0 { return [coordinates[0]] }
        if clamped >= 1 { return coordinates }

        let segmentCount = coordinates.count - 1
        let exact = Double(segmentCount) * clamped
        let index = min(segmentCount - 1, Int(exact))
        let fraction = exact - Double(index)
        var result = Array(coordinates.prefix(index + 1))
        let start = coordinates[index]
        let end = coordinates[index + 1]
        result.append(
            CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                longitude: start.longitude + (end.longitude - start.longitude) * fraction
            )
        )
        return result
    }

    static func tip(
        of coordinates: [CLLocationCoordinate2D],
        progress: Double
    ) -> CLLocationCoordinate2D? {
        prefix(coordinates, progress: progress).last
    }

    /// Fraction along the point index range closest to `coordinate` (0...1).
    static func progress(
        nearestTo coordinate: CLLocationCoordinate2D,
        in coordinates: [CLLocationCoordinate2D]
    ) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in coordinates.enumerated() {
            let dLat = point.latitude - coordinate.latitude
            let dLon = point.longitude - coordinate.longitude
            let distance = dLat * dLat + dLon * dLon
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return Double(bestIndex) / Double(coordinates.count - 1)
    }
}

// MARK: - Soft pulse ring (Core Animation)

/// Compact Core Animation glow ring — used for recording tab badge and similar live signals.
struct SoftPulseRing: UIViewRepresentable {
    var color: UIColor
    var isActive: Bool
    var reduceMotion: Bool

    func makeUIView(context: Context) -> SoftPulseRingView {
        SoftPulseRingView()
    }

    func updateUIView(_ uiView: SoftPulseRingView, context: Context) {
        uiView.apply(color: color, isActive: isActive && !reduceMotion)
    }
}

final class SoftPulseRingView: UIView {
    private let ringLayer = CAShapeLayer()
    private var isActive = false
    private var ringColor: UIColor = .systemRed

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 2
        ringLayer.opacity = 0
        layer.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = ringLayer.lineWidth
        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isActive {
            startPulseIfNeeded()
        }
    }

    func apply(color: UIColor, isActive: Bool) {
        ringColor = color
        ringLayer.strokeColor = color.withAlphaComponent(0.7).cgColor
        self.isActive = isActive

        if isActive {
            isHidden = false
            startPulseIfNeeded()
        } else {
            stopPulse()
            ringLayer.opacity = 0
            ringLayer.transform = CATransform3DIdentity
            isHidden = true
        }
    }

    private func startPulseIfNeeded() {
        guard ringLayer.animation(forKey: "softPulse") == nil else { return }
        ringLayer.opacity = 0.4
        ringLayer.transform = CATransform3DIdentity

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.25
        opacity.toValue = 0.75

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.18

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 1.7
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        ringLayer.add(group, forKey: "softPulse")
    }

    private func stopPulse() {
        ringLayer.removeAnimation(forKey: "softPulse")
    }
}
