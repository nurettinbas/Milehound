import Foundation

/// Limits how often live recording UI snapshots refresh (GPS may update faster).
struct RecordingDisplaySampler: Equatable {
    var minimumInterval: TimeInterval = 0.25
    private(set) var lastPublishedAt: Date?

    mutating func shouldPublish(now: Date) -> Bool {
        guard let lastPublishedAt else {
            self.lastPublishedAt = now
            return true
        }
        guard now.timeIntervalSince(lastPublishedAt) >= minimumInterval else { return false }
        self.lastPublishedAt = now
        return true
    }

    mutating func markPublished(now: Date) {
        lastPublishedAt = now
    }

    mutating func reset() {
        lastPublishedAt = nil
    }
}
