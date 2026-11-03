import CoreLocation
import Foundation

@Observable
final class LocationService: NSObject {
    enum AuthorizationState: Equatable {
        case notDetermined
        case authorizedWhenInUse
        case authorizedAlways
        case denied
        case restricted
    }

    enum TrackingMode {
        case off
        case full
    }

    enum GPSQuality: Equatable {
        case good
        case weak
        case lost
    }

    private(set) var authorizationState: AuthorizationState = .notDetermined
    private(set) var lastLocation: CLLocation?
    private(set) var trackingMode: TrackingMode = .off

    var gpsQuality: GPSQuality {
        guard let lastLocation else { return .lost }
        let age = Date().timeIntervalSince(lastLocation.timestamp)
        if age > 30 { return .lost }
        if lastLocation.horizontalAccuracy < 0 || lastLocation.horizontalAccuracy > 80 { return .weak }
        return .good
    }

    var onLocationUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var isUpdating = false
    private var lastLoggedBackgroundUpdates: Bool?
    private var lastLoggedTrackingFull: Bool?

    var canRecordInBackground: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        updateAuthorizationState(from: manager.authorizationStatus)
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startTracking() {
        trackingMode = .full
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        DevLog.shared.log(.location, "startTracking: bestNavigation distanceFilter=none")
        startIfNeeded()
    }

    func stopTracking() {
        trackingMode = .off
        DevLog.shared.log(.location, "stopTracking")
        manager.pausesLocationUpdatesAutomatically = true
        applyBackgroundConfiguration()
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func startIfNeeded() {
        guard !isUpdating else {
            applyBackgroundConfiguration()
            return
        }
        applyBackgroundConfiguration()
        isUpdating = true
        manager.startUpdatingLocation()
    }

    private func applyBackgroundConfiguration() {
        let canUseBackground = manager.authorizationStatus == .authorizedAlways
        let needsBackground = canUseBackground && trackingMode != .off
        let trackingFull = trackingMode == .full

        manager.allowsBackgroundLocationUpdates = needsBackground
        manager.showsBackgroundLocationIndicator = trackingFull && needsBackground

        if lastLoggedBackgroundUpdates != needsBackground || lastLoggedTrackingFull != trackingFull {
            lastLoggedBackgroundUpdates = needsBackground
            lastLoggedTrackingFull = trackingFull
            DevLog.shared.log(
                .location,
                "background config: always=\(canUseBackground) tracking=\(trackingFull ? "full" : "off") bgUpdates=\(needsBackground)"
            )
        }
    }

    private func updateAuthorizationState(from status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            authorizationState = .authorizedAlways
        case .authorizedWhenInUse:
            authorizationState = .authorizedWhenInUse
        case .denied:
            authorizationState = .denied
        case .restricted:
            authorizationState = .restricted
        case .notDetermined:
            authorizationState = .notDetermined
        @unknown default:
            authorizationState = .notDetermined
        }
    }

    private func isLocationUsable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        if trackingMode == .full, location.horizontalAccuracy > 400 { return false }
        if Date().timeIntervalSince(location.timestamp) > 120 { return false }
        return true
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationState(from: manager.authorizationStatus)
        applyBackgroundConfiguration()
        DevLog.shared.log(
            .location,
            "authorization -> \(authorizationState) tracking=\(trackingMode == .full ? "full" : "off")"
        )
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var accepted = 0
        var lastAccepted: CLLocation?
        for location in locations {
            guard isLocationUsable(location) else {
                let age = Date().timeIntervalSince(location.timestamp)
                let accuracy = location.horizontalAccuracy
                let trackingFull = trackingMode == .full
                Task { @MainActor in
                    RecordingDiagnostics.logUnusableFix(
                        accuracy: accuracy,
                        ageSeconds: age,
                        trackingFull: trackingFull
                    )
                }
                continue
            }
            accepted += 1
            lastAccepted = location
            lastLocation = location
            onLocationUpdate?(location)
        }
        if let lastAccepted {
            let age = Int(Date().timeIntervalSince(lastAccepted.timestamp))
            Task { @MainActor in
                RecordingDiagnostics.logLocationBatch(
                    tripID: nil,
                    batchSize: locations.count,
                    acceptedCount: accepted,
                    lastAccuracyMeters: Int(lastAccepted.horizontalAccuracy),
                    lastAgeSeconds: age
                )
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DevLog.shared.error(.location, "location fail: \(error.localizedDescription)")
    }
}
