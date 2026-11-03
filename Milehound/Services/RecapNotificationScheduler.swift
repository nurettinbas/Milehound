import Foundation
import SwiftData
@preconcurrency import UserNotifications

enum RecapNotificationScheduler {
    static let actionUserInfoKey = TripNotificationService.actionUserInfoKey
    static let yearUserInfoKey = TripNotificationService.targetUserInfoKey

    private static let idPrefix = "milehound.recap."

    static func notificationIdentifier(year: Int) -> String {
        "\(idPrefix)\(year)"
    }

    @MainActor
    static func reschedule(in context: ModelContext, now: Date = Date()) {
        TripNotificationService.requestAuthorizationIfNeeded()
        let calendar = Calendar.current
        let catchUp = RecapNotificationPolicy.catchUpYear(now: now, calendar: calendar)
        let inProgress = calendar.component(.year, from: now)
        let catchUpPlan = catchUp.map { year in
            RecapEnqueuePlan(
                year: year,
                seen: UserDefaults.standard.bool(forKey: RecapYearPolicy.seenKey(for: year)),
                notified: UserDefaults.standard.bool(forKey: RecapNotificationPolicy.notifiedKey(for: year)),
                hasData: yearHasData(year, in: context, calendar: calendar)
            )
        }
        let inProgressPlan = RecapEnqueuePlan(
            year: inProgress,
            seen: UserDefaults.standard.bool(forKey: RecapYearPolicy.seenKey(for: inProgress)),
            notified: UserDefaults.standard.bool(forKey: RecapNotificationPolicy.notifiedKey(for: inProgress)),
            hasData: yearHasData(inProgress, in: context, calendar: calendar)
        )
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
            Task { @MainActor in
                if let catchUpPlan {
                    enqueue(catchUpPlan, now: now, calendar: calendar)
                }
                enqueue(inProgressPlan, now: now, calendar: calendar)
            }
        }
    }

    static func noteRecapConsumed(year: Int) {
        UserDefaults.standard.set(true, forKey: RecapYearPolicy.seenKey(for: year))
        UserDefaults.standard.set(true, forKey: RecapNotificationPolicy.notifiedKey(for: year))
        let identifier = notificationIdentifier(year: year)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func markNotifiedIfNeeded(from userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[yearUserInfoKey] as? String, let year = Int(raw) else { return }
        UserDefaults.standard.set(true, forKey: RecapNotificationPolicy.notifiedKey(for: year))
    }

    @MainActor
    private static func enqueue(_ plan: RecapEnqueuePlan, now: Date, calendar: Calendar) {
        guard RecapNotificationPolicy.shouldNotify(
            hasData: plan.hasData,
            seen: plan.seen,
            alreadyNotified: plan.notified
        ) else { return }
        guard let fireDate = RecapNotificationPolicy.fireDate(forRecapYear: plan.year, calendar: calendar) else {
            return
        }

        if fireDate > now {
            schedule(year: plan.year, fireDate: fireDate, calendar: calendar)
        } else if RecapNotificationPolicy.catchUpYear(now: now, calendar: calendar) == plan.year {
            deliverCatchUp(year: plan.year)
        }
    }

    @MainActor
    private static func yearHasData(_ year: Int, in context: ModelContext, calendar: Calendar) -> Bool {
        if let cached = YearRecapCache.load(year: year) {
            return cached.hasData
        }
        guard
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart)
        else { return false }
        let descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart >= yearStart && rollup.dayStart < yearEnd
            }
        )
        let rollups = (try? context.fetch(descriptor)) ?? []
        let tripCount = rollups.reduce(0) { $0 + $1.tripCount }
        let distance = rollups.reduce(0.0) { $0 + $1.distanceMeters }
        return tripCount > 0 && distance > 0
    }

    private static func schedule(year: Int, fireDate: Date, calendar: Calendar) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = makeContent(year: year, inboxRecorded: false)
            var components = calendar.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = 9
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(year: year),
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    @MainActor
    private static func deliverCatchUp(year: Int) {
        UserDefaults.standard.set(true, forKey: RecapNotificationPolicy.notifiedKey(for: year))
        let title = L10n.recapNotificationTitle(year)
        let body = L10n.string("premium.recap.notification.body")
        AppNotificationStore.shared.record(
            kind: .yearRecapReady,
            title: title,
            body: body,
            action: TripNotificationService.openRecapAction,
            target: String(year)
        )
        let content = makeContent(year: year, inboxRecorded: true)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(year: year),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func makeContent(year: Int, inboxRecorded: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L10n.recapNotificationTitle(year)
        content.body = L10n.string("premium.recap.notification.body")
        content.sound = .default
        var userInfo: [String: Any] = [
            TripNotificationService.actionUserInfoKey: TripNotificationService.openRecapAction,
            yearUserInfoKey: String(year),
        ]
        if inboxRecorded {
            userInfo["milehound.inboxRecorded"] = true
        }
        content.userInfo = userInfo
        return content
    }
}

private struct RecapEnqueuePlan: Sendable {
    let year: Int
    let seen: Bool
    let notified: Bool
    let hasData: Bool
}
