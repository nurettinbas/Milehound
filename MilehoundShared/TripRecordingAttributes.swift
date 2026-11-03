import ActivityKit
import Foundation

struct TripRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var distanceMeters: Double
        var currentSpeedKmh: Int
        var isPaused: Bool
        /// Side-profile SF Symbol for Dynamic Island / lock banner (fallback `car.side.fill`).
        var vehicleSystemImage: String
        /// `scaleEffect(x:)` so the symbol faces right.
        var vehicleSymbolScaleX: Double
        /// App Group mark revision; omit when using the SF Symbol. Bytes are not in ContentState.
        var vehiclePhotoRevision: String?
        /// Wall-clock start for `Text(timerInterval:)` so duration ticks locally without ActivityKit pushes.
        var effectiveStartedAt: Date?

        init(
            elapsedSeconds: Int,
            distanceMeters: Double,
            currentSpeedKmh: Int,
            isPaused: Bool,
            vehicleSystemImage: String = "car.side.fill",
            vehicleSymbolScaleX: Double = -1,
            vehiclePhotoRevision: String? = nil,
            effectiveStartedAt: Date? = nil
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.distanceMeters = distanceMeters
            self.currentSpeedKmh = currentSpeedKmh
            self.isPaused = isPaused
            self.vehicleSystemImage = vehicleSystemImage
            self.vehicleSymbolScaleX = vehicleSymbolScaleX
            self.vehiclePhotoRevision = vehiclePhotoRevision
            self.effectiveStartedAt = effectiveStartedAt
        }

        /// Anchor for a count-up timer. Pause-adjusted when `effectiveStartedAt` was published.
        func durationAnchor(fallbackStartedAt: Date? = nil) -> Date {
            if let effectiveStartedAt { return effectiveStartedAt }
            if let fallbackStartedAt { return fallbackStartedAt }
            return Date().addingTimeInterval(-TimeInterval(max(0, elapsedSeconds)))
        }
    }

    var startedAt: Date
}
