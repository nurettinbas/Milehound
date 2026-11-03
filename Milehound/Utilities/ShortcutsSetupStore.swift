import Foundation

enum ShortcutsSetupTrigger: String, CaseIterable, Identifiable, Sendable {
    case bluetooth
    case carplay
    case wifi

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .carplay: "carplay"
        case .wifi: "wifi"
        }
    }
}

enum ShortcutsSetupChecklistItem: String, CaseIterable, Identifiable, Sendable {
    case personalAutomationEnabled
    case askBeforeRunningOff
    case runShortcutNamed
    case secondVehicleSecondShortcut
    case locationAlways
    case silentStart
    case carplayWireless
    case focusDoesNotBlock
    case returnViaShortcutsLink

    var id: String { rawValue }
}

enum ShortcutsWizardEntry: Equatable, Sendable {
    case start
    case test
    case checklist
}

enum ShortcutsWizardTestOutcome: Equatable, Sendable {
    case noVehicle
    case awaitingConfirmation
    case recordingStarted
    case locationNotAlways
    case idle
}

enum ShortcutsWizardTestClassifier {
    static func classify(
        hasVehicle: Bool,
        awaitingConfirmation: Bool,
        isRecording: Bool,
        locationAlways: Bool
    ) -> ShortcutsWizardTestOutcome {
        guard hasVehicle else { return .noVehicle }
        if awaitingConfirmation { return .awaitingConfirmation }
        if isRecording { return .recordingStarted }
        if !locationAlways { return .locationNotAlways }
        return .idle
    }
}

/// Wizard-only prefs. `UserDefaults.standard` — widgets do not read these keys.
@MainActor
@Observable
final class ShortcutsSetupStore {
    static let shared = ShortcutsSetupStore()
    static let watchDuration: TimeInterval = 10 * 60

    private let defaults: UserDefaults

    var trigger: ShortcutsSetupTrigger?
    var vehicleID: UUID?
    var checkedItemIDs: Set<String>
    var pendingWatchAt: Date?
    var testInFlight: Bool
    var lastTestAt: Date?
    @ObservationIgnored
    private var suppressWatchUntil: Date?

    private enum Key {
        static let trigger = "shortcuts.setup.trigger"
        static let vehicleID = "shortcuts.setup.vehicleID"
        static let checklist = "shortcuts.setup.checklist"
        static let pendingWatchAt = "shortcuts.setup.pendingWatchAt"
        static let testInFlight = "shortcuts.setup.testInFlight"
        static let lastTestAt = "shortcuts.setup.lastTestAt"
    }

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let raw = userDefaults.string(forKey: Key.trigger) {
            trigger = ShortcutsSetupTrigger(rawValue: raw)
        } else {
            trigger = nil
        }
        if let raw = userDefaults.string(forKey: Key.vehicleID), let id = UUID(uuidString: raw) {
            vehicleID = id
        } else {
            vehicleID = nil
        }
        checkedItemIDs = Set(userDefaults.stringArray(forKey: Key.checklist) ?? [])
        let watch = userDefaults.double(forKey: Key.pendingWatchAt)
        pendingWatchAt = watch > 0 ? Date(timeIntervalSince1970: watch) : nil
        testInFlight = userDefaults.bool(forKey: Key.testInFlight)
        let tested = userDefaults.double(forKey: Key.lastTestAt)
        lastTestAt = tested > 0 ? Date(timeIntervalSince1970: tested) : nil
    }

    var hasCompletedTest: Bool { lastTestAt != nil }

    func persistTrigger(_ value: ShortcutsSetupTrigger) {
        trigger = value
        defaults.set(value.rawValue, forKey: Key.trigger)
    }

    func persistVehicleID(_ value: UUID?) {
        vehicleID = value
        if let value {
            defaults.set(value.uuidString, forKey: Key.vehicleID)
        } else {
            defaults.removeObject(forKey: Key.vehicleID)
        }
    }

    func isChecked(_ item: ShortcutsSetupChecklistItem) -> Bool {
        checkedItemIDs.contains(item.rawValue)
    }

    func toggle(_ item: ShortcutsSetupChecklistItem) {
        if checkedItemIDs.contains(item.rawValue) {
            checkedItemIDs.remove(item.rawValue)
        } else {
            checkedItemIDs.insert(item.rawValue)
        }
        defaults.set(Array(checkedItemIDs).sorted(), forKey: Key.checklist)
    }

    func markTestInFlight() {
        testInFlight = true
        defaults.set(true, forKey: Key.testInFlight)
        // Darwin + processPending can both run; do not treat the test as a watch hit.
        suppressWatchUntil = Date().addingTimeInterval(2)
    }

    @discardableResult
    func consumeTestInFlight() -> Bool {
        let value = testInFlight
        guard value else { return false }
        testInFlight = false
        defaults.set(false, forKey: Key.testInFlight)
        return true
    }

    func markTestCompleted(at date: Date = Date()) {
        lastTestAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastTestAt)
    }

    func armExternalStartWatch(at date: Date = Date()) {
        pendingWatchAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Key.pendingWatchAt)
    }

    /// Clears the watch. Returns true when a real start landed inside the 10-minute window.
    @discardableResult
    func consumePendingWatchIfReached(now: Date = Date()) -> Bool {
        if let until = suppressWatchUntil, now < until {
            return false
        }
        guard let started = pendingWatchAt else { return false }
        pendingWatchAt = nil
        defaults.removeObject(forKey: Key.pendingWatchAt)
        let elapsed = now.timeIntervalSince(started)
        return elapsed >= 0 && elapsed <= Self.watchDuration
    }
}
