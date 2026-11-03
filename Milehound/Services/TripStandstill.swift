import CoreLocation
import Foundation
import SwiftData

/// A stretch of time the vehicle spent standing still, ready to be written onto a trip.
///
/// `TripMergeService` produces one for the seam between two merged legs, where the car was
/// parked while nothing was recording. Deciding what to write — leave it alone, lengthen the
/// marker that is already there, or add a new one — lives here rather than in the merge so the
/// merge stays about combining legs.
struct TripStandstill {
    let coordinate: CLLocationCoordinate2D
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// Something already covers part of this period, so writing another marker would stack two
    /// pins on the same spot.
    func isAlreadyMarked(by stop: TripStop) -> Bool {
        let stopEnd = stop.startedAt.addingTimeInterval(stop.durationSeconds)
        return stopEnd > startedAt && stop.startedAt < endedAt
    }

    /// The same standstill seen from the other side: the vehicle was already parked here when
    /// the recording stopped, so this period continues that marker instead of following it.
    func continues(_ stop: TripStop) -> Bool {
        let stopEnd = stop.startedAt.addingTimeInterval(stop.durationSeconds)
        let elapsed = startedAt.timeIntervalSince(stopEnd)
        guard elapsed >= 0, elapsed <= RecordingConfiguration.mergeJunctionAbsorbSeconds else {
            return false
        }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let there = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        return here.distance(from: there) <= RecordingConfiguration.mergeJunctionAbsorbMeters
    }

    /// Returns false when `candidates` already cover this period and nothing was written.
    @discardableResult
    func apply(to trip: Trip, candidates: [TripStop], context: ModelContext) -> Bool {
        guard !candidates.contains(where: isAlreadyMarked) else { return false }

        if let adjacent = candidates.first(where: continues) {
            adjacent.durationSeconds = endedAt.timeIntervalSince(adjacent.startedAt)
            return true
        }

        let stop = TripStop(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            startedAt: startedAt,
            durationSeconds: duration,
            trip: trip
        )
        trip.stops.append(stop)
        context.insert(stop)
        return true
    }
}
