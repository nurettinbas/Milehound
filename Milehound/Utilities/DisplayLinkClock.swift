import Foundation
import QuartzCore

/// Thin `CADisplayLink` bridge that reports frame deltas on the main actor.
@MainActor
final class DisplayLinkClock {
    private final class Target: NSObject {
        var handler: ((CADisplayLink) -> Void)?

        @objc func step(_ link: CADisplayLink) {
            handler?(link)
        }
    }

    private let target = Target()
    /// `deinit` is nonisolated in Swift 6; `CADisplayLink` is not Sendable, so the
    /// stored link has to be reachable without hopping to the main actor.
    nonisolated(unsafe) private var link: CADisplayLink?
    private var lastPresentationTime: CFTimeInterval = 0

    /// Called each display frame with a clamped `dt` in seconds.
    var onTick: ((TimeInterval) -> Void)?

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        lastPresentationTime = 0
        let displayLink = CADisplayLink(target: target, selector: #selector(Target.step(_:)))
        target.handler = { [weak self] link in
            self?.handle(link)
        }
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        self.link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastPresentationTime = 0
        target.handler = nil
    }

    deinit {
        link?.invalidate()
    }

    /// Steps by the gap between *presentation* times, not between callback times.
    ///
    /// `targetTimestamp` is when the frame being built will actually reach the screen, so
    /// these deltas match what the eye integrates and stay even when a frame is dropped.
    /// Measuring `link.timestamp` instead folds callback-scheduling noise straight into
    /// the motion, which reads as micro-stutter even at a steady 60 fps.
    private func handle(_ link: CADisplayLink) {
        let presentationTime = link.targetTimestamp
        let dt: TimeInterval
        if lastPresentationTime > 0 {
            dt = min(
                max(presentationTime - lastPresentationTime, 0),
                LiveFollowCamera.maxTickDeltaSeconds
            )
        } else {
            dt = link.duration > 0 ? link.duration : (1.0 / 60.0)
        }
        lastPresentationTime = presentationTime
        onTick?(dt)
    }
}
