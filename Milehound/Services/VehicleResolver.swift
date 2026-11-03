import Foundation
import SwiftData

enum VehicleResolver {
    @MainActor
    static func resolveActiveVehicle(
        in context: ModelContext,
        settings: AppSettings = .shared
    ) -> VehicleProfile? {
        resolveActiveVehicle(from: fetchVehicles(in: context), settings: settings)
    }

    /// Fetch-free variant for views that already hold a `@Query` result. Fetching inside a
    /// view body made scrolling hit the store on every frame.
    @MainActor
    static func resolveActiveVehicle(
        from vehicles: [VehicleProfile],
        settings: AppSettings = .shared
    ) -> VehicleProfile? {
        guard !vehicles.isEmpty else { return nil }

        if let preferredID = settings.recordingVehicleID,
           let match = vehicles.first(where: { $0.id == preferredID }) {
            return match
        }

        return vehicles.first(where: \.isDefault) ?? vehicles.first
    }

    static func vehicle(withID id: UUID, in context: ModelContext) -> VehicleProfile? {
        fetchVehicles(in: context).first { $0.id == id }
    }

    static func assign(vehicle: VehicleProfile?, to trip: Trip) {
        trip.vehicleID = vehicle?.id
        trip.vehicle = nil
    }

    private static func fetchVehicles(in context: ModelContext) -> [VehicleProfile] {
        (try? context.fetch(FetchDescriptor<VehicleProfile>())) ?? []
    }
}
