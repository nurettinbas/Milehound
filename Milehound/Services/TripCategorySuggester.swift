import CoreLocation
import Foundation

enum TripCategorySuggester {
    static let minimumRouteSamples = 3
    static let minimumRouteMajority = 0.70

    static func suggestion(
        for trip: Trip,
        places: [SavedPlace],
        histogram: [String: [String: Int]],
        workHours: TripCategoryWorkHours = .default,
        calendar: Calendar = .current
    ) -> TripCategorySuggestion? {
        guard trip.endedAt != nil else { return nil }
        guard !trip.categoryOrigin.blocksSuggestion else { return nil }

        if let route = routeSuggestion(for: trip, histogram: histogram) {
            return route
        }
        if let place = placeSuggestion(for: trip, places: places) {
            return place
        }
        if let hours = hoursSuggestion(for: trip, workHours: workHours, calendar: calendar) {
            return hours
        }
        return nil
    }

    /// One-line reason for DevLog: why a pending suggestion was or was not written.
    static func explain(
        for trip: Trip,
        places: [SavedPlace],
        histogram: [String: [String: Int]],
        workHours: TripCategoryWorkHours = .default,
        calendar: Calendar = .current
    ) -> String {
        let tripTag = String(trip.id.uuidString.prefix(8))
        let category = categoryLabel(trip.categoryID)
        if trip.endedAt == nil {
            return "skip unfinished trip=\(tripTag) category=\(category)"
        }
        if trip.categoryOrigin.blocksSuggestion {
            return "skip locked origin=\(trip.categoryOrigin.rawValue) trip=\(tripTag) category=\(category)"
        }
        if let suggestion = suggestion(
            for: trip,
            places: places,
            histogram: histogram,
            workHours: workHours,
            calendar: calendar
        ) {
            return "suggest \(categoryLabel(suggestion.categoryID)) reason=\(suggestion.reason.rawValue) trip=\(tripTag) category stays \(category)"
        }

        let hour = calendar.component(.hour, from: trip.startedAt)
        let weekend = calendar.isDateInWeekend(trip.startedAt)
        let inHours = workHours.contains(trip.startedAt, calendar: calendar)
        let startKind = placeKind(
            name: trip.startPlaceName,
            coordinate: trip.startCoordinate,
            places: places
        )
        let endKind = placeKind(
            name: trip.endPlaceName,
            coordinate: trip.endCoordinate,
            places: places
        )
        let routeSamples: Int
        if let pairKey = FrequentRoutesService.pairKey(for: trip),
           let counts = histogram[pairKey] {
            routeSamples = counts.values.reduce(0, +)
        } else {
            routeSamples = 0
        }
        return "skip no-match trip=\(tripTag) category=\(category) weekend=\(weekend) hour=\(hour) workHours=\(workHours.startHour)-\(workHours.endHour) inHours=\(inHours) startKind=\(startKind?.rawValue ?? "none") endKind=\(endKind?.rawValue ?? "none") places=\(places.count) routeSamples=\(routeSamples)"
    }

    private static func categoryLabel(_ id: String) -> String {
        if id == BuiltInCategory.personalID.uuidString { return "Personal" }
        if id == BuiltInCategory.businessID.uuidString { return "Business" }
        return String(id.prefix(8))
    }

    private static func routeSuggestion(
        for trip: Trip,
        histogram: [String: [String: Int]]
    ) -> TripCategorySuggestion? {
        guard let pairKey = FrequentRoutesService.pairKey(for: trip),
              let counts = histogram[pairKey]
        else { return nil }

        let total = counts.values.reduce(0, +)
        guard total >= minimumRouteSamples else { return nil }
        guard let (categoryID, count) = counts.max(by: { $0.value < $1.value }) else { return nil }

        let confidence = Double(count) / Double(total)
        guard confidence >= minimumRouteMajority else { return nil }
        guard categoryID != BuiltInCategory.personalID.uuidString else { return nil }
        guard categoryID != trip.categoryID else { return nil }

        return TripCategorySuggestion(categoryID: categoryID, reason: .route, confidence: confidence)
    }

    private static func placeSuggestion(
        for trip: Trip,
        places: [SavedPlace]
    ) -> TripCategorySuggestion? {
        guard !places.isEmpty else { return nil }

        let startKind = placeKind(
            name: trip.startPlaceName,
            coordinate: trip.startCoordinate,
            places: places
        )
        let endKind = placeKind(
            name: trip.endPlaceName,
            coordinate: trip.endCoordinate,
            places: places
        )

        let isCommute =
            (startKind == .home && endKind == .work) ||
            (startKind == .work && endKind == .home)
        let touchesWork = startKind == .work || endKind == .work
        guard isCommute || touchesWork else { return nil }

        let businessID = BuiltInCategory.businessID.uuidString
        guard businessID != trip.categoryID else { return nil }
        return TripCategorySuggestion(categoryID: businessID, reason: .place, confidence: isCommute ? 0.85 : 0.75)
    }

    private static func hoursSuggestion(
        for trip: Trip,
        workHours: TripCategoryWorkHours,
        calendar: Calendar
    ) -> TripCategorySuggestion? {
        guard !calendar.isDateInWeekend(trip.startedAt) else { return nil }
        guard workHours.contains(trip.startedAt, calendar: calendar) else { return nil }

        let businessID = BuiltInCategory.businessID.uuidString
        guard businessID != trip.categoryID else { return nil }
        return TripCategorySuggestion(categoryID: businessID, reason: .hours, confidence: 0.55)
    }

    private static func placeKind(
        name: String?,
        coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace]
    ) -> SavedPlaceKind? {
        if let coordinate, let place = places.first(where: { $0.contains(coordinate) }) {
            return place.kind
        }
        if let name, let place = places.first(where: { $0.name == name }) {
            return place.kind
        }
        return nil
    }
}
