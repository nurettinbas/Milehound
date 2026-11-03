import Foundation

enum RecapYearPolicy {
    /// January shows last year's recap; every other month is year-to-date.
    static func displayYear(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return month == 1 ? year - 1 : year
    }

    static func seenKey(for year: Int) -> String {
        "recap.seen.\(year)"
    }

    static func shouldPresent(_ snapshot: YearRecapSnapshot?) -> Bool {
        snapshot?.hasData == true
    }
}

enum RecapPromoPolicy {
    static let windowDays = 7

    static func dismissedKey(for year: Int) -> String {
        "recap.promo.dismissed.\(year)"
    }

    static func catchUpPresentedKey(for year: Int) -> String {
        "recap.promo.catchUpPresented.\(year)"
    }

    /// 1 January 00:00 local of the year after `year`.
    static func windowStart(forRecapYear year: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
    }

    static func isJanuary(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.component(.month, from: now) == 1
    }

    /// Inclusive of 1 Jan 00:00, exclusive of 8 Jan 00:00.
    static func isWithinWindow(
        now: Date = Date(),
        recapYear: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard let start = windowStart(forRecapYear: recapYear, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: windowDays, to: start)
        else { return false }
        return now >= start && now < end
    }

    static func shouldPresent(
        hasData: Bool,
        dismissed: Bool,
        catchUpPresented: Bool,
        recapYear: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard hasData, !dismissed else { return false }
        guard isJanuary(now: now, calendar: calendar) else { return false }
        guard RecapYearPolicy.displayYear(now: now, calendar: calendar) == recapYear else { return false }
        if isWithinWindow(now: now, recapYear: recapYear, calendar: calendar) {
            return true
        }
        return !catchUpPresented
    }

    static func noteDismissed(year: Int, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: dismissedKey(for: year))
    }

    static func noteCatchUpPresented(year: Int, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: catchUpPresentedKey(for: year))
    }
}

enum RecapNotificationPolicy {
    static func notifiedKey(for year: Int) -> String {
        "recap.notified.\(year)"
    }

    /// Previous calendar year — only during January, when that recap is complete.
    static func catchUpYear(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        calendar.component(.month, from: now) == 1
            ? calendar.component(.year, from: now) - 1
            : nil
    }

    /// 1 January 09:00 local of the year after `year`.
    static func fireDate(forRecapYear year: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1, hour: 9, minute: 0))
    }

    static func shouldNotify(hasData: Bool, seen: Bool, alreadyNotified: Bool) -> Bool {
        hasData && !seen && !alreadyNotified
    }
}

/// Identifiable wrapper so the recap cover is never presented empty.
/// `fullScreenCover(isPresented:)` + `if let snapshot` draws a blank white
/// screen when SwiftUI builds the cover before the optional is copied in.
struct RecapStorySession: Identifiable, Equatable {
    let id: UUID
    let snapshot: YearRecapSnapshot
    let startPage: RecapStoryPage?

    init(snapshot: YearRecapSnapshot, startPage: RecapStoryPage? = nil) {
        self.id = UUID()
        self.snapshot = snapshot
        self.startPage = startPage
    }
}
