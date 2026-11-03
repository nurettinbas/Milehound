import CoreLocation

enum DistanceCalculator {
    static func totalDistance(for locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<locations.count {
            total += locations[index].distance(from: locations[index - 1])
        }
        return total
    }

    /// Douglas-Peucker polyline simplification in degree space (legacy callers).
    static func simplify(coordinates: [CLLocationCoordinate2D], tolerance: Double = 0.00005) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        return douglasPeucker(coordinates, epsilon: tolerance)
    }

    /// Douglas-Peucker with the tolerance expressed in meters.
    ///
    /// Degrees of longitude shrink with latitude, so raw degree deltas measure deviation
    /// unevenly (about 27% off at Izmir's latitude). Projecting to meters first keeps the
    /// tolerance geometrically honest.
    static func simplify(
        coordinates: [CLLocationCoordinate2D],
        toleranceMeters: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        let indices = simplifiedIndices(coordinates: coordinates, toleranceMeters: toleranceMeters)
        return indices.map { coordinates[$0] }
    }

    /// Indices of the coordinates Douglas-Peucker keeps — lets callers carry along per-point
    /// metadata (timestamps, speed) instead of re-matching coordinates afterwards.
    static func simplifiedIndices(
        coordinates: [CLLocationCoordinate2D],
        toleranceMeters: Double
    ) -> [Int] {
        guard coordinates.count > 2 else { return Array(coordinates.indices) }

        let referenceLatitude = coordinates[coordinates.count / 2].latitude
        let projected = coordinates.map { projectToMeters($0, referenceLatitude: referenceLatitude) }

        var keep = [Bool](repeating: false, count: coordinates.count)
        keep[0] = true
        keep[coordinates.count - 1] = true
        markKeptIndices(projected, start: 0, end: coordinates.count - 1, epsilon: toleranceMeters, keep: &keep)

        return coordinates.indices.filter { keep[$0] }
    }

    private struct ProjectedPoint {
        let x: Double
        let y: Double
    }

    /// Equirectangular projection — accurate enough for polyline deviation over a single trip.
    private static func projectToMeters(
        _ coordinate: CLLocationCoordinate2D,
        referenceLatitude: Double
    ) -> ProjectedPoint {
        let metersPerDegreeLatitude: Double = 111_132
        let metersPerDegreeLongitude = 111_320 * cos(referenceLatitude * .pi / 180)
        return ProjectedPoint(
            x: coordinate.longitude * metersPerDegreeLongitude,
            y: coordinate.latitude * metersPerDegreeLatitude
        )
    }

    /// Iterative Douglas-Peucker — avoids the deep recursion (and array copies) of the
    /// degree-space variant on multi-thousand-point routes.
    private static func markKeptIndices(
        _ points: [ProjectedPoint],
        start: Int,
        end: Int,
        epsilon: Double,
        keep: inout [Bool]
    ) {
        var stack: [(Int, Int)] = [(start, end)]

        while let (rangeStart, rangeEnd) = stack.popLast() {
            guard rangeEnd > rangeStart + 1 else { continue }

            var maxDistance: Double = 0
            var farthestIndex = rangeStart

            for index in (rangeStart + 1)..<rangeEnd {
                let distance = perpendicularDistanceMeters(
                    points[index],
                    lineStart: points[rangeStart],
                    lineEnd: points[rangeEnd]
                )
                if distance > maxDistance {
                    maxDistance = distance
                    farthestIndex = index
                }
            }

            guard maxDistance > epsilon, farthestIndex > rangeStart, farthestIndex < rangeEnd else { continue }
            keep[farthestIndex] = true
            stack.append((rangeStart, farthestIndex))
            stack.append((farthestIndex, rangeEnd))
        }
    }

    private static func perpendicularDistanceMeters(
        _ point: ProjectedPoint,
        lineStart: ProjectedPoint,
        lineEnd: ProjectedPoint
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        if dx == 0 && dy == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (dx * dx + dy * dy)
        let clampedT = max(0, min(1, t))
        return hypot(
            point.x - (lineStart.x + clampedT * dx),
            point.y - (lineStart.y + clampedT * dy)
        )
    }

    private static func douglasPeucker(_ points: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var maxDistance: Double = 0
        var index = 0
        let end = points.count - 1

        for i in 1..<end {
            let distance = perpendicularDistance(points[i], lineStart: points[0], lineEnd: points[end])
            if distance > maxDistance {
                maxDistance = distance
                index = i
            }
        }

        if maxDistance > epsilon {
            guard index > 0, index < end else {
                return [points[0], points[end]]
            }
            let left = douglasPeucker(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[index...end]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }

        return [points[0], points[end]]
    }

    private static func perpendicularDistance(
        _ point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        if dx == 0 && dy == 0 {
            return hypot(point.latitude - lineStart.latitude, point.longitude - lineStart.longitude)
        }
        let t = ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)
        let clampedT = max(0, min(1, t))
        let projLat = lineStart.latitude + clampedT * dy
        let projLon = lineStart.longitude + clampedT * dx
        return hypot(point.latitude - projLat, point.longitude - projLon)
    }
}
