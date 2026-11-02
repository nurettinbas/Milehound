import CoreLocation
import Foundation

public enum DateFormatters {
    public static var currentLocale: Locale {
        SharedLanguage.locale
    }

    public static func tripDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    public static func tripDateOnlyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    public static func tripTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    public static var tripDate: DateFormatter { tripDateFormatter() }
    public static var tripDateOnly: DateFormatter { tripDateOnlyFormatter() }
    public static var tripTime: DateFormatter { tripTimeFormatter() }

    public static func monthYearFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }

    public static func monthNameFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }

    public static func chartDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }

    public static var monthYear: DateFormatter { monthYearFormatter() }
    public static var monthName: DateFormatter { monthNameFormatter() }
    public static var chartDay: DateFormatter { chartDayFormatter() }

    /// Localized month name only (`August` / `Ağustos`). Pass a real year so the date is not year 1.
    public static func formatMonthName(
        month: Int,
        year: Int,
        calendar: Calendar = .current
    ) -> String {
        var components = DateComponents()
        components.year = year
        components.month = min(12, max(1, month))
        components.day = 1
        let date = calendar.date(from: components) ?? Date()
        return monthName.string(from: date)
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Turns stay in metres until a kilometre. Trip totals stay in kilometres.
    public static func formatManeuverDistance(_ meters: Double) -> String {
        guard meters < 1_000 else { return formatDistance(meters) }
        let formatter = MeasurementFormatter()
        formatter.locale = currentLocale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    public static func formatDistance(_ meters: Double) -> String {
        let kilometers = meters / 1000
        let formatter = MeasurementFormatter()
        formatter.locale = currentLocale
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = kilometers >= 10 ? 0 : 1
        let measurement = Measurement(value: kilometers, unit: UnitLength.kilometers)
        return formatter.string(from: measurement)
    }

    public static func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    public static func formatTripDateRange(startedAt: Date, endedAt: Date?) -> String {
        let datePart = tripDateOnly.string(from: startedAt)
        let startTime = tripTime.string(from: startedAt)
        guard let endedAt else { return "\(datePart) · \(startTime)" }
        let endTime = tripTime.string(from: endedAt)
        return "\(datePart) · \(startTime) – \(endTime)"
    }
}
