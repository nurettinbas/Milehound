import os
import SwiftUI
import UIKit

/// One render-server snapshot of each app window, faded out after a settings change.
/// The new tree draws once underneath. Nothing in the hierarchy is animated.
@MainActor
final class AppearanceTransitionCoordinator {
    static let shared = AppearanceTransitionCoordinator()

    private var snapshots: [UIView] = []
    private var animator: UIViewPropertyAnimator?
    private var generation = 0
    private var signpost: OSSignpostIntervalState?
    /// Lists jump to the top when the window style changes. These are the offsets from before that jump.
    private var scrollPins: [ScrollPin] = []
    private var pinLink: CADisplayLink?
    private var pinUntil: CFTimeInterval = 0
    private let pinRelay = ScrollPinRelay()

    /// Applies `change` with animations off, then fades the previous frame away.
    /// A second call while the fade is running keeps the original snapshot, applies the new value, and restarts the fade.
    func perform(
        excluding hole: CGRect? = nil,
        reduceMotion: Bool = false,
        _ change: () -> Void
    ) {
        let duration = reduceMotion ? 0.2 : TrailhoundMotion.appearanceCrossfadeDuration
        generation += 1
        let generation = generation
        captureScrollPins()

        if snapshots.isEmpty {
            capture(excluding: hole)
            signpost = PerformanceSignposts.signposter.beginInterval("settings.appearanceTransition")
        } else {
            animator?.stopAnimation(false)
            animator = nil
            for snapshot in snapshots {
                snapshot.alpha = 1
            }
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            change()
            AppIconSync.syncWindowStyle(AppSettings.shared.appearanceMode)
        }
        restoreScrollPins()
        startScrollPinning()

        guard !snapshots.isEmpty else {
            endSignpost()
            return
        }

        let fading = snapshots
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.generation else { return }
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut) {
                for snapshot in fading {
                    snapshot.alpha = 0
                }
            }
            animator.addCompletion { [weak self] _ in
                guard let self, generation == self.generation else { return }
                for snapshot in fading {
                    snapshot.removeFromSuperview()
                }
                if self.snapshots.first === fading.first {
                    self.snapshots = []
                }
                self.animator = nil
                self.endSignpost()
            }
            self.animator = animator
            animator.startAnimation()
        }
    }

    private func capture(excluding hole: CGRect?) {
        var taken: [UIView] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where AppIconSync.isAppWindow(window) {
                guard let snapshot = window.snapshotView(afterScreenUpdates: false) else { continue }
                snapshot.frame = window.bounds
                snapshot.isUserInteractionEnabled = false
                if let hole, hole.width > 1, hole.height > 1, hole.intersects(window.bounds) {
                    let path = UIBezierPath(rect: snapshot.bounds)
                    let cutout = UIBezierPath(
                        roundedRect: hole.insetBy(dx: -6, dy: -6),
                        cornerRadius: 18
                    )
                    path.append(cutout)
                    let mask = CAShapeLayer()
                    mask.fillRule = .evenOdd
                    mask.path = path.cgPath
                    snapshot.layer.mask = mask
                }
                window.addSubview(snapshot)
                taken.append(snapshot)
            }
        }
        snapshots = taken
    }

    fileprivate func tickScrollPin() {
        restoreScrollPins()
        guard CACurrentMediaTime() >= pinUntil else { return }
        pinLink?.invalidate()
        pinLink = nil
        for pin in scrollPins {
            pin.observation?.invalidate()
        }
        scrollPins = []
    }

    /// One scrolled list. The observation puts the offset back at the moment UIKit drops it to the top.
    private final class ScrollPin: NSObject {
        let frame: CGRect
        let offset: CGPoint
        var corrections = 0
        var applying = false
        var observation: NSKeyValueObservation?

        init(frame: CGRect, offset: CGPoint) {
            self.frame = frame
            self.offset = offset
        }

        func bind(to scroll: UIScrollView) {
            guard observation == nil || bound !== scroll else { return }
            observation?.invalidate()
            bound = scroll
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self, weak scroll] _, _ in
                guard let self, let scroll else { return }
                MainActor.assumeIsolated {
                    AppearanceTransitionCoordinator.shared.correct(self, on: scroll)
                }
            }
        }

        private weak var bound: UIScrollView?
    }

    /// Keeps a scrolled-away offset. A second tap after the list has already jumped must not replace it with the top.
    private func captureScrollPins() {
        let fresh = scrollViews().compactMap { scroll -> ScrollPin? in
            guard !isNearTop(scroll) else { return nil }
            let frame = scroll.convert(scroll.bounds, to: nil)
            guard frame.width > 40, frame.height > 40 else { return nil }
            return ScrollPin(frame: frame, offset: scroll.contentOffset)
        }
        guard !fresh.isEmpty else { return }
        scrollPins = fresh
    }

    private func startScrollPinning() {
        guard !scrollPins.isEmpty else { return }
        pinUntil = CACurrentMediaTime() + 0.6
        guard pinLink == nil else { return }
        let link = CADisplayLink(target: pinRelay, selector: #selector(ScrollPinRelay.tick))
        link.add(to: .main, forMode: .common)
        pinLink = link
    }

    private func restoreScrollPins() {
        guard !scrollPins.isEmpty else { return }
        let scrolls = scrollViews()
        for pin in scrollPins {
            guard let scroll = nearestScroll(in: scrolls, to: pin.frame) else { continue }
            pin.bind(to: scroll)
            correct(pin, on: scroll)
        }
    }

    private func correct(_ pin: ScrollPin, on scroll: UIScrollView) {
        guard !pin.applying, pin.corrections < 12 else { return }
        if scroll.isDragging || scroll.isTracking {
            pin.corrections = 12
            return
        }
        guard !scroll.isDecelerating else { return }
        guard isNearTop(scroll) else { return }
        guard scroll.contentSize.height > pin.offset.y + 1
                || scroll.contentSize.width > pin.offset.x + 1 else { return }
        pin.applying = true
        scroll.setContentOffset(pin.offset, animated: false)
        pin.applying = false
        pin.corrections += 1
    }

    private func nearestScroll(in scrolls: [UIScrollView], to frame: CGRect) -> UIScrollView? {
        let match = scrolls.min { frameDistance($0, frame) < frameDistance($1, frame) }
        guard let match, frameDistance(match, frame) < 48 else { return nil }
        return match
    }

    private func frameDistance(_ scroll: UIScrollView, _ frame: CGRect) -> CGFloat {
        let current = scroll.convert(scroll.bounds, to: nil)
        let dx = current.midX - frame.midX
        let dy = current.midY - frame.midY
        return abs(dx) + abs(dy)
    }

    private func isNearTop(_ scroll: UIScrollView) -> Bool {
        let y = scroll.contentOffset.y
        let top = -scroll.adjustedContentInset.top
        return min(abs(y - top), abs(y)) < 24 && abs(scroll.contentOffset.x) < 24
    }

    private func scrollViews() -> [UIScrollView] {
        var found: [UIScrollView] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where AppIconSync.isAppWindow(window) {
                collectScrollViews(in: window, into: &found)
            }
        }
        return found
    }

    private func collectScrollViews(in view: UIView, into found: inout [UIScrollView]) {
        if snapshots.contains(where: { $0 === view }) { return }
        if let scroll = view as? UIScrollView {
            found.append(scroll)
        }
        for child in view.subviews {
            collectScrollViews(in: child, into: &found)
        }
    }

    private func endSignpost() {
        guard let signpost else { return }
        PerformanceSignposts.signposter.endInterval("settings.appearanceTransition", signpost)
        self.signpost = nil
    }
}

private final class ScrollPinRelay: NSObject {
    @objc func tick() {
        MainActor.assumeIsolated {
            AppearanceTransitionCoordinator.shared.tickScrollPin()
        }
    }
}
