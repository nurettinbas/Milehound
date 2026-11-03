import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class VehicleCareSummaryStore {
    static let shared = VehicleCareSummaryStore()

    private(set) var upcomingItems: [VehicleDueItem] = []
    private(set) var topBannerItem: VehicleDueItem?

    private init() {}

    func refresh(in context: ModelContext) {
        let descriptor = FetchDescriptor<VehicleSchedule>(
            predicate: #Predicate { $0.isEnabled == true }
        )
        let schedules = (try? context.fetch(descriptor)) ?? []
        let urgent = VehicleCareDueCalculator.dueItems(from: schedules, urgentOnly: true)
        upcomingItems = Array(urgent.prefix(3))
        topBannerItem = urgent.first { item in
            !isBannerDismissed(scheduleID: item.scheduleID)
        }
    }

    func dismissBanner(scheduleID: UUID) {
        let tomorrow = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(24 * 60 * 60)
        UserDefaults.standard.set(tomorrow.timeIntervalSince1970, forKey: dismissKey(scheduleID))
        if topBannerItem?.scheduleID == scheduleID {
            topBannerItem = upcomingItems.first { item in
                item.scheduleID != scheduleID && !isBannerDismissed(scheduleID: item.scheduleID)
            }
        }
    }

    private func isBannerDismissed(scheduleID: UUID) -> Bool {
        let key = dismissKey(scheduleID)
        let until = UserDefaults.standard.double(forKey: key)
        guard until > 0 else { return false }
        return Date().timeIntervalSince1970 < until
    }

    private func dismissKey(_ scheduleID: UUID) -> String {
        "careBannerDismissedUntil.\(scheduleID.uuidString)"
    }
}
