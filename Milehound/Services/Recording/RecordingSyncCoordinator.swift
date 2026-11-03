import Foundation

@MainActor
enum RecordingSyncCoordinator {
    private static var lastSyncAt: Date?
    private static let minimumInterval: TimeInterval = 2

    static func shouldSync(now: Date = Date()) -> Bool {
        guard let lastSyncAt else {
            self.lastSyncAt = now
            return true
        }
        guard now.timeIntervalSince(lastSyncAt) >= minimumInterval else { return false }
        self.lastSyncAt = now
        return true
    }

    static func reset() {
        lastSyncAt = nil
    }
}
