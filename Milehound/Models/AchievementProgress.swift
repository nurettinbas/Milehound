import Foundation
import SwiftData

/// Persisted progress for one catalog achievement. Unlocks are not revoked on delete.
@Model
final class AchievementProgress {
    var achievementID: String = ""
    var currentValue: Double = 0
    var unlockedAt: Date?
    var seenAt: Date?

    init(achievementID: String, currentValue: Double = 0) {
        self.achievementID = achievementID
        self.currentValue = currentValue
    }

    var isUnlocked: Bool { unlockedAt != nil }
    var needsCelebration: Bool { unlockedAt != nil && seenAt == nil }
}
