import Foundation
import UIKit

/// Controls the system idle timer (auto-lock / screensaver).
@MainActor
protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerControlling {}

/// Ref-counted keep-awake for full-screen live follow (Maps-style).
///
/// Only the live follow cover should retain this. Recording alone does not keep
/// the screen on — that matches intentional background-GPS behavior.
@MainActor
final class ScreenIdleLock {
    static let shared = ScreenIdleLock()

    private let controller: IdleTimerControlling
    private(set) var retainCount = 0

    init(controller: IdleTimerControlling = UIApplication.shared) {
        self.controller = controller
    }

    func retain() {
        retainCount += 1
        if retainCount == 1 {
            controller.isIdleTimerDisabled = true
        }
    }

    func release() {
        guard retainCount > 0 else { return }
        retainCount -= 1
        if retainCount == 0 {
            controller.isIdleTimerDisabled = false
        }
    }

    /// Test helper — drops all retains and restores the idle timer.
    func resetForTesting() {
        retainCount = 0
        controller.isIdleTimerDisabled = false
    }
}
