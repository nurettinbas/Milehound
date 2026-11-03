import Foundation
import SwiftData

/// Conservative locality fill for pre-V21 trips: privacy zones stay blank; saved-place
/// names are never treated as cities. Future reverse-geocode writes `CLPlacemark.locality`.
@ModelActor
actor TripLocalityBackfiller {
    private static let batchSize = 50
    private static let versionKey = "milehound.derived.localityBackfillVersion"
    private static let version = 1

    func run(privacyRadius: Double) async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.versionKey) < Self.version else { return }

        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        var offset = 0
        while !Task.isCancelled {
            // Keep the predicate to one stored field so SwiftData can type-check it on the
            // live Trip model (journal + smart-category + locality columns).
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize
            let batch = (try? modelContext.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }

            for trip in batch {
                if trip.startLocality != nil || trip.endLocality != nil { continue }
                TripLocalityResolver.apply(
                    to: trip,
                    startLocality: nil,
                    startCountryCode: nil,
                    endLocality: nil,
                    endCountryCode: nil,
                    places: places,
                    privacyRadius: privacyRadius
                )
                trip.invalidatePointCaches()
            }
            try? modelContext.save()
            offset += batch.count
            await Task.yield()
        }

        defaults.set(Self.version, forKey: Self.versionKey)
    }
}

enum TripLocalityBackfillService {
    static func backfillIfNeeded(container: ModelContainer, privacyRadius: Double) async {
        await TripLocalityBackfiller(modelContainer: container).run(privacyRadius: privacyRadius)
    }
}
