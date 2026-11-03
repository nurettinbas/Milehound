import CoreLocation
import Foundation

/// Parking-stop markers during a trip — not GPS recording quality.
enum RecordingConfiguration {
    /// Below this speed (km/h), the car counts as stopped for parking-stop markers only.
    static let stopDetectionSpeedKmh: Double = 2
    /// How long speed must stay low before a parking stop is stored on the trip.
    static let minimumParkingStopDurationSeconds: TimeInterval = 120

    /// Shortest gap between two merged legs that still counts as the car having stopped.
    /// Below this the seam is a recording glitch, not somewhere the driver actually waited.
    static let minimumMergeJunctionStopSeconds: TimeInterval = 60

    /// A stop already recorded this close in time and space to a merge seam is the same
    /// standstill, so it gets extended instead of drawing a second marker on top of it.
    static let mergeJunctionAbsorbSeconds: TimeInterval = 120
    static let mergeJunctionAbsorbMeters: CLLocationDistance = 50
}
