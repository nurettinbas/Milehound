import Foundation
import SwiftData

/// Distinct privacy-safe city names seen on completed trips. Derived; used for city achievements.
@Model
final class VisitedLocality {
    var name: String = ""
    var visitCount: Int = 0

    init(name: String, visitCount: Int = 1) {
        self.name = name
        self.visitCount = visitCount
    }
}
