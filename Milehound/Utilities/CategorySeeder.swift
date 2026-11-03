import Foundation
import SwiftData

enum CategorySeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<UserCategory>())) ?? []
        guard existing.isEmpty else { return }

        let defaults: [(UUID, String, String, Int)] = [
            (BuiltInCategory.personalID, L10n.categoryPersonal, "person.fill", 0),
            (BuiltInCategory.businessID, L10n.categoryBusiness, "briefcase.fill", 1)
        ]

        for (id, name, icon, order) in defaults {
            let category = UserCategory(id: id, name: name, systemImage: icon, isBuiltIn: true, sortOrder: order)
            context.insert(category)
        }
        try? context.save()
    }
}
