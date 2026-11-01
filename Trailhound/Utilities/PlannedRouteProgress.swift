import CoreLocation
import Foundation

/// Where the vehicle sits on the planned route, and when to ask MapKit again.
/// Pure geometry — no MapKit, no SwiftData.
enum PlannedRouteProgress {
    /// Farther than this from the line counts as off route.
    static let offRouteMeters: CLLocationDistance = 75
    /// Consecutive off-route fixes before a reroute.
    static let offRouteFixes = 3
    /// MapKit directions are throttled. Never ask more often than this.
    static let rerouteInterval: TimeInterval = 30
    /// Inside this radius the trip has reached the destination and the route clears.
    static let arrivalMeters: CLLocationDistance = 50

    struct Measure: Equatable {
        /// Shortest distance from the vehicle to the route line.
        var offRouteMeters: CLLocationDistance
        /// Route length still ahead of the vehicle's projection.
        var remainingMeters: CLLocationDistance
    }

    /// Running distance at every vertex. `result[0] == 0`, `result.last` is the route length.
    static func cumulativeDistances(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
        guard !coordinates.isEmpty else { return [] }
        var result: [CLLocationDistance] = [0]
        result.reserveCapacity(coordinates.count)
        for index in 1..<coordinates.count {
            result.append(result[index - 1] + meters(coordinates[index - 1], coordinates[index]))
        }
        return result
    }

    /// Projects the vehicle onto the closest route segment.
    /// Returns nil when the route has fewer than two valid vertices or the vehicle is invalid.
    static func measure(
        vehicle: CLLocationCoordinate2D,
        along coordinates: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance]
    ) -> Measure? {
        guard CLLocationCoordinate2DIsValid(vehicle),
              coordinates.count >= 2,
              cumulative.count == coordinates.count,
              let total = cumulative.last
        else { return nil }

        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestAlong: CLLocationDistance = 0
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = metresPerDegreeLat * cos(vehicle.latitude * .pi / 180)

        func local(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (coordinate.longitude - vehicle.longitude) * metresPerDegreeLon,
                (coordinate.latitude - vehicle.latitude) * metresPerDegreeLat
            )
        }

        for index in 0..<(coordinates.count - 1) {
            let a = local(coordinates[index])
            let b = local(coordinates[index + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t: Double
            if lengthSquared < 1e-9 {
                t = 0
            } else {
                t = min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared))
            }
            let px = a.x + dx * t
            let py = a.y + dy * t
            let distance = (px * px + py * py).squareRoot()
            if distance < bestDistance {
                bestDistance = distance
                let segment = cumulative[index + 1] - cumulative[index]
                bestAlong = cumulative[index] + segment * t
            }
        }

        guard bestDistance.isFinite else { return nil }
        return Measure(offRouteMeters: bestDistance, remainingMeters: max(0, total - bestAlong))
    }

    /// MapKit's travel time scaled by the share of the route still ahead.
    static func remainingTravelTime(
        remainingMeters: CLLocationDistance,
        routeMeters: CLLocationDistance,
        expectedTravelTime: TimeInterval
    ) -> TimeInterval {
        guard routeMeters > 0, expectedTravelTime > 0, remainingMeters > 0 else { return 0 }
        let fraction = min(1, remainingMeters / routeMeters)
        return expectedTravelTime * fraction
    }

    static func shouldReroute(
        offRouteStreak: Int,
        lastRequestAt: Date?,
        now: Date
    ) -> Bool {
        guard offRouteStreak >= offRouteFixes else { return false }
        return canRequest(lastRequestAt: lastRequestAt, now: now)
    }

    static func canRequest(lastRequestAt: Date?, now: Date) -> Bool {
        guard let lastRequestAt else { return true }
        return now.timeIntervalSince(lastRequestAt) >= rerouteInterval
    }

    static func hasArrived(
        vehicle: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) -> Bool {
        guard CLLocationCoordinate2DIsValid(vehicle), CLLocationCoordinate2DIsValid(destination) else {
            return false
        }
        return meters(vehicle, destination) <= arrivalMeters
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

/// Destination entry while recording. Saved places are one tap at any speed;
/// typing a search waits until the car is stopped or the trip is paused.
enum DestinationEntryPolicy {
    /// Above this the car is moving (about 7 km/h — walking pace in a car park).
    static let movingSpeedMps: Double = 2
    static let maxQueryLength = 120

    /// Core Location reports `-1` when speed is unknown. Recording treats that as 0.
    static func allowsSearch(speedMps: Double, isPaused: Bool) -> Bool {
        if isPaused { return true }
        return max(0, speedMps) <= movingSpeedMps
    }

    static func sanitizedQuery(_ raw: String) -> String {
        String(raw.prefix(maxQueryLength))
    }
}
