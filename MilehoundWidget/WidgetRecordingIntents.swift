@preconcurrency import AppIntents
import Foundation

// MARK: - Home-screen widget (AppIntent — lightweight, extension-local)

struct HomeWidgetPauseRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "shortcut.pause.title"
    static let openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControlBridge.handleHomeWidgetPausePressed()
        return .result()
    }
}

struct HomeWidgetResumeRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "shortcut.resume.title"
    static let openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControlBridge.handleHomeWidgetResumePressed()
        return .result()
    }
}

struct HomeWidgetStopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "shortcut.stop.title"
    static let openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControlBridge.handleHomeWidgetStopPressed()
        return .result()
    }
}

// MARK: - Live Activity / Dynamic Island (LiveActivityIntent)

struct WidgetStopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "shortcut.stop.title"
    static let openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingControlBridge.handleLiveActivityStopPressed()
        return .result()
    }
}

/// Single stable control slot — UI morphs pause↔play (YouTube Music style) without swapping buttons.
///
/// The state the button was rendered with travels as a parameter instead of being re-read from the
/// App Group: it keeps the toggle aligned with what the user actually tapped, and keeps a cfprefsd
/// read off the path that holds the button in its pressed state.
struct WidgetTogglePauseResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "shortcut.pause.title"
    static let openAppWhenRun = false
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Paused")
    var wasPaused: Bool

    init() {
        wasPaused = false
    }

    init(wasPaused: Bool) {
        self.wasPaused = wasPaused
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if wasPaused {
            await RecordingControlBridge.handleLiveActivityResumePressed()
        } else {
            await RecordingControlBridge.handleLiveActivityPausePressed()
        }
        return .result()
    }
}
