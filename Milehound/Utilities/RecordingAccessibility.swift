import Foundation

/// Combined VoiceOver label for the live recording card.
///
/// Kept pure and outside any view body on purpose: reading the ~4 Hz display sampler
/// (`displayElapsedTime` and friends) inside the card's own body subscribed the whole card
/// to it, rebuilding the glass surface, morph effects and vehicle picker four times a second.
enum RecordingAccessibility {
    static func summary(
        status: String,
        elapsed: TimeInterval,
        speedMps: Double,
        distanceMeters: Double
    ) -> String {
        String(
            format: L10n.string("recording.accessibility.summary"),
            status,
            DateFormatters.formatDuration(elapsed),
            speedText(speedMps: speedMps),
            DateFormatters.formatDistance(distanceMeters)
        )
    }

    static func speedText(speedMps: Double) -> String {
        "\(Int(max(0, speedMps) * 3.6)) \(L10n.speedKmh)"
    }
}
