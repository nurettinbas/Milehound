import Foundation
import SwiftData
import UserNotifications

enum TripNotificationService {
    /// userInfo key carried on notifications that should deep-link somewhere on tap.
    static let actionUserInfoKey = "milehound.action"
    static let tripIDUserInfoKey = "milehound.tripID"
    static let targetUserInfoKey = "milehound.target"
    /// Action value that opens the Pairing tab when the notification is tapped.
    static let openPairingAction = "openPairing"
    static let openTripAction = "openTrip"
    static let openAchievementsAction = "openAchievements"
    static let openRecapAction = "openRecap"

    static func requestAuthorizationIfNeeded() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// - Returns: `true` when the rich system banner was posted immediately (start place already known).
    @discardableResult
    static func notifyTripStarted(tripID: UUID, startSummary: String) -> Bool {
        let body = startedBody(startSummary: startSummary)
        let identifier = startedNotificationID(tripID: tripID)
        // Always land in the inbox immediately.
        Task { @MainActor in
            AppNotificationStore.shared.record(
                kind: .tripStarted,
                title: L10n.tripStartedTitle,
                body: body,
                tripID: tripID,
                action: openTripAction,
                target: tripID.uuidString
            )
        }
        // Prefer posting the system banner once we know "From …". If place is already
        // known, post now; otherwise wait briefly for the first GPS/place refresh.
        if body != L10n.tripStartedBody {
            postSystemNotification(
                identifier: identifier,
                title: L10n.tripStartedTitle,
                body: body,
                action: openTripAction,
                tripID: tripID
            )
            return true
        }
        scheduleDeferredStartedPush(tripID: tripID)
        return false
    }

    /// Updates the inbox trip-started row when start place becomes available (first fix / trip end).
    /// - Parameter postBanner: When true, posts/replaces the system banner so it matches inbox
    ///   (used while recording). Pass false at trip end so we don't re-alert "Trip started".
    @MainActor
    static func refreshTripStartedBody(tripID: UUID, startSummary: String, postBanner: Bool = true) {
        let body = startedBody(startSummary: startSummary)
        guard body != L10n.tripStartedBody else { return }
        let bodyChanged = AppNotificationStore.shared.updateTripStartedBody(tripID: tripID, body: body)
        cancelDeferredStartedPush(tripID: tripID)
        // Same body as notifyTripStarted (or inbox row not written yet) — don't re-alert.
        guard postBanner, bodyChanged else { return }
        postSystemNotification(
            identifier: startedNotificationID(tripID: tripID),
            title: L10n.tripStartedTitle,
            body: body,
            action: openTripAction,
            tripID: tripID
        )
    }

    private static func startedBody(startSummary: String) -> String {
        if startSummary.isEmpty || startSummary == "—" {
            return L10n.tripStartedBody
        }
        return String(format: L10n.string("trip.started.rich.body"), startSummary)
    }

    private static func startedNotificationID(tripID: UUID) -> String {
        "milehound.trip.started.\(tripID.uuidString)"
    }

    private static func deferredStartedPushID(tripID: UUID) -> String {
        "milehound.trip.started.deferred.\(tripID.uuidString)"
    }

    /// Fallback: if place never resolves, still show the generic started banner after a short wait.
    private static func scheduleDeferredStartedPush(tripID: UUID) {
        let identifier = deferredStartedPushID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = L10n.tripStartedTitle
        content.body = L10n.tripStartedBody
        content.sound = .default
        content.userInfo = tripUserInfo(tripID: tripID, action: openTripAction, inboxRecorded: true)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2.5, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelDeferredStartedPush(tripID: UUID) {
        let identifier = deferredStartedPushID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func postSystemNotification(
        identifier: String,
        title: String,
        body: String,
        action: String? = nil,
        tripID: UUID? = nil,
        target: String? = nil,
        skipWhenYearSelected: Bool = false
    ) {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            if skipWhenYearSelected, TabSelection.shared.selectedTab == .year { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = tripUserInfo(
                tripID: tripID,
                action: action,
                target: target,
                inboxRecorded: true
            )
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static func tripUserInfo(
        tripID: UUID? = nil,
        action: String? = nil,
        target: String? = nil,
        inboxRecorded: Bool
    ) -> [String: Any] {
        var userInfo: [String: Any] = [:]
        if inboxRecorded {
            userInfo["milehound.inboxRecorded"] = true
        }
        if let action {
            userInfo[actionUserInfoKey] = action
        }
        if let tripID {
            userInfo[tripIDUserInfoKey] = tripID.uuidString
        }
        if let target {
            userInfo[targetUserInfoKey] = target
        }
        return userInfo
    }

    static func notifyTripEnded(
        tripID: UUID,
        distanceMeters: Double,
        duration: TimeInterval,
        routeSummary: String
    ) {
        requestAuthorizationIfNeeded()
        let km = DateFormatters.formatDistance(distanceMeters)
        let durationText = DateFormatters.formatDuration(duration)
        let format = L10n.string("trip.ended.rich.body")
        let body = String(format: format, km, durationText, routeSummary)
        deliver(
            identifier: "milehound.trip.ended.\(tripID.uuidString)",
            kind: .tripEnded,
            title: L10n.tripEndedTitle,
            body: body,
            tripID: tripID,
            action: openTripAction
        )
    }

    static func notifyTripDiscarded(tripID: UUID) {
        deliver(
            identifier: "milehound.trip.discarded.\(tripID.uuidString)",
            kind: .tripDiscarded,
            title: L10n.tripDiscardedTitle,
            body: L10n.tripDiscardedBody,
            tripID: tripID
        )
    }

    static func notifyTripsMerged(tripID: UUID, legCount: Int) {
        deliver(
            identifier: "milehound.trip.merged.\(tripID.uuidString)",
            kind: .tripsMerged,
            title: L10n.tripsMergedTitle,
            body: L10n.tripsMergedBody(legCount),
            tripID: tripID,
            action: openTripAction
        )
    }

    @MainActor
    static func notifyAchievementsUnlocked(_ ids: [AchievementID]) {
        let unique = Array(Set(ids)).sorted { $0.sortOrder < $1.sortOrder }
        guard !unique.isEmpty else { return }
        let title = L10n.string("premium.achievements.unlocked")
        for id in unique {
            AppNotificationStore.shared.record(
                kind: .achievementUnlocked,
                title: title,
                body: L10n.achievementTitle(id),
                action: openAchievementsAction,
                target: id.rawValue
            )
        }
        let body = unique.count == 1
            ? L10n.achievementTitle(unique[0])
            : L10n.achievementsUnlockedCount(unique.count)
        let identifier = unique.count == 1
            ? "milehound.achievement.\(unique[0].rawValue)"
            : "milehound.achievement.batch"
        postSystemNotification(
            identifier: identifier,
            title: title,
            body: body,
            action: openAchievementsAction,
            target: unique.count == 1 ? unique[0].rawValue : nil,
            skipWhenYearSelected: true
        )
    }

    static func scheduleOrphanStaleNotification(tripID: UUID, lastActivity: Date) {
        let identifier = orphanNotificationID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let fireDate = lastActivity.addingTimeInterval(TripRecoveryService.staleThreshold)
        guard fireDate > Date() else {
            notifyOrphanStaleNow(tripID: tripID)
            return
        }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let title = L10n.string("orphan.stale.title")
            let body = L10n.string("orphan.stale.body")
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = tripUserInfo(tripID: tripID, action: openTripAction, inboxRecorded: true)

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelOrphanStaleNotification(tripID: UUID) {
        let identifier = orphanNotificationID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func notifyOrphanStaleNow(tripID: UUID) {
        deliver(
            identifier: orphanNotificationID(tripID: tripID),
            kind: .orphanStale,
            title: L10n.string("orphan.stale.title"),
            body: L10n.string("orphan.stale.body"),
            tripID: tripID,
            action: openTripAction
        )
    }

    private static func orphanNotificationID(tripID: UUID) -> String {
        "milehound.trip.orphan.\(tripID.uuidString)"
    }

    private static func deliver(
        identifier: String,
        kind: AppNotificationKind,
        title: String,
        body: String,
        tripID: UUID? = nil,
        action: String? = nil,
        target: String? = nil
    ) {
        let resolvedAction = action
        let resolvedTarget = target ?? tripID?.uuidString
        Task { @MainActor in
            AppNotificationStore.shared.record(
                kind: kind,
                title: title,
                body: body,
                tripID: tripID,
                action: resolvedAction,
                target: resolvedTarget
            )
        }

        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else {
                #if DEBUG
                print("TripNotificationService: skipped push '\(identifier)' — authorization is \(settings.authorizationStatus.rawValue)")
                #endif
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = tripUserInfo(
                tripID: tripID,
                action: resolvedAction,
                target: resolvedTarget,
                inboxRecorded: true
            )

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                #if DEBUG
                print("TripNotificationService: failed to deliver '\(identifier)': \(error.localizedDescription)")
                #endif
            }
        }
    }
}
