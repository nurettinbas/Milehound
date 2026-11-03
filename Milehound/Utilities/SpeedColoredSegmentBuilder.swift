import CoreLocation
import Foundation
import SwiftUI

/// Speed band used for route coloring. Thresholds match the previous green / yellow / red
/// legend; hysteresis stops short segments from flickering at the edges.
enum SpeedBand: Int, Comparable, CaseIterable {
    case slow = 0
    case medium = 1
    case fast = 2

    static let enterMediumKmh = 50.0
    static let enterFastKmh = 90.0
    static let hysteresisKmh = 5.0

    static func < (lhs: SpeedBand, rhs: SpeedBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func initial(kmh: Double) -> SpeedBand {
        if kmh < enterMediumKmh { return .slow }
        if kmh < enterFastKmh { return .medium }
        return .fast
    }

    mutating func update(kmh: Double) {
        switch self {
        case .slow:
            if kmh >= Self.enterFastKmh + Self.hysteresisKmh {
                self = .fast
            } else if kmh >= Self.enterMediumKmh + Self.hysteresisKmh {
                self = .medium
            }
        case .medium:
            if kmh < Self.enterMediumKmh - Self.hysteresisKmh {
                self = .slow
            } else if kmh >= Self.enterFastKmh + Self.hysteresisKmh {
                self = .fast
            }
        case .fast:
            if kmh < Self.enterMediumKmh - Self.hysteresisKmh {
                self = .slow
            } else if kmh < Self.enterFastKmh - Self.hysteresisKmh {
                self = .medium
            }
        }
    }

    var color: Color {
        switch self {
        case .slow: return .green
        case .medium: return .yellow
        case .fast: return .red
        }
    }
}

/// Builds speed-colored polyline segments with hysteresis and a hard overlay budget.
enum SpeedColoredSegmentBuilder {
    static let maxColorSegments = 60
    static let baseMinSegmentMeters: CLLocationDistance = 40

    static func build(pieces: [[RouteSample]]) -> [SpeedColoredSegment] {
        // Budget per piece first so a real gap can never be bridged by a merge, then a final
        // pass if the whole route still exceeds the overlay cap.
        var all: [SpeedColoredSegment] = []
        for piece in pieces where piece.count >= 2 {
            let capped = enforceBudget(buildRaw(piece: piece))
            for segment in capped {
                all.append(
                    SpeedColoredSegment(
                        id: all.count,
                        coordinates: segment.coordinates,
                        band: segment.band
                    )
                )
            }
        }
        if all.count > maxColorSegments {
            all = reindex(enforceBudget(all))
        }
        return all
    }

    /// Truncates already-built segments to `progress` without re-running speed coloring.
    static func revealed(
        segments: [SpeedColoredSegment],
        progress: Double
    ) -> [SpeedColoredSegment] {
        let clamped = min(1, max(0, progress))
        if clamped >= 1 { return segments }
        guard !segments.isEmpty else { return [] }

        let totalVertices = vertexCount(in: segments)
        guard totalVertices >= 2 else { return [] }

        let exact = Double(totalVertices - 1) * clamped
        let lastIndex = min(totalVertices - 1, Int(exact))
        let fraction = exact - Double(Int(exact))

        var result: [SpeedColoredSegment] = []
        var consumed = 0

        for segment in segments {
            let segmentVertices = segment.coordinates.count
            let sharedSkip = result.isEmpty ? 0 : overlapSkip(result.last?.coordinates, segment.coordinates)
            let newVertices = max(0, segmentVertices - sharedSkip)

            if consumed + newVertices <= lastIndex + 1 {
                result.append(
                    SpeedColoredSegment(
                        id: result.count,
                        coordinates: segment.coordinates,
                        band: segment.band
                    )
                )
                consumed += newVertices
                continue
            }

            let need = lastIndex + 1 - consumed
            guard need > 0 else { break }

            let endExclusive = sharedSkip + need
            guard endExclusive <= segment.coordinates.count else { break }

            var coords = Array(segment.coordinates[0..<endExclusive])
            if fraction > 0.001, endExclusive < segment.coordinates.count {
                let start = segment.coordinates[endExclusive - 1]
                let end = segment.coordinates[endExclusive]
                coords.append(
                    CLLocationCoordinate2D(
                        latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                        longitude: start.longitude + (end.longitude - start.longitude) * fraction
                    )
                )
            }
            if coords.count >= 2 {
                result.append(
                    SpeedColoredSegment(
                        id: result.count,
                        coordinates: coords,
                        band: segment.band
                    )
                )
            }
            break
        }

        return result
    }

    private static func buildRaw(piece: [RouteSample]) -> [SpeedColoredSegment] {
        guard piece.count >= 2 else { return [] }

        let firstKmh = (TripSpeedSummary.effectiveSpeedMps(at: 0, in: piece) ?? 0) * 3.6
        var band = SpeedBand.initial(kmh: firstKmh)
        var currentCoordinates = [piece[0].coordinate]
        var currentBand = band
        var segments: [SpeedColoredSegment] = []

        for index in 1..<piece.count {
            let kmh = (TripSpeedSummary.effectiveSpeedMps(at: index, in: piece) ?? 0) * 3.6
            band.update(kmh: kmh)
            currentCoordinates.append(piece[index].coordinate)

            guard band != currentBand else { continue }
            if currentCoordinates.count >= 2 {
                segments.append(
                    SpeedColoredSegment(
                        id: segments.count,
                        coordinates: currentCoordinates,
                        band: currentBand
                    )
                )
            }
            // Overlapping chord so MapKit paints a continuous stroke across the color join.
            currentCoordinates = [piece[index - 1].coordinate, piece[index].coordinate]
            currentBand = band
        }

        if currentCoordinates.count >= 2 {
            segments.append(
                SpeedColoredSegment(
                    id: segments.count,
                    coordinates: currentCoordinates,
                    band: currentBand
                )
            )
        }
        return segments
    }

    private static func enforceBudget(_ segments: [SpeedColoredSegment]) -> [SpeedColoredSegment] {
        guard segments.count > maxColorSegments else {
            return reindex(segments)
        }

        var minLength = baseMinSegmentMeters
        var current = segments
        for _ in 0..<8 {
            current = mergeShortSegments(current, minLengthMeters: minLength)
            if current.count <= maxColorSegments { break }
            minLength *= 2
        }

        if current.count > maxColorSegments {
            current = collapseToBudget(current, maxCount: maxColorSegments)
        }
        return reindex(current)
    }

    /// Merges segments shorter than `minLengthMeters` into their predecessor when they share
    /// the overlapping color-join chord. Never merges across a real route gap.
    private static func mergeShortSegments(
        _ segments: [SpeedColoredSegment],
        minLengthMeters: CLLocationDistance
    ) -> [SpeedColoredSegment] {
        guard !segments.isEmpty else { return [] }

        var result: [SpeedColoredSegment] = []
        for segment in segments {
            let length = pathLengthMeters(segment.coordinates)
            if let last = result.last,
               length < minLengthMeters,
               areColorAdjacent(last.coordinates, segment.coordinates) {
                var merged = last.coordinates
                appendMerging(&merged, segment.coordinates)
                result[result.count - 1] = SpeedColoredSegment(
                    id: last.id,
                    coordinates: merged,
                    band: last.band
                )
            } else {
                result.append(segment)
            }
        }
        return result
    }

    private static func collapseToBudget(
        _ segments: [SpeedColoredSegment],
        maxCount: Int
    ) -> [SpeedColoredSegment] {
        guard segments.count > maxCount, maxCount > 0 else { return segments }
        let groupSize = Int(ceil(Double(segments.count) / Double(maxCount)))
        var result: [SpeedColoredSegment] = []
        var index = 0
        while index < segments.count {
            var group = [segments[index]]
            var cursor = index + 1
            while group.count < groupSize, cursor < segments.count {
                let next = segments[cursor]
                guard areColorAdjacent(group[group.count - 1].coordinates, next.coordinates) else {
                    break
                }
                group.append(next)
                cursor += 1
            }
            var coords = group[0].coordinates
            for extra in group.dropFirst() {
                appendMerging(&coords, extra.coordinates)
            }
            result.append(
                SpeedColoredSegment(
                    id: result.count,
                    coordinates: coords,
                    band: group[0].band
                )
            )
            index = cursor
        }
        return result
    }

    /// Color joins store an overlapping two-point chord: previous ends with [A, B], next starts
    /// with [A, B, ...]. Real gaps have no such overlap.
    private static func areColorAdjacent(
        _ lhs: [CLLocationCoordinate2D],
        _ rhs: [CLLocationCoordinate2D]
    ) -> Bool {
        guard lhs.count >= 2, rhs.count >= 2 else { return false }
        return nearlyEqual(lhs[lhs.count - 2], rhs[0]) && nearlyEqual(lhs[lhs.count - 1], rhs[1])
    }

    private static func appendMerging(
        _ base: inout [CLLocationCoordinate2D],
        _ next: [CLLocationCoordinate2D]
    ) {
        if areColorAdjacent(base, next) {
            base.append(contentsOf: next.dropFirst(2))
        } else if let last = base.last, let first = next.first, nearlyEqual(last, first) {
            base.append(contentsOf: next.dropFirst())
        } else {
            base.append(contentsOf: next)
        }
    }

    private static func overlapSkip(
        _ previous: [CLLocationCoordinate2D]?,
        _ next: [CLLocationCoordinate2D]
    ) -> Int {
        guard let previous else { return 0 }
        if areColorAdjacent(previous, next) { return 2 }
        if let last = previous.last, let first = next.first, nearlyEqual(last, first) { return 1 }
        return 0
    }

    private static func nearlyEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 1e-12
            && abs(lhs.longitude - rhs.longitude) < 1e-12
    }

    private static func reindex(_ segments: [SpeedColoredSegment]) -> [SpeedColoredSegment] {
        segments.enumerated().map { index, segment in
            SpeedColoredSegment(id: index, coordinates: segment.coordinates, band: segment.band)
        }
    }

    private static func pathLengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 1..<coordinates.count {
            let previous = CLLocation(
                latitude: coordinates[index - 1].latitude,
                longitude: coordinates[index - 1].longitude
            )
            let current = CLLocation(
                latitude: coordinates[index].latitude,
                longitude: coordinates[index].longitude
            )
            total += current.distance(from: previous)
        }
        return total
    }

    private static func vertexCount(in segments: [SpeedColoredSegment]) -> Int {
        guard let first = segments.first else { return 0 }
        var total = first.coordinates.count
        var previous = first.coordinates
        for segment in segments.dropFirst() {
            total += max(0, segment.coordinates.count - overlapSkip(previous, segment.coordinates))
            previous = segment.coordinates
        }
        return total
    }
}
