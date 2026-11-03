import CoreLocation
import Foundation

/// One Apple driving step. The instruction is Apple's text; the distance is that step's length.
struct RouteStep: Equatable, Sendable {
    var instruction: String
    var distanceMeters: CLLocationDistance
}

/// The next maneuver to show, and how far it is. Not a button.
struct UpcomingManeuver: Equatable, Sendable {
    var distanceMeters: CLLocationDistance
    var instruction: String
}

/// SF Symbol for Apple's maneuver sentence. The text is localized, so the match
/// covers English and Turkish after folding accents.
enum ManeuverIcon {
    static func systemImage(for instruction: String) -> String {
        let text = folded(instruction)
        if isUTurn(text) {
            return side(of: text) == .right ? "arrow.uturn.right" : "arrow.uturn.left"
        }
        if text.contains("roundabout") || text.contains("kavsak") {
            return side(of: text) == .left
                ? "arrow.triangle.turn.up.left.circle"
                : "arrow.triangle.turn.up.right.circle"
        }
        if text.contains("arriv") || text.contains("destination") || text.contains("varis") || text.contains("hedef") {
            return "flag.checkered"
        }
        if text.contains("merge") || text.contains("katil") {
            return "arrow.triangle.merge"
        }
        let turn = side(of: text)
        let slight = text.contains("bear") || text.contains("slight") || text.contains("keep ")
            || text.contains("hafif") || text.contains("sap")
        let exit = text.contains("exit") || text.contains("ramp") || text.contains("cikis")
        if slight || exit {
            switch turn {
            case .left: return "arrow.up.left"
            case .right: return "arrow.up.right"
            case nil: return exit ? "arrow.up.right" : "arrow.up"
            }
        }
        switch turn {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case nil: return "arrow.up"
        }
    }

    private enum Side { case left, right }

    private static func folded(_ instruction: String) -> String {
        instruction
            .lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isUTurn(_ text: String) -> Bool {
        text.contains("u-turn") || text.contains("u turn") || text.contains("uturn")
            || text.contains("u don") || text.contains("geri don")
    }

    private static func side(of text: String) -> Side? {
        if text.contains("left") || text.contains("sola") || text.contains("links") || text.contains("gauche") {
            return .left
        }
        if text.contains("right") || text.contains("saga") || text.contains("rechts") || text.contains("droite") {
            return .right
        }
        return nil
    }
}

/// Where the vehicle sits on the planned route, and when to ask MapKit again.
/// Pure geometry — no MapKit, no SwiftData.
enum PlannedRouteProgress {
    /// Farther than this from the line counts as off route.
    static let offRouteMeters: CLLocationDistance = 75
    /// Consecutive off-route fixes before another reroute. The first miss of a departure
    /// does not wait for this many.
    static let offRouteFixes = 2
    /// A moving car aimed this far from the road ahead has missed the turn, even while
    /// it is still close to the junction.
    static let missedTurnDegrees: CLLocationDirection = 55
    static let missedTurnMinSpeed: CLLocationSpeed = 4
    /// MapKit directions are throttled. A further miss waits this long, not half a minute.
    static let rerouteInterval: TimeInterval = 8
    /// Quiet refresh while still on the road, so a longer drive from traffic can replace the countdown.
    static let trafficRefresh: TimeInterval = 180
    /// Inside this radius the trip has reached the destination and the route clears.
    static let arrivalMeters: CLLocationDistance = 50

    struct Measure: Equatable {
        /// Shortest distance from the vehicle to the route line.
        var offRouteMeters: CLLocationDistance
        /// Route length still ahead of the vehicle's projection.
        var remainingMeters: CLLocationDistance
        /// Direction of the nearest route segment, degrees clockwise from north.
        var segmentBearing: CLLocationDirection
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
        var bestBearing: CLLocationDirection = 0
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
                bestBearing = bearing(coordinates[index], coordinates[index + 1])
            }
        }

        guard bestDistance.isFinite else { return nil }
        return Measure(
            offRouteMeters: bestDistance,
            remainingMeters: max(0, total - bestAlong),
            segmentBearing: bestBearing
        )
    }

    /// The car has left the road it was meant to follow. One noisy fix is not enough;
    /// two in a row is the miss, whether that is distance or a wrong heading.
    static func confirmedMiss(offRouteStreak: Int) -> Bool {
        offRouteStreak >= offRouteFixes
    }

    /// True when a moving car is pointed away from the segment it is nearest to.
    static func missedTheTurn(
        course: CLLocationDirection,
        speed: CLLocationSpeed,
        routeBearing: CLLocationDirection
    ) -> Bool {
        guard speed >= missedTurnMinSpeed, course >= 0, routeBearing >= 0 else { return false }
        return angleDelta(course, routeBearing) >= missedTurnDegrees
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDirection {
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = metresPerDegreeLat * cos(a.latitude * .pi / 180)
        let east = (b.longitude - a.longitude) * metresPerDegreeLon
        let north = (b.latitude - a.latitude) * metresPerDegreeLat
        guard hypot(east, north) > 0.5 else { return -1 }
        var degrees = atan2(east, north) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    static func angleDelta(_ a: CLLocationDirection, _ b: CLLocationDirection) -> CLLocationDirection {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
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

    /// The next spoken step, and the distance until it starts.
    /// The step the car is on describes the road it is already on, so the banner names the one after it.
    /// The last step names itself. Empty Apple text is skipped. Distance is rounded to 10 m.
    static func upcomingManeuver(traveledMeters: CLLocationDistance, steps: [RouteStep]) -> UpcomingManeuver? {
        guard !steps.isEmpty else { return nil }
        var starts: [CLLocationDistance] = []
        starts.reserveCapacity(steps.count)
        var cursor: CLLocationDistance = 0
        for step in steps {
            starts.append(cursor)
            cursor += max(0, step.distanceMeters)
        }
        let traveled = min(max(0, traveledMeters), cursor)
        var index = 0
        for candidate in steps.indices where starts[candidate] <= traveled {
            index = candidate
        }
        let spoken = steps.indices.dropFirst(index + 1).first {
            !steps[$0].instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let chosen = spoken ?? index
        let text = steps[chosen].instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let target = spoken == nil ? cursor : starts[chosen]
        let distance = max(0, target - traveled)
        return UpcomingManeuver(
            distanceMeters: (distance / 10).rounded() * 10,
            instruction: text
        )
    }

    static func canRequest(lastRequestAt: Date?, now: Date, interval: TimeInterval = rerouteInterval) -> Bool {
        guard let lastRequestAt else { return true }
        return now.timeIntervalSince(lastRequestAt) >= interval
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

/// Destination entry while recording. Saved places and search stay available at any speed.
/// Typing is optional; the trip does not ask for it.
enum DestinationEntryPolicy {
    static let maxQueryLength = 120

    static func allowsSearch(speedMps _: Double, isPaused _: Bool) -> Bool {
        true
    }

    static func sanitizedQuery(_ raw: String) -> String {
        String(raw.prefix(maxQueryLength))
    }
}
