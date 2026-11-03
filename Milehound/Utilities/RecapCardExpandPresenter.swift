import os
import SwiftUI

/// Live data for the Recap card that is expanded at the app root.
/// `YearView` writes; the shell reads. Nothing here is stored.
@MainActor
@Observable
final class RecapExpandModel {
    var achievements: [AchievementDisplay] = []
    var routeAggregates: [FrequentRouteAggregate] = []
    var forecast: MonthCostForecast = .empty
    var currencyCode: String = ""
    var badgesAnchor: CGRect = .zero
    var routesAnchor: CGRect = .zero
    var forecastAnchor: CGRect = .zero

    func liveAnchor(for kind: RecapCardExpandKind) -> CGRect {
        switch kind {
        case .achievements: badgesAnchor
        case .routes: routesAnchor
        case .forecast: forecastAnchor
        }
    }
}

enum RecapCardExpandKind: Equatable {
    case achievements
    case routes
    case forecast
}

/// Scale, blur, and anchor math shared by the shell. Tests cover this, not the view.
enum RecapCardExpandGeometry {
    static func scale(isShown: Bool, isClosing: Bool, reduceMotion: Bool) -> CGFloat {
        if reduceMotion || isShown { return 1 }
        return isClosing ? GlassTokens.morphPanelCloseScale : GlassTokens.morphPanelOpenScale
    }

    static func blur(isShown: Bool, reduceMotion: Bool) -> CGFloat {
        if reduceMotion || isShown { return 0 }
        return GlassTokens.morphPanelBlur
    }

    /// Card center in the overlay's own bounds. Unusable frames use the screen center.
    static func unitPoint(for anchor: CGRect, overlayGlobal: CGRect) -> UnitPoint {
        let bounds = overlayGlobal.size
        guard bounds.width > 1, bounds.height > 1,
              AchievementGalleryExpandLayout.hasUsableSource(anchor) else {
            return .center
        }
        let x = min(1, max(0, (anchor.midX - overlayGlobal.minX) / bounds.width))
        let y = min(1, max(0, (anchor.midY - overlayGlobal.minY) / bounds.height))
        return UnitPoint(x: x, y: y)
    }

    /// Shrink toward the card where it is now. If that card is off screen, keep the open anchor.
    static func anchorForClose(frozen: CGRect, live: CGRect, liveIsOnScreen: Bool) -> CGRect {
        guard liveIsOnScreen, AchievementGalleryExpandLayout.hasUsableSource(live) else {
            return frozen
        }
        return live
    }
}

private struct RecapExpandChromeBlurKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Blur for Recap chrome that must not blur a MapKit view. Zero at rest.
    var recapExpandChromeBlur: CGFloat {
        get { self[RecapExpandChromeBlurKey.self] }
        set { self[RecapExpandChromeBlurKey.self] = newValue }
    }
}

/// One expanded Recap card above the tab bar. Same idea as `GlassMorphPanelPresenter`:
/// not a `fullScreenCover`, so the source card can sharpen while the surface shrinks.
@MainActor
@Observable
final class RecapCardExpandPresenter {
    static let shared = RecapCardExpandPresenter()

    struct Presentation: Identifiable {
        let id = UUID()
        let kind: RecapCardExpandKind
        var anchor: CGRect
        let startsShown: Bool
        let model: RecapExpandModel
        let onWillDismiss: () -> Void
        let onDismissed: () -> Void
    }

    private(set) var presentation: Presentation?
    /// Bumped to ask the shell to run the close motion.
    private(set) var closeGeneration = 0
    private(set) var closeFromDrag = false
    /// True once the open spring has settled, so medal clocks stay off during the grow.
    private(set) var isOpenSettled = false
    private var closeArmed = false

    func present(
        kind: RecapCardExpandKind,
        anchor: CGRect,
        startsShown: Bool,
        model: RecapExpandModel,
        onWillDismiss: @escaping () -> Void,
        onDismissed: @escaping () -> Void
    ) {
        guard presentation == nil else { return }
        closeArmed = false
        isOpenSettled = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = Presentation(
                kind: kind,
                anchor: anchor,
                startsShown: startsShown,
                model: model,
                onWillDismiss: onWillDismiss,
                onDismissed: onDismissed
            )
        }
    }

    /// Close button. The shell runs `glassPanelClose` and calls `onWillDismiss` on the panel's delay.
    func requestClose(fromDrag: Bool = false) {
        guard var current = presentation, !closeArmed else { return }
        closeArmed = true
        isOpenSettled = false
        let live = current.model.liveAnchor(for: current.kind)
        current.anchor = RecapCardExpandGeometry.anchorForClose(
            frozen: current.anchor,
            live: live,
            liveIsOnScreen: Self.anchorIsOnScreen(live)
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = current
            closeFromDrag = fromDrag
            closeGeneration += 1
        }
        MilehoundHaptics.selection()
    }

    /// Tab change, lock, or the Year screen leaving. No animation, no leftover surface.
    func dismissImmediately() {
        guard let current = presentation else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = nil
            isOpenSettled = false
            closeArmed = false
        }
        current.onWillDismiss()
        current.onDismissed()
    }

    fileprivate func noteOpened(_ id: UUID) {
        guard presentation?.id == id else { return }
        isOpenSettled = true
    }

    fileprivate func finish(_ id: UUID) {
        guard let current = presentation, current.id == id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = nil
            isOpenSettled = false
            closeArmed = false
        }
        current.onDismissed()
    }

    private static func anchorIsOnScreen(_ source: CGRect) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard let window else { return false }
        return AchievementGalleryExpandLayout.isOnScreenCard(
            source,
            windowBounds: window.bounds,
            topInset: window.safeAreaInsets.top
        )
    }
}

private struct RecapCardExpandHostModifier: ViewModifier {
    @Bindable private var presenter = RecapCardExpandPresenter.shared

    func body(content: Content) -> some View {
        content.overlay {
            if let presentation = presenter.presentation {
                RecapCardExpandShell(
                    id: presentation.id,
                    kind: presentation.kind,
                    anchor: presentation.anchor,
                    startsShown: presentation.startsShown,
                    onWillDismiss: presentation.onWillDismiss,
                    onDismissed: {
                        presenter.finish(presentation.id)
                    }
                ) {
                    recapExpandContent(presentation)
                }
                .id(presentation.id)
                .transition(.identity)
            }
        }
    }

    @ViewBuilder
    private func recapExpandContent(_ presentation: RecapCardExpandPresenter.Presentation) -> some View {
        let close = { RecapCardExpandPresenter.shared.requestClose(fromDrag: false) }
        let swipe = { RecapCardExpandPresenter.shared.requestClose(fromDrag: true) }
        switch presentation.kind {
        case .achievements:
            AchievementGalleryExpandOverlay(
                model: presentation.model,
                onClose: close,
                onSwipeClose: swipe
            )
        case .routes:
            FrequentRoutesExpandOverlay(
                model: presentation.model,
                onClose: close,
                onSwipeClose: swipe
            )
        case .forecast:
            StatsForecastExpandOverlay(
                model: presentation.model,
                onClose: close,
                onSwipeClose: swipe
            )
        }
    }
}

extension View {
    /// Root host for an expanded Recap card. Apply once, next to `glassMorphPanelHost()`.
    func recapCardExpandHost() -> some View {
        modifier(RecapCardExpandHostModifier())
    }
}

/// Full-screen Recap surface that grows and shrinks like `GlassMorphPanel`.
/// Content stays at its final size; only scale, blur, and opacity move.
private struct RecapCardExpandShell<Content: View>: View {
    let id: UUID
    let kind: RecapCardExpandKind
    let anchor: CGRect
    let startsShown: Bool
    let onWillDismiss: () -> Void
    let onDismissed: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isShown: Bool
    @State private var isClosing = false
    @State private var willDismissTask: Task<Void, Never>?
    @Bindable private var presenter = RecapCardExpandPresenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        id: UUID,
        kind: RecapCardExpandKind,
        anchor: CGRect,
        startsShown: Bool,
        onWillDismiss: @escaping () -> Void,
        onDismissed: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.kind = kind
        self.anchor = anchor
        self.startsShown = startsShown
        self.onWillDismiss = onWillDismiss
        self.onDismissed = onDismissed
        self.content = content
        _isShown = State(initialValue: startsShown)
    }

    var body: some View {
        GeometryReader { proxy in
            let overlayGlobal = proxy.frame(in: .global)
            let point = RecapCardExpandGeometry.unitPoint(for: anchor, overlayGlobal: overlayGlobal)
            let scale = RecapCardExpandGeometry.scale(
                isShown: isShown,
                isClosing: isClosing,
                reduceMotion: reduceMotion
            )
            let blur = RecapCardExpandGeometry.blur(isShown: isShown, reduceMotion: reduceMotion)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                surface(blur: blur)
                    .scaleEffect(scale, anchor: point)
                    .opacity(isShown ? 1 : 0)
                    .allowsHitTesting(isShown)
            }
            .environment(\.recapExpandChromeBlur, kind == .routes ? blur : 0)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { presenter.requestClose(fromDrag: false) }
        .task { await runOpen() }
        .onChange(of: presenter.closeGeneration) { _, _ in
            guard presenter.presentation?.id == id else { return }
            close(fromDrag: presenter.closeFromDrag)
        }
        .onDisappear {
            willDismissTask?.cancel()
        }
    }

    /// One blur on the whole surface. The routes map is the exception: MapKit stays sharp
    /// and only the SwiftUI chrome reads `recapExpandChromeBlur`. The modifier stays in the
    /// tree at radius 0 so removing it cannot reset the gallery scroll.
    @ViewBuilder
    private func surface(blur: CGFloat) -> some View {
        if kind == .routes {
            content()
        } else {
            content().blur(radius: blur)
        }
    }

    private func runOpen() async {
        if startsShown {
            presenter.noteOpened(id)
            return
        }
        let state = PerformanceSignposts.signposter.beginInterval("RecapCardExpand")
        try? await Task.sleep(for: MilehoundMotion.glassPanelOpenDelay)
        guard !Task.isCancelled, presenter.presentation?.id == id else {
            PerformanceSignposts.signposter.endInterval("RecapCardExpand", state)
            return
        }
        withAnimation(MilehoundMotion.recapCardExpandOpen(reduceMotion: reduceMotion)) {
            isShown = true
        } completion: {
            PerformanceSignposts.signposter.endInterval("RecapCardExpand", state)
            presenter.noteOpened(id)
        }
    }

    private func close(fromDrag: Bool) {
        guard !isClosing else { return }
        isClosing = true
        let state = PerformanceSignposts.signposter.beginInterval("RecapCardExpand")
        if fromDrag || reduceMotion {
            onWillDismiss()
        } else {
            willDismissTask = Task { @MainActor in
                try? await Task.sleep(for: MilehoundMotion.glassPanelSourceReturnDelay)
                guard !Task.isCancelled, isClosing, presenter.presentation?.id == id else { return }
                onWillDismiss()
            }
        }
        withAnimation(MilehoundMotion.recapCardExpandClose(reduceMotion: reduceMotion)) {
            isShown = false
        } completion: {
            PerformanceSignposts.signposter.endInterval("RecapCardExpand", state)
            guard presenter.presentation?.id == id else { return }
            onDismissed()
        }
    }
}
