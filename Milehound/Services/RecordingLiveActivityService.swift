import ActivityKit
import Foundation
import UIKit

// Vehicle mark is passed as systemImage / scaleX / App Group revision token only.
@MainActor
enum RecordingLiveActivityService {
    private static let logCategory: DevLogCategory = .widget
    private static var lastUpdateAt: Date?
    private static var lastPublishedIsPaused: Bool?
    private static var dashboardOccluded = false
    private static var operationChain: Task<Void, Never>?

    /// Snapshot for deferred recreate when `Activity.request` is blocked in background.
    private struct PendingRestart {
        var startedAt: Date
        var elapsed: TimeInterval
        var distanceMeters: Double
        var currentSpeedKmh: Int
        var isPaused: Bool
        var vehicleSystemImage: String
        var vehicleSymbolScaleX: Double
        var vehiclePhotoRevision: String?
    }

    private static var pendingRestart: PendingRestart?
    private static var didLogDeferredRestart = false

    /// Ends orphan Live Activities left over from a prior process (e.g. Xcode debug restart).
    static func reconcileAfterLaunch(hasActiveSession: Bool) async {
        await runSerially {
            guard !hasActiveSession else { return }
            guard !Activity<TripRecordingAttributes>.activities.isEmpty else { return }
            await endAllImmediately()
        }
        clearPendingRestart()
    }

    static func start(
        startedAt: Date,
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        currentSpeedKmh: Int = 0,
        isPaused: Bool = false,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoRevision: String? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        clearPendingRestart()
        enqueue {
            await endAllImmediately()
            await requestActivity(
                startedAt: startedAt,
                elapsed: elapsed,
                distanceMeters: distanceMeters,
                currentSpeedKmh: currentSpeedKmh,
                isPaused: isPaused,
                vehicleSystemImage: vehicleSystemImage,
                vehicleSymbolScaleX: vehicleSymbolScaleX,
                vehiclePhotoRevision: vehiclePhotoRevision,
                logMessage: "Live Activity started"
            )
            lastUpdateAt = nil
            lastPublishedIsPaused = isPaused
        }
    }

    /// Starts (or confirms) a Live Activity on the *current* task.
    /// Required when invoking from a `LiveActivityIntent`: background
    /// `Activity.request` is only authorized on that intent's `perform()` task,
    /// not on a detached/enqueued Task (which hits `visibility` and fails until
    /// the app is later opened).
    static func startOnCurrentTask(
        startedAt: Date,
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        currentSpeedKmh: Int = 0,
        isPaused: Bool = false,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoRevision: String? = nil
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        clearPendingRestart()
        await operationChain?.value
        if !Activity<TripRecordingAttributes>.activities.isEmpty { return }
        await endAllImmediately()
        await requestActivity(
            startedAt: startedAt,
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            currentSpeedKmh: currentSpeedKmh,
            isPaused: isPaused,
            vehicleSystemImage: vehicleSystemImage,
            vehicleSymbolScaleX: vehicleSymbolScaleX,
            vehiclePhotoRevision: vehiclePhotoRevision,
            logMessage: "Live Activity started (intent)"
        )
        lastUpdateAt = nil
        lastPublishedIsPaused = isPaused
    }

    /// Re-creates the Live Activity if recording is active but the system dismissed it.
    /// Background recreate is deferred — ActivityKit rejects `Activity.request` when not foreground.
    static func ensureActiveIfNeeded(
        startedAt: Date,
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int,
        isPaused: Bool,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoRevision: String? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        enqueue {
            await dedupeActivitiesIfNeeded()
            guard Activity<TripRecordingAttributes>.activities.isEmpty else {
                clearPendingRestart()
                return
            }

            let snapshot = PendingRestart(
                startedAt: startedAt,
                elapsed: elapsed,
                distanceMeters: distanceMeters,
                currentSpeedKmh: currentSpeedKmh,
                isPaused: isPaused,
                vehicleSystemImage: vehicleSystemImage,
                vehicleSymbolScaleX: vehicleSymbolScaleX,
                vehiclePhotoRevision: vehiclePhotoRevision
            )

            guard UIApplication.shared.applicationState == .active else {
                storePendingRestart(snapshot)
                return
            }

            DevLog.shared.log(logCategory, "Live Activity missing during recording; restarting", level: .warning)
            await requestActivity(
                startedAt: snapshot.startedAt,
                elapsed: snapshot.elapsed,
                distanceMeters: snapshot.distanceMeters,
                currentSpeedKmh: snapshot.currentSpeedKmh,
                isPaused: snapshot.isPaused,
                vehicleSystemImage: snapshot.vehicleSystemImage,
                vehicleSymbolScaleX: snapshot.vehicleSymbolScaleX,
                vehiclePhotoRevision: snapshot.vehiclePhotoRevision,
                logMessage: "Live Activity restarted"
            )
            clearPendingRestart()
            lastUpdateAt = nil
            lastPublishedIsPaused = isPaused
        }
    }

    /// Retries a deferred background recreate once the app is foreground again.
    static func retryPendingRestartIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            clearPendingRestart()
            return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        guard let snapshot = pendingRestart else { return }
        enqueue {
            await dedupeActivitiesIfNeeded()
            guard Activity<TripRecordingAttributes>.activities.isEmpty else {
                clearPendingRestart()
                return
            }
            DevLog.shared.log(logCategory, "Live Activity missing during recording; restarting", level: .warning)
            await requestActivity(
                startedAt: snapshot.startedAt,
                elapsed: snapshot.elapsed,
                distanceMeters: snapshot.distanceMeters,
                currentSpeedKmh: snapshot.currentSpeedKmh,
                isPaused: snapshot.isPaused,
                vehicleSystemImage: snapshot.vehicleSystemImage,
                vehicleSymbolScaleX: snapshot.vehicleSymbolScaleX,
                vehiclePhotoRevision: snapshot.vehiclePhotoRevision,
                logMessage: "Live Activity restarted"
            )
            clearPendingRestart()
            lastUpdateAt = nil
            lastPublishedIsPaused = snapshot.isPaused
        }
    }

    /// CarPlay Phone UI is covering the dashboard tile — skip snapshot pushes until it returns.
    static func setDashboardOccluded(_ occluded: Bool) {
        let wasOccluded = dashboardOccluded
        dashboardOccluded = occluded
        if wasOccluded != occluded {
            DevLog.shared.log(
                logCategory,
                occluded ? "Live Activity CarPlay dashboard occluded" : "Live Activity CarPlay dashboard revealed"
            )
        }
        if wasOccluded, !occluded {
            lastUpdateAt = nil
        }
    }

    static func update(
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int,
        isPaused: Bool,
        force: Bool = false,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoRevision: String? = nil
    ) {
        let pauseStateChanged = lastPublishedIsPaused != isPaused
        let now = Date()
        let secondsSinceLastUpdate = lastUpdateAt.map { now.timeIntervalSince($0) }
        guard LiveActivityDashboardPublishPolicy.shouldPublish(
            dashboardOccluded: dashboardOccluded,
            force: force,
            pauseStateChanged: pauseStateChanged,
            secondsSinceLastUpdate: secondsSinceLastUpdate
        ) else { return }
        lastUpdateAt = now
        lastPublishedIsPaused = isPaused

        let state = TripRecordingAttributes.ContentState(
            elapsedSeconds: Int(elapsed.rounded()),
            distanceMeters: distanceMeters,
            currentSpeedKmh: currentSpeedKmh,
            isPaused: isPaused,
            vehicleSystemImage: vehicleSystemImage,
            vehicleSymbolScaleX: vehicleSymbolScaleX,
            vehiclePhotoRevision: vehiclePhotoRevision,
            effectiveStartedAt: Date().addingTimeInterval(-elapsed)
        )
        let content = ActivityContent(state: state, staleDate: nil)

        enqueue {
            await dedupeActivitiesIfNeeded()
            guard !Activity<TripRecordingAttributes>.activities.isEmpty else { return }
            for activity in Activity<TripRecordingAttributes>.activities {
                // Live Activity intent already painted pause/resume; a second near-identical
                // update restarts the control morph and reads as stutter.
                if Self.isRedundantPublish(current: activity.content.state, next: state) {
                    continue
                }
                await activity.update(content)
            }
        }
    }

    /// True when a publish would not change what the banner shows in a meaningful way.
    private static func isRedundantPublish(
        current: TripRecordingAttributes.ContentState,
        next: TripRecordingAttributes.ContentState
    ) -> Bool {
        guard current.isPaused == next.isPaused,
              current.elapsedSeconds == next.elapsedSeconds,
              current.currentSpeedKmh == next.currentSpeedKmh,
              current.vehicleSystemImage == next.vehicleSystemImage,
              current.vehicleSymbolScaleX == next.vehicleSymbolScaleX,
              current.vehiclePhotoRevision == next.vehiclePhotoRevision,
              abs(current.distanceMeters - next.distanceMeters) < 0.5 else {
            return false
        }
        return true
    }

    static func stop() {
        lastUpdateAt = nil
        lastPublishedIsPaused = nil
        clearPendingRestart()
        LiveActivityVehicleMarkStore.clear()
        RecordingVehicleMarkSnapshot.clearCompactPNGCache()
        enqueue {
            await endAllImmediately()
        }
    }

    private static func storePendingRestart(_ snapshot: PendingRestart) {
        pendingRestart = snapshot
        guard !didLogDeferredRestart else { return }
        didLogDeferredRestart = true
        DevLog.shared.log(logCategory, "Live Activity restart deferred (background)")
    }

    private static func clearPendingRestart() {
        pendingRestart = nil
        didLogDeferredRestart = false
    }

    private static func enqueue(_ operation: @MainActor @escaping () async -> Void) {
        let waitFor = operationChain
        operationChain = Task { @MainActor in
            await waitFor?.value
            await operation()
        }
    }

    private static func runSerially(_ operation: @MainActor @escaping () async -> Void) async {
        let waitFor = operationChain
        let task = Task { @MainActor in
            await waitFor?.value
            await operation()
        }
        operationChain = task
        await task.value
    }

    private static func requestActivity(
        startedAt: Date,
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int,
        isPaused: Bool,
        vehicleSystemImage: String,
        vehicleSymbolScaleX: Double,
        vehiclePhotoRevision: String?,
        logMessage: String
    ) async {
        let attributes = TripRecordingAttributes(startedAt: startedAt)
        let state = TripRecordingAttributes.ContentState(
            elapsedSeconds: Int(elapsed.rounded()),
            distanceMeters: distanceMeters,
            currentSpeedKmh: currentSpeedKmh,
            isPaused: isPaused,
            vehicleSystemImage: vehicleSystemImage,
            vehicleSymbolScaleX: vehicleSymbolScaleX,
            vehiclePhotoRevision: vehiclePhotoRevision,
            effectiveStartedAt: startedAt
        )
        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
            DevLog.shared.log(logCategory, logMessage)
            await dedupeActivitiesIfNeeded()
        } catch {
            // Background `AppIntent` (non-LiveActivityIntent) hits `.visibility`; the
            // Shortcuts path retries via `startOnCurrentTask` on the intent task.
            let level: DevLogLevel = (error as? ActivityAuthorizationError) == .visibility
                ? .warning
                : .error
            DevLog.shared.log(
                logCategory,
                "Live Activity start failed: \(error.localizedDescription)",
                level: level
            )
        }
    }

    private static func dedupeActivitiesIfNeeded() async {
        let activities = Activity<TripRecordingAttributes>.activities
        guard activities.count > 1 else { return }
        DevLog.shared.log(
            logCategory,
            "Live Activity duplicate count=\(activities.count); ending extras",
            level: .warning
        )
        for activity in activities.dropLast() {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func endAllImmediately() async {
        for activity in Activity<TripRecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
