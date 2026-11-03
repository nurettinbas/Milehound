import ActivityKit
@preconcurrency import CoreFoundation
@preconcurrency import Foundation
import WidgetKit

public enum RecordingControlBridge {
    public static let appGroupSuiteName = "group.com.milehound.app"

    private struct UncheckedDefaults: @unchecked Sendable {
        let value: UserDefaults
    }

    private static let uncheckedSharedDefaults = UncheckedDefaults(
        value: UserDefaults(suiteName: appGroupSuiteName) ?? .standard
    )

    /// Cached app-group defaults; avoids repeated `UserDefaults(suiteName:)` calls that spam cfprefsd
    /// logs and add cfprefsd round trips to the Live Activity intent's critical path.
    public static func sharedDefaults() -> UserDefaults {
        uncheckedSharedDefaults.value
    }

    /// Pulls cross-process App Group writes (widget extension → app) into this process before reads.
    public static func refreshSharedDefaultsFromDisk() {
        CFPreferencesAppSynchronize(appGroupSuiteName as CFString)
    }

    public static func hasPendingStopRequest() -> Bool {
        sharedDefaults().bool(forKey: Keys.requestStop)
    }

    public static func hasPendingPauseRequest() -> Bool {
        sharedDefaults().bool(forKey: Keys.requestPause)
    }

    public static func hasPendingResumeRequest() -> Bool {
        sharedDefaults().bool(forKey: Keys.requestResume)
    }

    private static func stampRequest(_ key: String, at timestampKey: String, in defaults: UserDefaults) {
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
        defaults.set(true, forKey: key)
    }

    private static func commitSharedDefaultsToDisk() {
        CFPreferencesAppSynchronize(appGroupSuiteName as CFString)
    }

    public enum Keys {
        public static let requestStop = "recording.requestStop"
        public static let requestStart = "recording.requestStart"
        public static let requestPause = "recording.requestPause"
        public static let requestResume = "recording.requestResume"
        public static let requestStartAt = "recording.requestStartAt"
        public static let requestStopAt = "recording.requestStopAt"
        public static let requestPauseAt = "recording.requestPauseAt"
        public static let requestResumeAt = "recording.requestResumeAt"
        public static let isActive = "recording.isActive"
        public static let isPaused = "recording.isPaused"
        public static let elapsed = "recording.elapsed"
        public static let startedAt = "recording.startedAt"
        /// Persisted so widget/intent stop after process death can finalize the correct orphan.
        public static let activeTripID = "recording.activeTripID"
        public static let distance = "recording.distance"
        public static let weekDistance = "stats.weekDistance"
        public static let monthDistance = "stats.monthDistance"
        /// When true, external start (Shortcuts/Siri) opens the app for confirmation.
        public static let confirmExternalRecordingStart = "confirmExternalRecordingStart"
    }

    /// Home-screen / lock-screen widget timeline payload from App Group defaults.
    public struct RecordingWidgetSnapshot: Equatable, Sendable {
        public var isRecording: Bool
        public var isPaused: Bool
        public var elapsed: TimeInterval
        public var distanceMeters: Double
        public var weekDistanceMeters: Double
        public var monthDistanceMeters: Double
        /// When actively recording, widget extrapolates elapsed locally from this anchor.
        public var recordingStartedAt: Date?

        public var showsRecordingControls: Bool { isRecording || isPaused }
        /// Pause control when actively recording; Resume when paused.
        public var showsResumeControl: Bool { isPaused }

        /// Elapsed duration for widget display at `now` — ticks locally while recording.
        public func elapsed(at now: Date = Date()) -> TimeInterval {
            if isRecording, !isPaused, let recordingStartedAt {
                return max(0, now.timeIntervalSince(recordingStartedAt))
            }
            return elapsed
        }
    }

    public static func recordingWidgetSnapshot(
        from defaults: UserDefaults? = nil
    ) -> RecordingWidgetSnapshot {
        let defaults = defaults ?? sharedDefaults()
        let startedAtTimestamp = defaults.double(forKey: Keys.startedAt)
        return RecordingWidgetSnapshot(
            isRecording: defaults.bool(forKey: Keys.isActive),
            isPaused: defaults.bool(forKey: Keys.isPaused),
            elapsed: defaults.double(forKey: Keys.elapsed),
            distanceMeters: defaults.double(forKey: Keys.distance),
            weekDistanceMeters: defaults.double(forKey: Keys.weekDistance),
            monthDistanceMeters: defaults.double(forKey: Keys.monthDistance),
            recordingStartedAt: startedAtTimestamp > 0
                ? Date(timeIntervalSince1970: startedAtTimestamp)
                : nil
        )
    }

    private enum DarwinNotification: CaseIterable {
        case start
        case stop
        case pause
        case resume

        var name: String {
            switch self {
            case .start: "com.milehound.recording.requestStart"
            case .stop: "com.milehound.recording.requestStop"
            case .pause: "com.milehound.recording.requestPause"
            case .resume: "com.milehound.recording.requestResume"
            }
        }

        var cfName: CFNotificationName {
            CFNotificationName(name as CFString)
        }

        var cfString: CFString {
            name as CFString
        }
    }

    private static func registerDarwinObserver(
        _ notification: DarwinNotification,
        observer: UnsafeRawPointer,
        callback: @escaping CFNotificationCallback
    ) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            callback,
            notification.cfString,
            nil,
            .deliverImmediately
        )
    }

    private static func postDarwinNotification(_ notification: DarwinNotification) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notification.cfName,
            nil,
            nil,
            true
        )
    }

    public static func registerDarwinStartObserver(
        observer: UnsafeRawPointer,
        callback: @escaping CFNotificationCallback
    ) {
        registerDarwinObserver(.start, observer: observer, callback: callback)
    }

    public static func registerDarwinStopObserver(
        observer: UnsafeRawPointer,
        callback: @escaping CFNotificationCallback
    ) {
        registerDarwinObserver(.stop, observer: observer, callback: callback)
    }

    public static func registerDarwinPauseObserver(
        observer: UnsafeRawPointer,
        callback: @escaping CFNotificationCallback
    ) {
        registerDarwinObserver(.pause, observer: observer, callback: callback)
    }

    public static func registerDarwinResumeObserver(
        observer: UnsafeRawPointer,
        callback: @escaping CFNotificationCallback
    ) {
        registerDarwinObserver(.resume, observer: observer, callback: callback)
    }

    @MainActor
    public static func endAllLiveActivitiesImmediately() async {
        for activity in Activity<TripRecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    public static func updateLiveActivities(isPaused: Bool) async {
        for activity in Activity<TripRecordingAttributes>.activities {
            var state = activity.content.state
            guard state.isPaused != isPaused else { continue }
            state.isPaused = isPaused
            // Match in-app pause snapshot so the follow-up app publish is a no-op
            // (avoids a second paint that restarts the pause/resume morph).
            if isPaused {
                state.currentSpeedKmh = 0
            } else {
                state.effectiveStartedAt = Date().addingTimeInterval(-TimeInterval(state.elapsedSeconds))
            }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private static let homeWidgetKind = "MilehoundWidget"
    private static let lockScreenWidgetKind = "MilehoundLockScreenWidget"

    /// Requests an immediate home-screen widget repaint. Non-blocking; safe inside `perform()`.
    public static func reloadHomeScreenWidgetTimelinesImmediately() {
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: lockScreenWidgetKind)
    }

    @MainActor
    private static func scheduleLiveActivitySideEffects(
        liveActivityPaused: Bool? = nil,
        endLiveActivities: Bool = false
    ) {
        Task { @MainActor(priority: .userInitiated) in
            if let liveActivityPaused {
                await updateLiveActivities(isPaused: liveActivityPaused)
            }
            if endLiveActivities {
                await endAllLiveActivitiesImmediately()
            }
        }
    }

    public static func requestStartFromControlSurface() {
        let defaults = sharedDefaults()
        defaults.set(false, forKey: Keys.requestStop)
        defaults.set(false, forKey: Keys.requestPause)
        defaults.set(false, forKey: Keys.requestResume)
        stampRequest(Keys.requestStart, at: Keys.requestStartAt, in: defaults)
        commitSharedDefaultsToDisk()
        postDarwinNotification(.start)
    }

    public static func requestStopFromControlSurface() {
        let defaults = sharedDefaults()
        defaults.set(false, forKey: Keys.requestPause)
        defaults.set(false, forKey: Keys.requestResume)
        stampRequest(Keys.requestStop, at: Keys.requestStopAt, in: defaults)
        defaults.set(false, forKey: Keys.isActive)
        defaults.set(false, forKey: Keys.isPaused)
        commitSharedDefaultsToDisk()
        postDarwinNotification(.stop)
    }

    public static func requestPauseFromControlSurface() {
        let defaults = sharedDefaults()
        defaults.set(false, forKey: Keys.requestResume)
        stampRequest(Keys.requestPause, at: Keys.requestPauseAt, in: defaults)
        // Keep session active — widget shows Resume only when isActive && isPaused.
        defaults.set(true, forKey: Keys.isActive)
        defaults.set(true, forKey: Keys.isPaused)
        commitSharedDefaultsToDisk()
        postDarwinNotification(.pause)
    }

    public static func requestResumeFromControlSurface() {
        let defaults = sharedDefaults()
        defaults.set(false, forKey: Keys.requestPause)
        stampRequest(Keys.requestResume, at: Keys.requestResumeAt, in: defaults)
        defaults.set(true, forKey: Keys.isActive)
        defaults.set(false, forKey: Keys.isPaused)
        commitSharedDefaultsToDisk()
        postDarwinNotification(.resume)
    }

    // MARK: - Home-screen widget (AppIntent — stays in extension, no LA handoff stall)

    @MainActor
    public static func handleHomeWidgetStopPressed() {
        requestStopFromControlSurface()
        reloadHomeScreenWidgetTimelinesImmediately()
        scheduleLiveActivitySideEffects(endLiveActivities: true)
    }

    @MainActor
    public static func handleHomeWidgetPausePressed() {
        requestPauseFromControlSurface()
        reloadHomeScreenWidgetTimelinesImmediately()
        scheduleLiveActivitySideEffects(liveActivityPaused: true)
    }

    @MainActor
    public static func handleHomeWidgetResumePressed() {
        requestResumeFromControlSurface()
        reloadHomeScreenWidgetTimelinesImmediately()
        scheduleLiveActivitySideEffects(liveActivityPaused: false)
    }

    // MARK: - Live Activity / Dynamic Island (LiveActivityIntent — paint LA in `perform()`)

    @MainActor
    public static func handleLiveActivityStopPressed() async {
        requestStopFromControlSurface()
        await endAllLiveActivitiesImmediately()
        reloadHomeScreenWidgetTimelinesImmediately()
    }

    @MainActor
    public static func handleLiveActivityPausePressed() async {
        requestPauseFromControlSurface()
        await updateLiveActivities(isPaused: true)
        reloadHomeScreenWidgetTimelinesImmediately()
    }

    @MainActor
    public static func handleLiveActivityResumePressed() async {
        requestResumeFromControlSurface()
        await updateLiveActivities(isPaused: false)
        reloadHomeScreenWidgetTimelinesImmediately()
    }
}

public enum MilehoundDeepLink {
    public static let startRecording = URL(string: "milehound://recording/start")!

    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        guard url.scheme == "milehound" else { return false }
        if url.host == "open" || url.host == "stats" || url.host == "trip" {
            return true
        }
        guard url.host == "recording" else { return false }
        switch url.path {
        case "/start":
            RecordingControlBridge.requestStartFromControlSurface()
            return true
        default:
            return false
        }
    }
}
