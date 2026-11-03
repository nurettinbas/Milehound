import Foundation

enum VehicleCareDueCalculator {
    static func dueState(
        nextDueDate: Date?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> VehicleCareDueState {
        guard let nextDueDate else { return .noDate }
        let startToday = calendar.startOfDay(for: today)
        let startDue = calendar.startOfDay(for: nextDueDate)
        let days = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 0
        if days > 0 { return .upcoming(daysLeft: days) }
        if days == 0 { return .dueToday }
        return .overdue(days: abs(days))
    }

    /// 15% of the service interval, clamped to 300...1500 km.
    static func kmSoonThreshold(intervalKm: Int?) -> Int {
        let interval = max(intervalKm ?? 1_000, 1)
        let raw = Int((Double(interval) * 0.15).rounded())
        return min(1_500, max(300, raw))
    }

    static func formatKilometers(_ km: Int, locale: Locale = .current) -> String {
        let number = abs(km).formatted(.number.locale(locale))
        return "\(number) km"
    }

    static func dueState(
        schedule: VehicleSchedule,
        odometerKm: Int?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> VehicleCareDueState {
        let dateState = dueState(nextDueDate: schedule.nextDueDate, today: today, calendar: calendar)
        let kmState = kmDueState(
            dueKm: schedule.nextDueOdometerKm,
            odometerKm: odometerKm,
            intervalKm: schedule.intervalKm
        )
        switch schedule.intervalKind {
        case .everyKm:
            return kmState
        case .everyMonths, .everyYears, .none:
            return dateState
        case .whicheverFirst:
            if case .noDate = kmState { return dateState }
            if case .noDate = dateState { return kmState }
            return moreUrgent(dateState, kmState)
        }
    }

    static func kmDueState(dueKm: Int?, odometerKm: Int?, intervalKm: Int?) -> VehicleCareDueState {
        guard let dueKm, let odometerKm else { return .noDate }
        let left = dueKm - odometerKm
        if left > 0 {
            let approaching = left <= kmSoonThreshold(intervalKm: intervalKm)
            return .upcomingKm(kmLeft: left, approaching: approaching)
        }
        if left == 0 { return .dueToday }
        return .overdueKm(kmOver: abs(left))
    }

    static func moreUrgent(_ lhs: VehicleCareDueState, _ rhs: VehicleCareDueState) -> VehicleCareDueState {
        if lhs.sortPriority != rhs.sortPriority {
            return lhs.sortPriority < rhs.sortPriority ? lhs : rhs
        }
        return lhs.urgencySortKey <= rhs.urgencySortKey ? lhs : rhs
    }

    static func dueItems(
        from schedules: [VehicleSchedule],
        today: Date = Date(),
        calendar: Calendar = .current,
        urgentOnly: Bool = false
    ) -> [VehicleDueItem] {
        var items: [VehicleDueItem] = []
        for schedule in schedules where schedule.isEnabled {
            guard let vehicle = schedule.vehicle else { continue }
            let state = dueState(
                schedule: schedule,
                odometerKm: vehicle.currentOdometerKm,
                today: today,
                calendar: calendar
            )
            let kmLeft: Int? = {
                guard let due = schedule.nextDueOdometerKm, let current = vehicle.currentOdometerKm else { return nil }
                return due - current
            }()
            let item = VehicleDueItem(
                id: schedule.id,
                scheduleID: schedule.id,
                vehicleID: vehicle.id,
                vehicleName: vehicle.name,
                kind: schedule.kind,
                title: schedule.title,
                dueDate: schedule.nextDueDate,
                dueOdometerKm: schedule.nextDueOdometerKm,
                kmLeft: kmLeft,
                state: state
            )
            if urgentOnly && !state.isUrgent { continue }
            if case .noDate = state { continue }
            items.append(item)
        }
        return items.sorted { lhs, rhs in
            if lhs.state.sortPriority != rhs.state.sortPriority {
                return lhs.state.sortPriority < rhs.state.sortPriority
            }
            return lhs.daysSortKey < rhs.daysSortKey
        }
    }

    /// Urgent service schedule for a single vehicle (recording-card badge).
    static func urgentServiceDue(
        for vehicleID: UUID,
        from schedules: [VehicleSchedule],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> VehicleDueItem? {
        dueItems(from: schedules, today: today, calendar: calendar, urgentOnly: true)
            .first { $0.vehicleID == vehicleID && $0.kind == .service }
    }

    /// Advances `nextDueDate` after a completion, using the schedule interval.
    static func nextDueDateAfterCompletion(
        completedOn: Date,
        intervalKind: VehicleScheduleIntervalKind,
        intervalMonths: Int?,
        calendar: Calendar = .current
    ) -> Date? {
        switch intervalKind {
        case .none, .everyKm:
            return nil
        case .everyMonths:
            let months = max(1, intervalMonths ?? 12)
            return calendar.date(byAdding: .month, value: months, to: completedOn)
        case .everyYears:
            let years = max(1, (intervalMonths ?? 12) / 12)
            let monthCount = intervalMonths ?? (years * 12)
            if monthCount % 12 == 0 {
                return calendar.date(byAdding: .year, value: monthCount / 12, to: completedOn)
            }
            return calendar.date(byAdding: .month, value: monthCount, to: completedOn)
        case .whicheverFirst:
            let months = max(1, intervalMonths ?? 12)
            return calendar.date(byAdding: .month, value: months, to: completedOn)
        }
    }

    static func subtitle(for state: VehicleCareDueState, title: String) -> String {
        switch state {
        case .upcoming(let days):
            return String(format: L10n.string("vehicles.care.due.days_left"), title, days)
        case .dueToday:
            return String(format: L10n.string("vehicles.care.due.today"), title)
        case .overdue(let days):
            return String(format: L10n.string("vehicles.care.due.overdue"), title, days)
        case .upcomingKm(let km, _):
            return String(format: L10n.string("vehicles.care.due.km_left"), title, formatKilometers(km))
        case .overdueKm(let km):
            return String(format: L10n.string("vehicles.care.due.km_overdue"), title, formatKilometers(km))
        case .noDate:
            return title
        }
    }

    static func shortSubtitle(for state: VehicleCareDueState) -> String? {
        switch state {
        case .upcoming(let days):
            return String(format: L10n.string("vehicles.care.due.short_days"), days)
        case .dueToday:
            return L10n.string("vehicles.care.due.short_today")
        case .overdue(let days):
            return String(format: L10n.string("vehicles.care.due.short_overdue"), days)
        case .upcomingKm(let km, _):
            return String(format: L10n.string("vehicles.care.due.short_km_left"), formatKilometers(km))
        case .overdueKm(let km):
            return String(format: L10n.string("vehicles.care.due.short_km_overdue"), formatKilometers(km))
        case .noDate:
            return nil
        }
    }
}
