import AppIntents
import Foundation
import SwiftData

/// Shortcuts-facing vehicle row (not the SwiftData `@Model`).
struct VehicleEntity: AppEntity, Identifiable, Hashable, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "shortcut.start.vehicle")
    }

    static let defaultQuery = VehicleEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    static func from(_ profile: VehicleProfile) -> VehicleEntity {
        VehicleEntity(id: profile.id, name: profile.name)
    }
}

struct VehicleEntityQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [VehicleEntity] {
        let wanted = Set(identifiers)
        return await loadAll().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [VehicleEntity] {
        await loadAll()
    }

    private func loadAll() async -> [VehicleEntity] {
        await MainActor.run {
            VehicleEntityQuery.fetchSortedEntities(
                from: AppServices.modelContainer.mainContext
            )
        }
    }

    /// Testable mapping — same sort used by Shortcuts suggestions.
    @MainActor
    static func fetchSortedEntities(from context: ModelContext) -> [VehicleEntity] {
        let descriptor = FetchDescriptor<VehicleProfile>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let profiles = (try? context.fetch(descriptor)) ?? []
        return profiles.map(VehicleEntity.from)
    }
}
