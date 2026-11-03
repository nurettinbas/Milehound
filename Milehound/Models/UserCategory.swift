import Foundation
import SwiftData

@Model
final class UserCategory {
    var id: UUID
    var name: String
    var systemImage: String
    var isBuiltIn: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        systemImage: String = "tag.fill",
        isBuiltIn: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
    }

    var storageKey: String {
        id.uuidString
    }
}

enum BuiltInCategory {
    static let personalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let businessID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
}
