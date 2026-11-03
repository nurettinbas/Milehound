import Foundation
import SwiftData

/// Where a trip notification can land. A deleted trip is `.missing` so the UI can warn
/// instead of closing the inbox onto an empty list.
enum TripDeepLinkResolution: Equatable {
    case finished(Trip)
    case recording
    /// The trip row still exists but has not ended and is not the live session (orphan).
    case unfinished
    case missing

    static func == (lhs: TripDeepLinkResolution, rhs: TripDeepLinkResolution) -> Bool {
        switch (lhs, rhs) {
        case (.recording, .recording), (.unfinished, .unfinished), (.missing, .missing):
            return true
        case (.finished(let lhsTrip), .finished(let rhsTrip)):
            return lhsTrip.id == rhsTrip.id
        default:
            return false
        }
    }
}

enum TripDeepLinkResolver {
    @MainActor
    static func resolve(
        tripID: UUID,
        in context: ModelContext,
        activeTripID: UUID?
    ) -> TripDeepLinkResolution {
        if tripID == activeTripID {
            return .recording
        }
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.id == tripID }
        )
        descriptor.fetchLimit = 1
        guard let trip = (try? context.fetch(descriptor))?.first else {
            return .missing
        }
        if trip.endedAt == nil {
            return .unfinished
        }
        return .finished(trip)
    }
}
