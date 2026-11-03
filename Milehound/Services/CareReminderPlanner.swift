import Foundation

enum CareReminderStage: String, CaseIterable, Sendable {
    case early
    case week
    case dueDay
    case overdue

    /// Days relative to due date: negative = before, 0 = due day, positive = after due.
    var dayDeltaFromDue: Int {
        switch self {
        case .early: -30
        case .week: -7
        case .dueDay: 0
        case .overdue: 1
        }
    }
}

enum CareReminderAction: Equatable, Sendable {
    /// Schedule a 09:00 local calendar trigger on this start-of-day.
    case schedule(fireDay: Date)
    /// Overdue fire day already passed — deliver once if not yet recorded.
    case catchUpImmediate(fireDay: Date)
}

struct CareReminderPlanEntry: Equatable, Sendable {
    let stage: CareReminderStage
    let action: CareReminderAction
}

enum CareReminderPlanner {
    static func stages(for kind: VehicleScheduleKind) -> [CareReminderStage] {
        kind.reminderStages
    }

    /// Pure plan of reminder actions for one schedule due date.
    static func plan(
        stages: [CareReminderStage],
        dueDate: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [CareReminderPlanEntry] {
        let startToday = calendar.startOfDay(for: today)
        let startDue = calendar.startOfDay(for: dueDate)
        var entries: [CareReminderPlanEntry] = []

        for stage in stages {
            guard let fireDay = calendar.date(byAdding: .day, value: stage.dayDeltaFromDue, to: startDue)
            else { continue }

            if fireDay >= startToday {
                entries.append(CareReminderPlanEntry(stage: stage, action: .schedule(fireDay: fireDay)))
            } else if stage == .overdue {
                entries.append(CareReminderPlanEntry(stage: stage, action: .catchUpImmediate(fireDay: fireDay)))
            }
        }
        return entries
    }

    static func dueDayKey(dueDate: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: dueDate)
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d%02d%02d", year, month, day)
    }
}

enum KmCareStage: String, Sendable {
    case kmEarly
    case kmDue
    case kmOverdue
}

struct KmCareDecision: Equatable, Sendable {
    let stage: KmCareStage
    let kmLeft: Int
    /// Changes when the target kilometre changes, so the next service can notify again.
    let dedupeKey: String
}

enum KmReminderPlanner {
    /// One stage for the reading right now. A long trip that jumps past the window sends only the latest stage.
    static func decision(
        scheduleID: UUID,
        dueKm: Int,
        odometerKm: Int,
        intervalKm: Int?
    ) -> KmCareDecision? {
        let left = dueKm - odometerKm
        let threshold = VehicleCareDueCalculator.kmSoonThreshold(intervalKm: intervalKm)
        let stage: KmCareStage
        if left > threshold {
            return nil
        } else if left > 0 {
            stage = .kmEarly
        } else if left > -threshold {
            stage = .kmDue
        } else {
            stage = .kmOverdue
        }
        let key = "\(scheduleID.uuidString).\(dueKm).\(stage.rawValue)"
        return KmCareDecision(stage: stage, kmLeft: left, dedupeKey: key)
    }

    static func shouldSend(recordingActive: Bool, alreadySent: Bool, decision: KmCareDecision?) -> Bool {
        guard !recordingActive, decision != nil, !alreadySent else { return false }
        return true
    }
}
