import Foundation

/// One-time "eyes on the road" reminder before the first manual recording (App Review 1.4.1).
/// Shortcut and automation starts show no UI, so they never ask for it.
struct DrivingSafetyNoticePolicy {
    static let shownKey = "drivingSafetyNoticeShown"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldShow: Bool {
        !defaults.bool(forKey: Self.shownKey)
    }

    func markShown() {
        defaults.set(true, forKey: Self.shownKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.shownKey)
    }
}
