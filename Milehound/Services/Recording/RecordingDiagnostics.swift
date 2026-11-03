import CoreLocation
import Foundation

/// Structured DevLog output for active trip recording — export this file after a bad trip.
@MainActor
enum RecordingDiagnostics {
    private static var activeTripID: UUID?
    private static var locationUpdates = 0
    private static var ignoredFixes = 0
    private static var accumulatedSegments = 0
    private static var gapResumes = 0
    private static var pointsPersisted = 0
    private static var distanceAccumulatedMeters: Double = 0
    private static var lastHeartbeat = Date.distantPast
    private static let heartbeatInterval: TimeInterval = 45
    private static var speedRejections: [String: Int] = [:]

    static func beginSession(
        tripID: UUID,
        authorization: LocationService.AuthorizationState,
        backgroundUpdatesEnabled: Bool
    ) {
        resetCounters()
        activeTripID = tripID
        DevLog.shared.log(
            .recording,
            "session start \(tripLabel(tripID)) auth=\(authorization) bgGPS=\(backgroundUpdatesEnabled)"
        )
    }

    static func endSession(
        tripID: UUID,
        saved: Bool,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        maxSpeedKmh: Double,
        pointCount: Int,
        reconciledDistanceMeters: Double?
    ) {
        logHeartbeat(force: true)
        let recon = reconciledDistanceMeters.map { " reconciled=\(Int($0))m" } ?? ""
        DevLog.shared.log(
            .recording,
            "session end \(tripLabel(tripID)) saved=\(saved) dist=\(Int(distanceMeters))m duration=\(Int(durationSeconds))s max=\(Int(maxSpeedKmh))km/h points=\(pointCount)\(recon) stats fixes=\(locationUpdates) ignore=\(ignoredFixes) accum=\(accumulatedSegments) gap=\(gapResumes) written=\(pointsPersisted)"
        )
        activeTripID = nil
        resetCounters()
    }

    static func logPaused(tripID: UUID?) {
        DevLog.shared.log(.recording, "paused \(tripLabel(tripID))")
    }

    static func logResumed(tripID: UUID?, orphanResume: Bool) {
        DevLog.shared.log(
            .recording,
            "resumed \(tripLabel(tripID)) orphan=\(orphanResume)"
        )
    }

    static func logLocationBatch(
        tripID: UUID?,
        batchSize: Int,
        acceptedCount: Int,
        lastAccuracyMeters: Int,
        lastAgeSeconds: Int
    ) {
        let resolvedTrip = tripID ?? activeTripID
        guard resolvedTrip != nil || batchSize > 1 || acceptedCount != batchSize else { return }
        DevLog.shared.log(
            .location,
            "batch \(tripLabel(resolvedTrip)) in=\(batchSize) accepted=\(acceptedCount) acc=\(lastAccuracyMeters)m age=\(lastAgeSeconds)s"
        )
    }

    static func logIncomingFix(
        tripID: UUID?,
        location: CLLocation,
        state: TripRecordingState
    ) {
        guard state == .recording else {
            DevLog.shared.log(
                .recording,
                "fix dropped \(tripLabel(tripID)) state=\(state) (not recording)"
            )
            return
        }
        locationUpdates += 1
    }

    static func logMovement(
        tripID: UUID?,
        decision: RecordingMovementPolicy.Decision,
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        accuracy: CLLocationAccuracy,
        locationSpeedKmh: Double,
        storedSpeedKmh: Double?,
        distanceMeters: Double,
        pointSequence: Int,
        mapNewSegment: Bool,
        ignoreReason: String? = nil
    ) {
        switch decision {
        case .ignore:
            ignoredFixes += 1
        case .accumulate:
            accumulatedSegments += 1
            distanceAccumulatedMeters += delta
        case .gapResume:
            gapResumes += 1
        }

        let shouldLogDetail = decision != .ignore
            || delta >= 10
            || timeDelta >= 5
            || (ignoreReason != nil && ignoreReason != "jitter")

        guard shouldLogDetail else {
            maybeHeartbeat(tripID: tripID, distanceMeters: distanceMeters, pointSequence: pointSequence)
            return
        }

        let speedGPS = locationSpeedKmh >= 0 ? String(format: "%.0f", locationSpeedKmh) : "—"
        let speedStored = storedSpeedKmh.map { String(format: "%.0f", $0) } ?? "—"
        let implied = timeDelta > 0 ? delta / timeDelta * 3.6 : 0
        var line = "move \(tripLabel(tripID)) \(decision) d=\(Int(delta))m dt=\(String(format: "%.1f", timeDelta))s acc=\(Int(accuracy))m gps=\(speedGPS) impl=\(String(format: "%.0f", implied)) stored=\(speedStored) dist=\(Int(distanceMeters))m pt=\(pointSequence)"
        // routeBreak+ = recorder starts a new map polyline piece (not a speed-color band).
        if mapNewSegment { line += " routeBreak+" }
        if let ignoreReason { line += " why=\(ignoreReason)" }
        if decision == .gapResume {
            DevLog.shared.warning(.recording, line)
        } else {
            DevLog.shared.log(.recording, line)
        }
        maybeHeartbeat(tripID: tripID, distanceMeters: distanceMeters, pointSequence: pointSequence)
    }

    static func logPointPersisted(tripID: UUID?, sequence: Int, batchSave: Bool) {
        pointsPersisted += 1
        if sequence == 0 || sequence % 100 == 0 {
            DevLog.shared.log(
                .recording,
                "point \(tripLabel(tripID)) seq=\(sequence) batchSave=\(batchSave)"
            )
        }
    }

    static func logPersistFailure(tripID: UUID?, error: String) {
        DevLog.shared.error(.recording, "persist failed \(tripLabel(tripID)): \(error)")
    }

    static func logReconcile(tripID: UUID?, liveMeters: Double, fromPointsMeters: Double) {
        let delta = Int(liveMeters - fromPointsMeters)
        if abs(delta) >= 50 {
            DevLog.shared.log(
                .recording,
                "reconcile \(tripLabel(tripID)) live=\(Int(liveMeters))m points=\(Int(fromPointsMeters))m delta=\(delta)m"
            )
        }
    }

    /// A fix whose position was kept but whose speed was not believed. Logged once per reason and
    /// then every 20th time, because a long tunnel would otherwise fill the log with one line.
    static func logSpeedRejected(
        tripID: UUID?,
        reason: String,
        reportedKmh: Double,
        speedAccuracyMps: Double,
        accuracyMeters: CLLocationAccuracy,
        ageSeconds: TimeInterval
    ) {
        let count = (speedRejections[reason] ?? 0) + 1
        speedRejections[reason] = count
        guard count == 1 || count.isMultiple(of: 20) else { return }

        DevLog.shared.log(
            .recording,
            "speed rejected \(tripLabel(tripID)) why=\(reason) gps=\(String(format: "%.0f", reportedKmh))km/h spdAcc=\(String(format: "%.1f", speedAccuracyMps)) acc=\(Int(accuracyMeters))m age=\(String(format: "%.1f", ageSeconds))s n=\(count)"
        )
    }

    static func logUnusableFix(
        accuracy: CLLocationAccuracy,
        ageSeconds: TimeInterval,
        trackingFull: Bool
    ) {
        DevLog.shared.log(
            .location,
            "fix rejected acc=\(Int(accuracy))m age=\(Int(ageSeconds))s tracking=\(trackingFull ? "full" : "off")"
        )
    }

    private static func maybeHeartbeat(tripID: UUID?, distanceMeters: Double, pointSequence: Int) {
        logHeartbeat(
            force: false,
            tripID: tripID,
            distanceMeters: distanceMeters,
            pointSequence: pointSequence
        )
    }

    private static func logHeartbeat(
        force: Bool,
        tripID: UUID? = nil,
        distanceMeters: Double = 0,
        pointSequence: Int = 0
    ) {
        let now = Date()
        guard force || now.timeIntervalSince(lastHeartbeat) >= heartbeatInterval else { return }
        lastHeartbeat = now
        DevLog.shared.log(
            .recording,
            "heartbeat \(tripLabel(tripID ?? activeTripID)) fixes=\(locationUpdates) ignore=\(ignoredFixes) accum=\(accumulatedSegments) gap=\(gapResumes) dist=\(Int(distanceMeters))m pt=\(pointSequence) written=\(pointsPersisted)"
        )
    }

    private static func tripLabel(_ id: UUID?) -> String {
        guard let id else { return "trip=—" }
        return "trip=\(id.uuidString.prefix(8))"
    }

    private static func resetCounters() {
        locationUpdates = 0
        ignoredFixes = 0
        accumulatedSegments = 0
        gapResumes = 0
        pointsPersisted = 0
        distanceAccumulatedMeters = 0
        lastHeartbeat = Date.distantPast
        speedRejections = [:]
    }
}

extension RecordingMovementPolicy {
    static func ignoreReason(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        locationSpeedMps: Double
    ) -> String? {
        guard decision(delta: delta, timeDelta: timeDelta, locationSpeedMps: locationSpeedMps) == .ignore
        else { return nil }
        if delta < minimumDistanceSampleMeters { return "jitter" }
        if timeDelta < minimumMovementTimeDeltaSeconds { return "convergence" }
        let implied = delta / max(0.01, timeDelta)
        let movement = locationSpeedMps > 0 ? locationSpeedMps : implied
        if movement < stationarySpeedMps, delta < stationaryDistanceMeters {
            return "stationary"
        }
        return "unknown"
    }
}
