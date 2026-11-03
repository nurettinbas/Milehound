import CoreLocation
import Foundation
import SwiftData

struct FrequentRouteSnapshot: Equatable, Sendable {
    let pairKey: String
    let startKey: String
    let endKey: String
    let startDisplay: String
    let endDisplay: String
    let startLatitude: Double
    let startLongitude: Double
    let endLatitude: Double
    let endLongitude: Double
    let distanceMeters: Double
    let fuelCost: Double
    let startedAt: Date
    let isBusiness: Bool

    var isValidPair: Bool {
        startKey != "unknown" && endKey != "unknown" && startKey != endKey
    }
}

enum FrequentRouteOverlayBudget {
    static let maxArcs = 40
    /// Portrait of habit — repeated corridors in the same metro as the top run.
    static let maxHabitArcs = 8
    static let minimumHabitCount = 2
    static let heatmapSamplesPerArc = 8
    static let metroMeters: CLLocationDistance = 45_000
    static let maxCameraSpanMeters: CLLocationDistance = 70_000

    static func topAggregates(_ aggregates: [FrequentRouteAggregate]) -> [FrequentRouteAggregate] {
        Array(ranked(aggregates).prefix(maxArcs))
    }

    /// Repeated corridors in the same city as the featured run. Count ≥ 2; one-off and far-away trips stay off.
    static func habitCorridors(_ aggregates: [FrequentRouteAggregate]) -> [FrequentRouteAggregate] {
        let ranked = ranked(aggregates).filter { $0.hasValidCoordinates && $0.count >= minimumHabitCount }
        guard let featured = ranked.first else { return [] }
        let reach = metroRadius(for: featured)
        var picked: [FrequentRouteAggregate] = [featured]
        for row in ranked.dropFirst() {
            guard picked.count < maxHabitArcs else { break }
            guard sharesMetro(row, with: featured, meters: reach) else { continue }
            picked.append(row)
        }
        return picked
    }

    private static func ranked(_ aggregates: [FrequentRouteAggregate]) -> [FrequentRouteAggregate] {
        aggregates.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.pairKey < rhs.pairKey
        }
    }

    private static func metroRadius(for featured: FrequentRouteAggregate) -> CLLocationDistance {
        let start = CLLocation(latitude: featured.startLatitude, longitude: featured.startLongitude)
        let end = CLLocation(latitude: featured.endLatitude, longitude: featured.endLongitude)
        return max(metroMeters, start.distance(from: end) * 0.55)
    }

    private static func sharesMetro(
        _ row: FrequentRouteAggregate,
        with featured: FrequentRouteAggregate,
        meters: CLLocationDistance
    ) -> Bool {
        let featuredPoints = [
            midpoint(featured),
            CLLocation(latitude: featured.startLatitude, longitude: featured.startLongitude),
            CLLocation(latitude: featured.endLatitude, longitude: featured.endLongitude)
        ]
        let rowPoints = [
            midpoint(row),
            CLLocation(latitude: row.startLatitude, longitude: row.startLongitude),
            CLLocation(latitude: row.endLatitude, longitude: row.endLongitude)
        ]
        return rowPoints.contains { point in
            featuredPoints.contains { $0.distance(from: point) <= meters }
        }
    }

    private static func midpoint(_ row: FrequentRouteAggregate) -> CLLocation {
        CLLocation(
            latitude: (row.startLatitude + row.endLatitude) / 2,
            longitude: (row.startLongitude + row.endLongitude) / 2
        )
    }
}

enum FrequentRouteAggregateService {
    static func snapshot(
        of trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> FrequentRouteSnapshot? {
        guard trip.endedAt != nil else { return nil }
        let startKey = clusterKey(
            placeName: trip.startPlaceName,
            address: trip.startAddress,
            coordinate: trip.startCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        let endKey = clusterKey(
            placeName: trip.endPlaceName,
            address: trip.endAddress,
            coordinate: trip.endCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        guard startKey != "unknown", endKey != "unknown", startKey != endKey else { return nil }

        let startDisplay = FrequentRoutesService.displayName(
            placeName: trip.startPlaceName,
            address: trip.startAddress,
            coordinate: trip.startCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        let endDisplay = FrequentRoutesService.displayName(
            placeName: trip.endPlaceName,
            address: trip.endAddress,
            coordinate: trip.endCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        let startCoord = TripLocalityResolver.mapCoordinate(
            trip.startCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        let endCoord = TripLocalityResolver.mapCoordinate(
            trip.endCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        return FrequentRouteSnapshot(
            pairKey: canonicalPairKey(startKey: startKey, endKey: endKey),
            startKey: startKey,
            endKey: endKey,
            startDisplay: startDisplay,
            endDisplay: endDisplay,
            startLatitude: startCoord?.latitude ?? 0,
            startLongitude: startCoord?.longitude ?? 0,
            endLatitude: endCoord?.latitude ?? 0,
            endLongitude: endCoord?.longitude ?? 0,
            distanceMeters: trip.distanceMeters,
            fuelCost: trip.estimatedFuelCost ?? 0,
            startedAt: trip.startedAt,
            isBusiness: trip.categoryID == BuiltInCategory.businessID.uuidString
        )
    }

    static func add(_ snapshot: FrequentRouteSnapshot, in context: ModelContext) {
        apply(snapshot, sign: 1, in: context)
    }

    static func remove(_ snapshot: FrequentRouteSnapshot, in context: ModelContext) {
        apply(snapshot, sign: -1, in: context)
    }

    static func topAggregates(in context: ModelContext, limit: Int = FrequentRouteOverlayBudget.maxArcs) -> [FrequentRouteAggregate] {
        var descriptor = FetchDescriptor<FrequentRouteAggregate>(
            sortBy: [SortDescriptor(\.count, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func bezierSamples(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        count: Int = FrequentRouteOverlayBudget.heatmapSamplesPerArc
    ) -> [CLLocationCoordinate2D] {
        guard count >= 2 else { return [start, end] }
        let control = arcControlPoint(start: start, end: end)
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return quadratic(start: start, control: control, end: end, t: t)
        }
    }

    static func arcControlPoint(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let midLat = (start.latitude + end.latitude) / 2
        let midLon = (start.longitude + end.longitude) / 2
        let dLat = end.latitude - start.latitude
        let dLon = end.longitude - start.longitude
        let bulge = 0.22
        return CLLocationCoordinate2D(
            latitude: midLat - dLon * bulge,
            longitude: midLon + dLat * bulge
        )
    }

    private static func quadratic(
        start: CLLocationCoordinate2D,
        control: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let u = 1 - t
        return CLLocationCoordinate2D(
            latitude: u * u * start.latitude + 2 * u * t * control.latitude + t * t * end.latitude,
            longitude: u * u * start.longitude + 2 * u * t * control.longitude + t * t * end.longitude
        )
    }

    private static func apply(_ snapshot: FrequentRouteSnapshot, sign: Double, in context: ModelContext) {
        guard snapshot.isValidPair else { return }
        let pairKey = snapshot.pairKey
        var descriptor = FetchDescriptor<FrequentRouteAggregate>(
            predicate: #Predicate { aggregate in
                aggregate.pairKey == pairKey
            }
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor))?.first
        let row: FrequentRouteAggregate
        if let existing {
            row = existing
        } else if sign > 0 {
            row = FrequentRouteAggregate(
                pairKey: snapshot.pairKey,
                startKey: snapshot.startKey,
                endKey: snapshot.endKey
            )
            context.insert(row)
        } else {
            return
        }

        row.startDisplay = snapshot.startDisplay
        row.endDisplay = snapshot.endDisplay
        if snapshot.startLatitude != 0 || snapshot.startLongitude != 0 {
            row.startLatitude = snapshot.startLatitude
            row.startLongitude = snapshot.startLongitude
        }
        if snapshot.endLatitude != 0 || snapshot.endLongitude != 0 {
            row.endLatitude = snapshot.endLatitude
            row.endLongitude = snapshot.endLongitude
        }
        row.count = max(0, row.count + Int(sign))
        row.totalDistanceMeters = max(0, row.totalDistanceMeters + sign * snapshot.distanceMeters)
        row.totalFuelCost = max(0, row.totalFuelCost + sign * snapshot.fuelCost)
        if snapshot.isBusiness {
            row.businessCount = max(0, row.businessCount + Int(sign))
        } else {
            row.personalCount = max(0, row.personalCount + Int(sign))
        }
        if sign > 0 {
            row.lastStartedAt = max(row.lastStartedAt, snapshot.startedAt)
        }
        if row.count == 0 {
            context.delete(row)
        }
    }

    /// A→B and B→A are the same corridor for the map card.
    static func canonicalPairKey(startKey: String, endKey: String) -> String {
        startKey <= endKey ? "\(startKey)→\(endKey)" : "\(endKey)→\(startKey)"
    }

    /// ~450 m at the equator — parking jitter merges, separate neighborhoods do not.
    static let geoCellDegrees = 0.004

    static func geoCellKey(_ coordinate: CLLocationCoordinate2D) -> String {
        let cell = geoCellDegrees
        let latCell = Int((coordinate.latitude / cell).rounded())
        let lonCell = Int((coordinate.longitude / cell).rounded())
        return "geo:\(latCell),\(lonCell)"
    }

    /// Saved-place identity first, then a geo cell. Reverse-geocode name drift must not
    /// split a commute that old trips already recorded under a different street label.
    static func clusterKey(
        placeName: String?,
        address: String?,
        coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String {
        if let coordinate, isUsable(coordinate),
           let place = PlaceMatchingService.matchingPlace(
            at: coordinate,
            places: places,
            privacyRadius: privacyRadius
           ) {
            return "place:\(place.id.uuidString)"
        }
        if let coordinate, isUsable(coordinate) {
            return geoCellKey(coordinate)
        }
        let trimmedName = placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty,
           let place = places.first(where: {
               $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
           }) {
            return "place:\(place.id.uuidString)"
        }
        return FrequentRoutesService.routeKey(
            placeName: placeName,
            address: address,
            coordinate: coordinate
        )
    }

    private static func isUsable(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && (abs(coordinate.latitude) > 0.0001 || abs(coordinate.longitude) > 0.0001)
    }
}
