import Foundation

/// When to push Live Activity snapshots while CarPlay Phone UI owns the dashboard.
enum LiveActivityDashboardPublishPolicy {
    static let minimumUpdateInterval: TimeInterval = 3

    /// CarPlay replaces Now Playing + Live Activity with the in-call UI. Updates
    /// pushed while that tile is hidden are composited on restore (ghosted labels).
    static func isCarPlayCallOcclusion(hasActiveCall: Bool, isCarAudioRoute: Bool) -> Bool {
        hasActiveCall && isCarAudioRoute
    }

    static func shouldPublish(
        dashboardOccluded: Bool,
        force: Bool,
        pauseStateChanged: Bool,
        secondsSinceLastUpdate: TimeInterval?
    ) -> Bool {
        if force || pauseStateChanged { return true }
        if dashboardOccluded { return false }
        guard let secondsSinceLastUpdate else { return true }
        return secondsSinceLastUpdate >= minimumUpdateInterval
    }
}
