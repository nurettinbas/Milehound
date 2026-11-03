import Foundation
import SwiftData

@Model
final class TravelJournal {
    var id: UUID
    var title: String
    var startedOn: Date
    var endedOn: Date
    var coverTripID: UUID?
    var note: String?
    /// Denormalized member count — list rows must not fault `trips`.
    var tripCount: Int
    /// Denormalized sum of member `distanceMeters`.
    var distanceMeters: Double
    /// Denormalized sum of avg fuel (`estimatedFuelCost`, with catalog fallback).
    var fuelCost: Double
    var searchIndex: String?
    /// Comma-separated trip UUIDs for the mosaic (cover first, then next-longest). Fits the 2×2 list tile.
    var mosaicTripIDsRaw: String

    static let mosaicSlotCount = 4

    @Relationship(deleteRule: .nullify, inverse: \Trip.journal)
    var trips: [Trip]

    init(
        id: UUID = UUID(),
        title: String,
        startedOn: Date = Date(),
        endedOn: Date = Date(),
        coverTripID: UUID? = nil,
        note: String? = nil,
        tripCount: Int = 0,
        distanceMeters: Double = 0,
        fuelCost: Double = 0,
        searchIndex: String? = nil,
        mosaicTripIDsRaw: String = "",
        trips: [Trip] = []
    ) {
        self.id = id
        self.title = title
        self.startedOn = startedOn
        self.endedOn = endedOn
        self.coverTripID = coverTripID
        self.note = note
        self.tripCount = tripCount
        self.distanceMeters = distanceMeters
        self.fuelCost = fuelCost
        self.searchIndex = searchIndex
        self.mosaicTripIDsRaw = mosaicTripIDsRaw
        self.trips = trips
    }

    var mosaicTripIDs: [UUID] {
        mosaicTripIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
    }
}
