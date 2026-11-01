import CoreLocation
import Foundation
import SwiftData
import UIKit
import WidgetKit

/// Compact vehicle identity for Live Activity / Dynamic Island updates.
struct RecordingVehicleMarkSnapshot: Equatable, Hashable, Sendable {
    var systemImage: String
    var symbolScaleX: Double
    /// App Group mark revision written before ActivityKit publish; nil → SF Symbol.
    var photoRevision: String?

    static let fallback = RecordingVehicleMarkSnapshot(
        systemImage: "car.side.fill",
        symbolScaleX: -1,
        photoRevision: nil
    )

    /// Revision by source photo file name — write App Group mark once per session photo.
    @MainActor private static var revisionByFileName: [String: String] = [:]

    @MainActor
    static func makeCached(for vehicle: VehicleProfile?) -> RecordingVehicleMarkSnapshot {
        let photoRevision = publishMarkRevision(fileName: vehicle?.photoFileName)
        return RecordingVehicleMarkSnapshot(
            systemImage: fallback.systemImage,
            symbolScaleX: fallback.symbolScaleX,
            photoRevision: photoRevision
        )
    }

    @MainActor
    static func clearCompactPNGCache(fileName: String? = nil) {
        if let fileName {
            revisionByFileName.removeValue(forKey: fileName)
        } else {
            revisionByFileName.removeAll()
            LiveActivityVehicleMarkStore.clear()
        }
    }

    /// Writes the vehicle thumb into the App Group (full size, no studio punch) and returns the revision.
    /// Punch (`markImageForDisplay`) is road-scene only — on Live Activity it turns light cars into silhouettes.
    @MainActor
    private static func publishMarkRevision(fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty else { return nil }
        if let cached = revisionByFileName[fileName] { return cached }
        guard let image = VehiclePhotoStore.shared.imageSync(fileName: fileName) else {
            DevLog.shared.log(.widget, "Live Activity mark: thumb not on disk", level: .warning)
            return nil
        }
        if VehiclePhotoStore.markImageIsVisuallyEmpty(image) {
            DevLog.shared.log(
                .widget,
                "Live Activity mark: photo unusable; using SF Symbol",
                level: .warning
            )
            return nil
        }
        guard let revision = LiveActivityVehicleMarkStore.write(image) else {
            DevLog.shared.log(
                .widget,
                "Live Activity mark: App Group write failed; using SF Symbol",
                level: .warning
            )
            return nil
        }
        revisionByFileName[fileName] = revision
        return revision
    }
}

enum TripRecordingState: Equatable {
    case idle
    case recording
    case paused

    var isActiveSession: Bool {
        self == .recording || self == .paused
    }
}

@MainActor
@Observable
final class TripRecordingService {
    private(set) var state: TripRecordingState = .idle {
        didSet { Self.sessionIsActive = state.isActiveSession }
    }

    /// Read by care reminders so a kilometre push never fires while a trip is recording or paused.
    static var sessionIsActive = false
    private(set) var currentDistanceMeters: Double = 0
    private(set) var currentSpeedMps: Double = 0
    private(set) var recordingStartedAt: Date?
    private(set) var elapsedTime: TimeInterval = 0
    /// Live breadcrumb path for the active session (updates as points are recorded).
    private(set) var liveBreadcrumbCoordinates: [CLLocationCoordinate2D] = []
    /// Breadcrumb polylines split at GPS gaps (no straight chords over missing data).
    private(set) var liveBreadcrumbSegments: [[CLLocationCoordinate2D]] = []
    /// Parking / user-pause stops for the active session (live follow map pins).
    private(set) var liveStopCoordinates: [CLLocationCoordinate2D] = []
    /// Live-map destination and planned route. Memory only; cleared when the session ends.
    let plannedRoute = PlannedRouteStore()

    /// Throttled snapshots for on-screen recording UI (see `RecordingDisplaySampler`).
    private(set) var displayElapsedTime: TimeInterval = 0
    private(set) var displayDistanceMeters: Double = 0
    private(set) var displaySpeedMps: Double = 0

    var activeTripID: UUID? { activeTrip?.id }

    private let locationService: LocationService
    private let settings: AppSettings
    private var displaySampler = RecordingDisplaySampler()

    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?
    private var activeTrip: Trip?
    private var lastRecordedLocation: CLLocation?
    private var pointSequence = 0
    private var pointsSinceLastSave = 0
    private let saveBatchSize = 10
    private var elapsedTimer: Timer?
    @ObservationIgnored nonisolated(unsafe) private var elapsedTimerTarget: ElapsedTimerTarget?
    private var maxSpeedMps: Double = 0
    /// Last speed that passed every trust gate, so the next one can be checked for a physically
    /// impossible jump.
    private var lastTrustedSpeedMps: Double?
    private var currentStopStartedAt: Date?
    private var currentStopCoordinate: CLLocationCoordinate2D?
    /// Manual pause pin — persisted as `TripStop` on resume when long enough.
    private var userPauseStartedAt: Date?
    private var userPauseCoordinate: CLLocationCoordinate2D?

    private var stopSpeedMps: Double {
        RecordingConfiguration.stopDetectionSpeedKmh / 3.6
    }

    /// Bumped when the recording vehicle changes so SwiftUI surfaces re-read trip.vehicleID
    /// (mutating a SwiftData property on `activeTrip` alone does not invalidate `@Observable`).
    private(set) var recordingVehicleEpoch: UInt = 0

    /// Reuse last Live Activity mark while vehicle identity is unchanged (avoids PNG churn).
    private var lastLiveActivityMarkIdentity: String?
    private var lastLiveActivityMark: RecordingVehicleMarkSnapshot?
    /// Ensures the trip-started inbox body is upgraded to "From …" once GPS/place is known.
    private var didRefreshTripStartedPlaceBody = false

    private static weak var elapsedTimerService: TripRecordingService?

    init(
        locationService: LocationService,
        settings: AppSettings = .shared
    ) {
        self.locationService = locationService
        self.settings = settings

        locationService.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                self?.handleLocationUpdate(location)
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.modelContainer = modelContext.container
    }

    /// Persists the vehicle for new trips, marks it default in Pairing, and updates the active trip if recording.
    func setRecordingVehicle(_ vehicleID: UUID) {
        guard let modelContext else { return }
        guard let vehicle = VehicleResolver.vehicle(withID: vehicleID, in: modelContext) else { return }

        settings.recordingVehicleID = vehicleID
        VehiclePairingService.setDefaultVehicle(vehicle, in: modelContext)

        if let trip = activeTrip {
            VehicleResolver.assign(vehicle: vehicle, to: trip)
            try? modelContext.save()
        }

        // Invalidate sticky Live Activity mark *before* any concurrent timer sync can
        // cache a nil-photo snapshot for this identity (race with thumb warm).
        recordingVehicleEpoch &+= 1
        lastLiveActivityMarkIdentity = nil
        lastLiveActivityMark = nil
        if let fileName = vehicle.photoFileName {
            RecordingVehicleMarkSnapshot.clearCompactPNGCache(fileName: fileName)
        }

        guard state.isActiveSession else { return }
        // Immediate publish (imageSync can read disk even when memory is cold).
        syncExternalState(force: true)
        Task {
            guard let fileName = vehicle.photoFileName else { return }
            _ = await VehiclePhotoStore.shared.image(fileName: fileName)
            lastLiveActivityMarkIdentity = nil
            lastLiveActivityMark = nil
            RecordingVehicleMarkSnapshot.clearCompactPNGCache(fileName: fileName)
            syncExternalState(force: true)
        }
    }

    /// Selected vehicle for Live Activity / intents (photo + side icon).
    func activeRecordingVehicleForLiveActivity() -> VehicleProfile? {
        guard let modelContext else { return nil }
        if let trip = activeTrip, let id = trip.vehicleID {
            return VehicleResolver.vehicle(withID: id, in: modelContext)
        }
        return VehicleResolver.resolveActiveVehicle(in: modelContext, settings: settings)
    }

    private func liveActivityVehicleMark() -> RecordingVehicleMarkSnapshot {
        let vehicle = activeRecordingVehicleForLiveActivity()
        let identity = [
            vehicle?.id.uuidString ?? "",
            vehicle?.photoFileName ?? "",
            "\(recordingVehicleEpoch)"
        ].joined(separator: "|")
        if identity == lastLiveActivityMarkIdentity,
           let lastLiveActivityMark,
           // Never reuse a symbol-only mark while the vehicle still has a photo file —
           // a concurrent sync can race ahead of thumb warm and stick on nil forever.
           lastLiveActivityMark.photoRevision != nil || vehicle?.photoFileName == nil {
            return lastLiveActivityMark
        }
        let mark = RecordingVehicleMarkSnapshot.makeCached(for: vehicle)
        // Only pin the cache when complete (photo attached or no photo expected).
        if mark.photoRevision != nil || vehicle?.photoFileName == nil {
            lastLiveActivityMarkIdentity = identity
            lastLiveActivityMark = mark
        }
        return mark
    }

    /// Prefetch thumb then republish Live Activity so Dynamic Island can show the photo.
    private func warmLiveActivityVehiclePhoto() async {
        guard let vehicle = activeRecordingVehicleForLiveActivity(),
              let fileName = vehicle.photoFileName else { return }
        _ = await VehiclePhotoStore.shared.image(fileName: fileName)
        // Drop cached mark so Compact PNG can attach after a cold cache miss.
        lastLiveActivityMarkIdentity = nil
        lastLiveActivityMark = nil
        RecordingVehicleMarkSnapshot.clearCompactPNGCache(fileName: fileName)
        guard state.isActiveSession else { return }
        syncExternalState(force: true)
    }

    func activeRecordingVehicleID(in context: ModelContext) -> UUID? {
        if let trip = activeTrip, let id = trip.vehicleID {
            return id
        }
        return VehicleResolver.resolveActiveVehicle(in: context, settings: settings)?.id
    }

    /// For views that already hold a `@Query` vehicle list — avoids a store fetch per body pass.
    func activeRecordingVehicleID(from vehicles: [VehicleProfile]) -> UUID? {
        if let trip = activeTrip, let id = trip.vehicleID {
            return id
        }
        return VehicleResolver.resolveActiveVehicle(from: vehicles, settings: settings)?.id
    }

    func stopIdleServices() {
        locationService.stopTracking()
        stopElapsedTimer()
    }

    @discardableResult
    func startManualRecording() -> Bool {
        guard state == .idle else { return false }
        DevLog.shared.log(.recording, "startManualRecording")
        beginRecording(trigger: .manual)
        return state == .recording
    }

    func stopManualRecording() {
        DevLog.shared.log(.recording, "stopManualRecording (state=\(state))")
        settings.pendingStopRecordingRequest = false
        switch state {
        case .recording, .paused:
            stopRecording(saveTrip: true)
        case .idle:
            break
        }
    }

    func discardActiveRecordingSession() {
        if settings.awaitingExternalStartConfirmation {
            cancelExternalStartRecording()
            return
        }
        guard state.isActiveSession else { return }
        stopRecording(saveTrip: false)
    }

    func processExternalStartRequest() {
        DevLog.shared.log(.recording, "processExternalStartRequest (state: \(state))")
        let isWizardTest = ShortcutsSetupStore.shared.consumeTestInFlight()
        defer {
            if !isWizardTest, ShortcutsSetupStore.shared.consumePendingWatchIfReached() {
                if !UITestSupport.isUnitTesting {
                    ToastPresenter.shared.show(.shortcutsAutomationReached)
                }
            }
        }
        guard state == .idle else {
            settings.pendingStartRecordingRequest = false
            settings.awaitingExternalStartConfirmation = false
            return
        }

        settings.pendingStopRecordingRequest = false
        settings.pendingPauseRecordingRequest = false
        settings.pendingResumeRecordingRequest = false

        if settings.confirmExternalRecordingStart {
            settings.awaitingExternalStartConfirmation = true
            settings.pendingStartRecordingRequest = false
            return
        }

        if startManualRecording() {
            settings.pendingStartRecordingRequest = false
        }
    }

    func confirmExternalStartRecording() {
        settings.awaitingExternalStartConfirmation = false
        _ = startManualRecording()
    }

    func cancelExternalStartRecording() {
        settings.awaitingExternalStartConfirmation = false
        settings.pendingStartRecordingRequest = false
    }

    func processExternalStopRequest() {
        DevLog.shared.log(.recording, "processExternalStopRequest (state: \(state))")
        settings.pendingStopRecordingRequest = false
        if state.isActiveSession {
            stopRecording(saveTrip: true)
            return
        }
        finalizeOrphanFromExternalStopIfNeeded()
    }

    /// Widget/intent stop after process death: in-memory session is gone but SwiftData orphan remains.
    @discardableResult
    func finalizeOrphanFromExternalStopIfNeeded() -> Bool {
        guard state == .idle, let modelContext else { return false }
        guard let orphan = TripStore.orphanMatchingRecordingSession(
            tripID: settings.persistedActiveTripID,
            startedAt: settings.persistedRecordingStartedAt,
            from: modelContext
        ) else {
            return false
        }
        DevLog.shared.log(
            .recording,
            "processExternalStopRequest: finalizing orphan trip=\(orphan.id.uuidString.prefix(8))"
        )
        let saved = TripRecoveryService.finalizeOrphan(orphan, in: modelContext, saveTrip: true)
        if saved {
            settings.syncRecordingState(
                isRecording: false,
                isPaused: false,
                elapsed: 0,
                distanceMeters: 0,
                currentSpeedKmh: 0,
                activeTripID: nil
            )
        }
        return saved
    }

    func processExternalPauseRequest() {
        // Flip state before clearing the pending flag. Clearing first let a concurrent
        // sync rewrite App Group `isPaused=false` while we were still `.recording`, so the
        // home-screen widget kept showing Pause after a successful pause tap.
        if state == .recording {
            pauseRecording()
        } else if state == .paused {
            settings.pendingPauseRecordingRequest = false
            syncExternalState(force: true)
        } else {
            settings.pendingPauseRecordingRequest = false
        }
    }

    func processExternalResumeRequest() {
        if state == .paused {
            resumeRecording()
        } else if state == .recording {
            settings.pendingResumeRecordingRequest = false
            syncExternalState(force: true)
        } else {
            settings.pendingResumeRecordingRequest = false
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        updateElapsedTime()
        // Close out an open dwell stop if it already qualifies; otherwise drop it so
        // the user-pause pin does not double with a short standstill.
        finalizeStopIfNeeded()
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        userPauseStartedAt = Date()
        userPauseCoordinate = locationService.lastLocation?.coordinate
            ?? liveBreadcrumbCoordinates.last
        state = .paused
        RecordingDiagnostics.logPaused(tripID: activeTrip?.id)
        stopElapsedTimer()
        settings.pendingPauseRecordingRequest = false
        syncExternalState(force: true)
        TrailhoundHaptics.recordingPaused()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        persistUserPauseStopIfNeeded()
        recordingStartedAt = Date().addingTimeInterval(-elapsedTime)
        state = .recording
        RecordingDiagnostics.logResumed(tripID: activeTrip?.id, orphanResume: false)
        startElapsedTimer()
        settings.pendingResumeRecordingRequest = false
        syncExternalState(force: true)
        TrailhoundHaptics.recordingResumed()
    }

    func resumeRecording(trip: Trip) {
        guard state == .idle, modelContext != nil else { return }

        activeTrip = trip
        state = .recording
        recordingStartedAt = trip.startedAt
        currentDistanceMeters = trip.distanceMeters
        pointSequence = (trip.sortedPoints.last?.sequence ?? -1) + 1
        currentSpeedMps = 0
        elapsedTime = Date().timeIntervalSince(trip.startedAt)
        // A trip saved before speeds were vetted may carry a phantom maximum, so do not let
        // resuming it write that value back.
        maxSpeedMps = trip.maxSpeedMps.flatMap {
            RecordingMovementPolicy.isRecordableSpeed($0) ? $0 : nil
        } ?? 0
        lastTrustedSpeedMps = trip.sortedPoints.last?.speedMps
        lastRecordedLocation = trip.sortedPoints.last?.location
        liveBreadcrumbCoordinates = trip.coordinates
        liveBreadcrumbSegments = Self.breadcrumbSegments(from: trip.sortedPoints)
        liveStopCoordinates = trip.stops.map(\.coordinate)
        refreshDisplaySnapshot(force: true)
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        userPauseStartedAt = nil
        userPauseCoordinate = nil
        pointsSinceLastSave = 0

        locationService.requestPermission()
        locationService.startTracking()
        if !locationService.canRecordInBackground {
            DevLog.shared.warning(
                .recording,
                "resume orphan \(trip.id.uuidString.prefix(8)): background GPS not active"
            )
        }
        RecordingDiagnostics.logResumed(tripID: trip.id, orphanResume: true)
        startElapsedTimer()
        if !UITestSupport.isUnitTesting {
            if let vehicle = activeRecordingVehicleForLiveActivity(),
               let fileName = vehicle.photoFileName {
                _ = VehiclePhotoStore.shared.imageSync(fileName: fileName)
            }
            let mark = liveActivityVehicleMark()
            RecordingLiveActivityService.start(
                startedAt: trip.startedAt,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                vehicleSystemImage: mark.systemImage,
                vehicleSymbolScaleX: mark.symbolScaleX,
                vehiclePhotoRevision: mark.photoRevision
            )
            Task { await warmLiveActivityVehiclePhoto() }
        }
        syncExternalState(force: true)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard state == .recording else {
            if state == .paused {
                RecordingDiagnostics.logIncomingFix(
                    tripID: activeTrip?.id,
                    location: location,
                    state: state
                )
            }
            return
        }
        processRecordingLocationUpdate(location)
    }

    private func processRecordingLocationUpdate(_ location: CLLocation) {
        RecordingDiagnostics.logIncomingFix(tripID: activeTrip?.id, location: location, state: state)
        updateElapsedTime()

        let speed = location.speed >= 0 ? location.speed : 0
        currentSpeedMps = speed

        if speed < stopSpeedMps {
            if currentStopStartedAt == nil {
                currentStopStartedAt = Date()
                currentStopCoordinate = location.coordinate
            }
        } else {
            finalizeStopIfNeeded()
        }

        applyDistanceSample(from: location, speed: speed)
        plannedRoute.noteVehicle(location.coordinate)
        refreshTripStartedPlaceBodyIfNeeded(coordinate: location.coordinate)
        refreshDisplaySnapshot()
        syncExternalState()
    }

    private func refreshTripStartedPlaceBodyIfNeeded(coordinate: CLLocationCoordinate2D) {
        guard !didRefreshTripStartedPlaceBody,
              !UITestSupport.isUnitTesting,
              let tripID = activeTripID,
              let modelContext else { return }
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let startSummary = TripListViewModel.startSummary(
            coordinate: coordinate,
            places: places,
            privacyRadius: settings.privacyRadiusMeters
        )
        guard startSummary != "—", !startSummary.isEmpty else { return }
        didRefreshTripStartedPlaceBody = true
        TripNotificationService.refreshTripStartedBody(tripID: tripID, startSummary: startSummary)
    }

    /// Core Location's speed for this fix, or nil when the fix is too uncertain, too old or too
    /// fast to be believed. The position is kept either way — dropping points is what makes routes
    /// look broken, and only the speedometer is at stake here.
    private func trustedGPSSpeed(for location: CLLocation) -> Double? {
        let age = Date().timeIntervalSince(location.timestamp)
        let trusted = RecordingMovementPolicy.trustedGPSSpeedMps(
            reportedMps: location.speed,
            speedAccuracyMps: location.speedAccuracy,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            fixAgeSeconds: age
        )

        // A speed of -1 just means Core Location has no reading yet; that is normal and not
        // worth a log line.
        if trusted == nil, location.speed >= 0,
           let reason = RecordingMovementPolicy.speedRejectionReason(
               reportedMps: location.speed,
               speedAccuracyMps: location.speedAccuracy,
               horizontalAccuracyMeters: location.horizontalAccuracy,
               fixAgeSeconds: age
           ) {
            RecordingDiagnostics.logSpeedRejected(
                tripID: activeTrip?.id,
                reason: reason,
                reportedKmh: location.speed * 3.6,
                speedAccuracyMps: location.speedAccuracy,
                accuracyMeters: location.horizontalAccuracy,
                ageSeconds: age
            )
        }
        return trusted
    }

    /// What to write on a point: Core Location's speed when it passed every gate, otherwise the
    /// speed the covered distance implies. Nil when neither survives.
    private func speedToStore(
        for location: CLLocation,
        delta: CLLocationDistance,
        timeDelta: TimeInterval
    ) -> Double? {
        if let trusted = trustedGPSSpeed(for: location),
           RecordingMovementPolicy.isPlausibleAcceleration(
               from: lastTrustedSpeedMps,
               to: trusted,
               timeDelta: timeDelta
           ) {
            return trusted
        }

        let implied = delta / max(0.01, timeDelta)
        guard RecordingMovementPolicy.isRecordableSpeed(implied),
              RecordingMovementPolicy.isPlausibleAcceleration(
                  from: lastTrustedSpeedMps,
                  to: implied,
                  timeDelta: timeDelta
              ) else { return nil }
        return implied
    }

    /// The trip's maximum is now always one of its point speeds, so it can never exceed what the
    /// route itself shows — the 203 km/h phantom came from a value no point ever carried.
    private func noteStoredSpeed(_ speedMps: Double?) {
        guard let speedMps, RecordingMovementPolicy.isRecordableSpeed(speedMps) else { return }
        lastTrustedSpeedMps = speedMps
        maxSpeedMps = max(maxSpeedMps, speedMps)
    }

    private func applyDistanceSample(from location: CLLocation, speed: Double, forcePoint: Bool = false) {
        if let previous = lastRecordedLocation {
            let delta = location.distance(from: previous)
            let timeDelta = max(0.01, location.timestamp.timeIntervalSince(previous.timestamp))
            let decision = RecordingMovementPolicy.decision(
                delta: delta,
                timeDelta: timeDelta,
                speed: speed
            )

            switch decision {
            case .ignore:
                RecordingDiagnostics.logMovement(
                    tripID: activeTrip?.id,
                    decision: .ignore,
                    delta: delta,
                    timeDelta: timeDelta,
                    accuracy: location.horizontalAccuracy,
                    locationSpeedKmh: speed * 3.6,
                    storedSpeedKmh: nil,
                    distanceMeters: currentDistanceMeters,
                    pointSequence: pointSequence,
                    mapNewSegment: false,
                    ignoreReason: RecordingMovementPolicy.ignoreReason(
                        delta: delta,
                        timeDelta: timeDelta,
                        locationSpeedMps: speed
                    )
                )
                return
            case .accumulate:
                currentDistanceMeters += delta
                lastRecordedLocation = location
                activeTrip?.distanceMeters = currentDistanceMeters
                let storedSpeed = speedToStore(for: location, delta: delta, timeDelta: timeDelta)
                noteStoredSpeed(storedSpeed)
                RecordingDiagnostics.logMovement(
                    tripID: activeTrip?.id,
                    decision: .accumulate,
                    delta: delta,
                    timeDelta: timeDelta,
                    accuracy: location.horizontalAccuracy,
                    locationSpeedKmh: speed * 3.6,
                    storedSpeedKmh: storedSpeed.map { $0 * 3.6 },
                    distanceMeters: currentDistanceMeters,
                    pointSequence: pointSequence,
                    mapNewSegment: false
                )
                appendPoint(
                    from: location,
                    speed: storedSpeed,
                    startsNewMapSegment: false
                )
            case .gapResume:
                lastRecordedLocation = location
                activeTrip?.distanceMeters = currentDistanceMeters
                // The jump itself is signal loss, so nothing about it can imply a speed. Only
                // Core Location's own reading, if it passes the gates, applies here.
                let storedSpeed = trustedGPSSpeed(for: location)
                noteStoredSpeed(storedSpeed)
                RecordingDiagnostics.logMovement(
                    tripID: activeTrip?.id,
                    decision: .gapResume,
                    delta: delta,
                    timeDelta: timeDelta,
                    accuracy: location.horizontalAccuracy,
                    locationSpeedKmh: speed * 3.6,
                    storedSpeedKmh: storedSpeed.map { $0 * 3.6 },
                    distanceMeters: currentDistanceMeters,
                    pointSequence: pointSequence,
                    mapNewSegment: true
                )
                appendPoint(
                    from: location,
                    speed: storedSpeed,
                    startsNewMapSegment: true
                )
            }
        } else {
            // No previous fix, so nothing to cross-check against: Core Location's own reading is
            // the only candidate, and on a cold start that is exactly the one that used to hand
            // the trip a 203 km/h record it never reached.
            let storedSpeed = trustedGPSSpeed(for: location)
            noteStoredSpeed(storedSpeed)
            RecordingDiagnostics.logMovement(
                tripID: activeTrip?.id,
                decision: .accumulate,
                delta: 0,
                timeDelta: 0,
                accuracy: location.horizontalAccuracy,
                locationSpeedKmh: speed * 3.6,
                storedSpeedKmh: storedSpeed.map { $0 * 3.6 },
                distanceMeters: currentDistanceMeters,
                pointSequence: pointSequence,
                mapNewSegment: false,
                ignoreReason: "first_fix"
            )
            lastRecordedLocation = location
            appendPoint(from: location, speed: storedSpeed, startsNewMapSegment: false)
        }
    }

    private func finalizeRecordingLocation() {
        guard state == .recording || state == .paused else { return }
        guard let location = locationService.lastLocation else { return }

        let speed = location.speed >= 0 ? location.speed : currentSpeedMps
        applyDistanceSample(from: location, speed: speed, forcePoint: true)
        reconcileTripDistance()
    }

    private func reconcileTripDistance() {
        guard let trip = activeTrip else { return }

        let points = trip.sortedPoints
        var computed: Double = 0
        if points.count > 1 {
            for index in 1..<points.count {
                let previous = points[index - 1].location
                let current = points[index].location
                let delta = current.distance(from: previous)
                let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
                let speed = points[index].speedMps
                    ?? (current.speed >= 0 ? current.speed : 0)
                if RecordingMovementPolicy.decision(delta: delta, timeDelta: timeDelta, speed: speed) == .accumulate {
                    computed += delta
                }
            }
        }

        if let lastPoint = points.last?.location, let lastRecordedLocation {
            let tail = lastRecordedLocation.distance(from: lastPoint)
            let timeDelta = max(
                0.01,
                lastRecordedLocation.timestamp.timeIntervalSince(lastPoint.timestamp)
            )
            let speed = lastRecordedLocation.speed >= 0 ? lastRecordedLocation.speed : 0
            if RecordingMovementPolicy.decision(delta: tail, timeDelta: timeDelta, speed: speed) == .accumulate {
                computed += tail
            }
        }

        currentDistanceMeters = max(currentDistanceMeters, computed)
        trip.distanceMeters = currentDistanceMeters
        RecordingDiagnostics.logReconcile(
            tripID: trip.id,
            liveMeters: currentDistanceMeters,
            fromPointsMeters: computed
        )
    }

    private func finalizeStopIfNeeded() {
        guard let trip = activeTrip,
              let modelContext,
              let startedAt = currentStopStartedAt,
              let coordinate = currentStopCoordinate else { return }

        let duration = Date().timeIntervalSince(startedAt)
        guard duration >= RecordingConfiguration.minimumParkingStopDurationSeconds else {
            currentStopStartedAt = nil
            currentStopCoordinate = nil
            return
        }

        let stop = TripStop(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            startedAt: startedAt,
            durationSeconds: duration,
            trip: trip
        )
        trip.stops.append(stop)
        modelContext.insert(stop)
        liveStopCoordinates.append(coordinate)
        currentStopStartedAt = nil
        currentStopCoordinate = nil
    }

    /// Writes a `TripStop` for a manual pause so trip detail shows the same pin.
    private func persistUserPauseStopIfNeeded() {
        guard let trip = activeTrip,
              let modelContext,
              let startedAt = userPauseStartedAt,
              let coordinate = userPauseCoordinate else {
            userPauseStartedAt = nil
            userPauseCoordinate = nil
            return
        }
        let duration = Date().timeIntervalSince(startedAt)
        userPauseStartedAt = nil
        userPauseCoordinate = nil
        // Skip accidental taps; still keep the live-map session pin from LiveFollowMapView.
        guard duration >= 5 else { return }

        let alreadyMarked = liveStopCoordinates.contains {
            abs($0.latitude - coordinate.latitude) < 0.00005
                && abs($0.longitude - coordinate.longitude) < 0.00005
        }
        guard !alreadyMarked else { return }

        let stop = TripStop(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            startedAt: startedAt,
            durationSeconds: duration,
            trip: trip
        )
        trip.stops.append(stop)
        modelContext.insert(stop)
        liveStopCoordinates.append(coordinate)
    }

    private func beginRecording(trigger: RecordingTrigger) {
        guard state == .idle else { return }
        beginRecordingImmediately()
    }

    /// Cached pre-tracking fixes are often minutes old; only replay when fresh and accurate.
    private func isUsableInitialLocation(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)
        guard age >= 0, age <= RecordingMovementPolicy.maximumSpeedFixAgeSeconds else { return false }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= RecordingMovementPolicy.maximumSpeedFixAccuracyMeters else {
            return false
        }
        return true
    }

    private func beginRecordingImmediately(
        startedAt: Date? = nil,
        announceStart: Bool = true,
        processInitialLocation: Bool = true
    ) {
        guard state == .idle else { return }
        guard let modelContext else { return }
        if !TripStore.orphans(from: modelContext).isEmpty {
            DevLog.shared.log(.recording, "beginRecording blocked: orphan exists")
            return
        }

        let resolvedStartedAt = startedAt ?? Date()
        state = .recording
        // Stale widget stop/pause/resume flags must not block Live Activity sync.
        settings.pendingStopRecordingRequest = false
        settings.pendingPauseRecordingRequest = false
        settings.pendingResumeRecordingRequest = false
        currentDistanceMeters = 0
        currentSpeedMps = 0
        lastRecordedLocation = nil
        pointSequence = 0
        pointsSinceLastSave = 0
        recordingStartedAt = resolvedStartedAt
        elapsedTime = Date().timeIntervalSince(resolvedStartedAt)
        maxSpeedMps = 0
        lastTrustedSpeedMps = nil
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        userPauseStartedAt = nil
        userPauseCoordinate = nil
        liveBreadcrumbCoordinates = []
        liveBreadcrumbSegments = []
        liveStopCoordinates = []
        plannedRoute.clear()
        resetDisplaySnapshot()

        let trip = Trip(startedAt: resolvedStartedAt)
        if let vehicle = VehicleResolver.resolveActiveVehicle(in: modelContext, settings: settings) {
            VehicleResolver.assign(vehicle: vehicle, to: trip)
            settings.recordingVehicleID = vehicle.id
        }
        modelContext.insert(trip)
        do {
            try modelContext.save()
        } catch {
            AppErrorPresenter.shared.present(error.localizedDescription)
            resetActiveSession()
            state = .idle
            return
        }
        activeTrip = trip
        DevLog.shared.log(.recording, "Trip started: id=\(trip.id.uuidString.prefix(8))")

        locationService.requestPermission()
        locationService.startTracking()
        RecordingDiagnostics.beginSession(
            tripID: trip.id,
            authorization: locationService.authorizationState,
            backgroundUpdatesEnabled: locationService.canRecordInBackground
        )
        if !locationService.canRecordInBackground {
            DevLog.shared.warning(
                .recording,
                "session \(trip.id.uuidString.prefix(8)): Always/background GPS not active — fixes may stop when screen locks"
            )
        }
        startElapsedTimer()
        if !UITestSupport.isUnitTesting {
            if let vehicle = activeRecordingVehicleForLiveActivity(),
               let fileName = vehicle.photoFileName {
                _ = VehiclePhotoStore.shared.imageSync(fileName: fileName)
            }
            let mark = liveActivityVehicleMark()
            RecordingLiveActivityService.start(
                startedAt: resolvedStartedAt,
                vehicleSystemImage: mark.systemImage,
                vehicleSymbolScaleX: mark.symbolScaleX,
                vehiclePhotoRevision: mark.photoRevision
            )
            Task { await warmLiveActivityVehiclePhoto() }
            let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
            let startSummary = TripListViewModel.startSummary(
                coordinate: locationService.lastLocation?.coordinate,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )
            if TripNotificationService.notifyTripStarted(tripID: trip.id, startSummary: startSummary) {
                // Rich banner already posted from lastLocation — don't let the
                // initial-fix replay fire a second "Trip started" alert.
                didRefreshTripStartedPlaceBody = true
            }
        }
        syncExternalState(force: true)
        if announceStart, !UITestSupport.isUnitTesting {
            TrailhoundHaptics.recordingStarted()
            TrailhoundSounds.recordingStarted()
        }

        if processInitialLocation, !UITestSupport.isUnitTesting,
           let location = locationService.lastLocation,
           isUsableInitialLocation(location) {
            processRecordingLocationUpdate(location)
        }
    }

    private enum RecordingTrigger {
        case manual
    }

    private func appendPoint(
        from location: CLLocation,
        speed: Double?,
        startsNewMapSegment: Bool = false
    ) {
        guard let trip = activeTrip, let modelContext else { return }

        let recordedSpeed = speed.flatMap {
            RecordingMovementPolicy.isRecordableSpeed($0) ? $0 : nil
        }

        let point = TripPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sequence: pointSequence,
            speedMps: recordedSpeed,
            trip: trip
        )
        pointSequence += 1
        trip.points.append(point)
        appendLiveBreadcrumb(location.coordinate, startsNewMapSegment: startsNewMapSegment)
        modelContext.insert(point)
        pointsSinceLastSave += 1
        let willBatchSave = pointsSinceLastSave >= saveBatchSize
        RecordingDiagnostics.logPointPersisted(
            tripID: trip.id,
            sequence: point.sequence,
            batchSave: willBatchSave
        )
        if willBatchSave {
            trip.distanceMeters = currentDistanceMeters
            trip.invalidatePointCaches()
            flushPointsToStore()
        }
    }

    private func appendLiveBreadcrumb(
        _ coordinate: CLLocationCoordinate2D,
        startsNewMapSegment: Bool
    ) {
        liveBreadcrumbCoordinates.append(coordinate)
        if startsNewMapSegment || liveBreadcrumbSegments.isEmpty {
            liveBreadcrumbSegments.append([coordinate])
        } else {
            liveBreadcrumbSegments[liveBreadcrumbSegments.count - 1].append(coordinate)
        }
    }

    private static func breadcrumbSegments(from points: [TripPoint]) -> [[CLLocationCoordinate2D]] {
        guard let first = points.first else { return [] }
        var segments: [[CLLocationCoordinate2D]] = [[first.coordinate]]
        guard points.count > 1 else { return segments }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let delta = current.location.distance(from: previous.location)
            let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
            let speed = current.speedMps ?? (current.location.speed >= 0 ? current.location.speed : 0)
            if RecordingMovementPolicy.shouldDrawMapSegment(delta: delta, timeDelta: timeDelta, speed: speed) {
                segments[segments.count - 1].append(current.coordinate)
            } else {
                segments.append([current.coordinate])
            }
        }
        return segments
    }

    private func flushPointsToStore() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
            pointsSinceLastSave = 0
        } catch {
            RecordingDiagnostics.logPersistFailure(tripID: activeTrip?.id, error: error.localizedDescription)
            AppErrorPresenter.shared.present(error.localizedDescription)
        }
    }

    private func stopRecording(saveTrip: Bool) {
        guard state.isActiveSession else { return }
        let tripID = activeTrip?.id
        let pointCountBeforeStop = activeTrip?.points.count ?? 0

        finalizeRecordingLocation()
        finalizeStopIfNeeded()

        let distanceBeforeIdle = currentDistanceMeters
        let elapsed = elapsedTime
        let maxKmh = maxSpeedMps * 3.6
        let reconciled = activeTrip.map { trip in
            var computed: Double = 0
            let points = trip.sortedPoints
            if points.count > 1 {
                for index in 1..<points.count {
                    let previous = points[index - 1].location
                    let current = points[index].location
                    let delta = current.distance(from: previous)
                    let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
                    let speed = points[index].speedMps ?? 0
                    if RecordingMovementPolicy.decision(delta: delta, timeDelta: timeDelta, speed: speed) == .accumulate {
                        computed += delta
                    }
                }
            }
            return computed
        }

        DevLog.shared.log(
            .recording,
            "stopRecording: saveTrip=\(saveTrip), distance=\(Int(distanceBeforeIdle))m, elapsed=\(Int(elapsed))s points=\(pointCountBeforeStop)"
        )
        state = .idle
        settings.syncRecordingState(
            isRecording: false,
            isPaused: false,
            elapsed: 0,
            distanceMeters: 0,
            currentSpeedKmh: 0,
            activeTripID: nil
        )
        if !UITestSupport.isUnitTesting {
            TrailhoundHaptics.recordingStopped()
            TrailhoundSounds.recordingStopped()
        }
        locationService.stopTracking()
        stopElapsedTimer()
        ensureTripHasAnchorPointIfNeeded()
        flushPointsToStore()
        if !UITestSupport.isUnitTesting {
            RecordingLiveActivityService.stop()
        }
        RecordingSyncCoordinator.reset()

        guard let trip = activeTrip, let modelContext else {
            if let tripID {
                RecordingDiagnostics.endSession(
                    tripID: tripID,
                    saved: false,
                    distanceMeters: distanceBeforeIdle,
                    durationSeconds: elapsed,
                    maxSpeedKmh: maxKmh,
                    pointCount: pointCountBeforeStop,
                    reconciledDistanceMeters: reconciled
                )
            }
            resetActiveSession()
            return
        }

        if !UITestSupport.isUnitTesting {
            TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)
            TripNotificationService.cancelDeferredStartedPush(tripID: trip.id)
        }

        let endedAt = Date()
        let duration = endedAt.timeIntervalSince(trip.startedAt)
        let shouldSave = saveTrip

        if shouldSave {
            trip.endedAt = endedAt
            trip.distanceMeters = currentDistanceMeters
            trip.maxSpeedMps = maxSpeedMps > 0 ? maxSpeedMps : nil
            let vehicle = trip.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: modelContext) }
            trip.vehicle = nil
            FuelCostCalculator.applyEstimate(
                to: trip,
                distanceMeters: currentDistanceMeters,
                vehicle: vehicle
            )
            trip.geocodeStatus = .pending

            TripDerivedMetrics.recomputeEndpoints(for: trip)
            let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
            PlaceMatchingService.matchPlaces(
                for: trip,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )
            let allTrips = (try? modelContext.fetch(FetchDescriptor<Trip>())) ?? []
            TripCategorySuggestionService.refreshPending(
                on: trip,
                among: allTrips,
                places: places,
                enabled: settings.smartCategorySuggestionsEnabled,
                workHours: settings.workHours
            )
            let privacyRadius = settings.privacyRadiusMeters
            let routeSummary = TripListViewModel.routeSummary(
                for: trip,
                places: places,
                privacyRadius: privacyRadius
            )
            let startSummary = TripListViewModel.displayName(
                placeName: trip.startPlaceName,
                address: trip.startAddress,
                coordinate: trip.startCoordinate,
                places: places,
                privacyRadius: privacyRadius
            )
            TripDerivedMetrics.recomputeNightDistance(for: trip)
            TripDerivedMetrics.recomputeSpeedProfile(for: trip)
            TripDerivedMetrics.recomputeFuel(
                for: trip,
                fuelType: vehicle?.fuelType ?? .petrol,
                vehicle: vehicle
            )
            TripDerivedMetrics.refreshSearchIndex(
                for: trip,
                places: places,
                privacyRadius: privacyRadius
            )
            TripRollupService.add(trip, in: modelContext)
            VehicleOdometerService.tripAdded(trip, in: modelContext)

            do {
                try modelContext.save()
            } catch {
                AppErrorPresenter.shared.present(error.localizedDescription)
                resetActiveSession()
                syncExternalState()
                return
            }
            PersonalRecordToast.presentIfNeeded(
                for: trip,
                in: modelContext,
                timing: .afterRecordingCredits
            )
            if !UITestSupport.isUnitTesting {
                TripNotificationService.refreshTripStartedBody(
                    tripID: trip.id,
                    startSummary: startSummary,
                    postBanner: false
                )
                TripNotificationService.notifyTripEnded(
                    tripID: trip.id,
                    distanceMeters: currentDistanceMeters,
                    duration: duration,
                    routeSummary: routeSummary
                )
            }

            let tripUUID = trip.id
            let container = modelContainer
            if !UITestSupport.isUnitTesting {
                Task { @MainActor in
                    guard let container else { return }
                    await TripPostProcessor.process(
                        tripUUID: tripUUID,
                        container: container
                    )
                }
            }
        } else {
            if saveTrip, !UITestSupport.isUnitTesting {
                TripNotificationService.notifyTripDiscarded(tripID: trip.id)
            }
            modelContext.delete(trip)
            try? modelContext.save()
        }

        RecordingDiagnostics.endSession(
            tripID: trip.id,
            saved: shouldSave,
            distanceMeters: currentDistanceMeters,
            durationSeconds: duration,
            maxSpeedKmh: maxKmh,
            pointCount: trip.sortedPoints.count,
            reconciledDistanceMeters: reconciled
        )

        let savedVehicleID = shouldSave ? trip.vehicleID : nil
        resetActiveSession()
        if let savedVehicleID {
            VehicleCareNotificationScheduler.evaluateKmReminders(for: savedVehicleID, in: modelContext)
        }
        TripStore.syncWidgetWeekDistance(in: modelContext)
        syncExternalState(force: true)
        if !UITestSupport.shouldSkipExternalEffects {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func ensureTripHasAnchorPointIfNeeded() {
        guard let trip = activeTrip, let modelContext else { return }
        guard trip.points.isEmpty else { return }
        guard let location = locationService.lastLocation else {
            DevLog.shared.warning(.recording, "anchor point skipped \(trip.id.uuidString.prefix(8)): no lastLocation")
            return
        }

        DevLog.shared.log(.recording, "anchor point added \(trip.id.uuidString.prefix(8)) (trip had 0 points)")

        let point = TripPoint(
            timestamp: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sequence: pointSequence,
            speedMps: nil,
            trip: trip
        )
        pointSequence += 1
        trip.points.append(point)
        trip.invalidatePointCaches()
        appendLiveBreadcrumb(location.coordinate, startsNewMapSegment: liveBreadcrumbSegments.isEmpty)
        modelContext.insert(point)
        pointsSinceLastSave += 1
    }

    private func resetActiveSession() {
        activeTrip = nil
        lastRecordedLocation = nil
        pointSequence = 0
        pointsSinceLastSave = 0
        currentDistanceMeters = 0
        currentSpeedMps = 0
        recordingStartedAt = nil
        elapsedTime = 0
        maxSpeedMps = 0
        lastTrustedSpeedMps = nil
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        userPauseStartedAt = nil
        userPauseCoordinate = nil
        liveBreadcrumbCoordinates = []
        liveBreadcrumbSegments = []
        liveStopCoordinates = []
        plannedRoute.clear()
        didRefreshTripStartedPlaceBody = false
        resetDisplaySnapshot()
    }

    private func resetDisplaySnapshot() {
        displaySampler.reset()
        displayElapsedTime = 0
        displayDistanceMeters = 0
        displaySpeedMps = 0
    }

    private func refreshDisplaySnapshot(force: Bool = false) {
        let now = Date()
        if !force && !displaySampler.shouldPublish(now: now) { return }
        displayElapsedTime = elapsedTime
        displayDistanceMeters = currentDistanceMeters
        displaySpeedMps = currentSpeedMps
    }

    func syncExternalState(force: Bool = false) {
        let shouldWriteDefaults = force || RecordingSyncCoordinator.shouldSync()

        // Live Activity / widget controls already wrote optimistic App Group
        // state (and may have ended the activity). Don't clobber that while the
        // matching request is still waiting to be applied in-process.
        // Use in-process settings flags — CFPreferences refresh here previously
        // re-introduced stale widget stop/pause bits and blocked LA updates.
        if settings.pendingStopRecordingRequest {
            if shouldWriteDefaults {
                settings.syncRecordingState(
                    isRecording: false,
                    isPaused: false,
                    elapsed: elapsedTime,
                    distanceMeters: currentDistanceMeters,
                    currentSpeedKmh: 0,
                    activeTripID: activeTripID
                )
            }
            return
        }
        if settings.pendingPauseRecordingRequest {
            if shouldWriteDefaults {
                settings.syncRecordingState(
                    isRecording: true,
                    isPaused: true,
                    elapsed: elapsedTime,
                    distanceMeters: currentDistanceMeters,
                    currentSpeedKmh: 0,
                    activeTripID: activeTripID
                )
            }
            if force {
                RecordingControlBridge.reloadHomeScreenWidgetTimelinesImmediately()
            }
            return
        }
        if settings.pendingResumeRecordingRequest {
            if shouldWriteDefaults {
                let speedKmh = Int(max(0, currentSpeedMps) * 3.6)
                settings.syncRecordingState(
                    isRecording: true,
                    isPaused: false,
                    elapsed: elapsedTime,
                    distanceMeters: currentDistanceMeters,
                    currentSpeedKmh: speedKmh,
                    recordingStartedAt: state == .recording ? recordingStartedAt : nil,
                    activeTripID: activeTripID
                )
            }
            if force {
                RecordingControlBridge.reloadHomeScreenWidgetTimelinesImmediately()
            }
            return
        }

        let speedKmh = Int(max(0, currentSpeedMps) * 3.6)
        let isPaused = state == .paused
        let isRecording = state == .recording
        if shouldWriteDefaults {
            settings.syncRecordingState(
                isRecording: isRecording || isPaused,
                isPaused: isPaused,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: speedKmh,
                recordingStartedAt: isRecording ? recordingStartedAt : nil,
                activeTripID: (isRecording || isPaused) ? activeTripID : nil
            )
        }
        guard !UITestSupport.isUnitTesting else { return }

        // App Group stays on the 2s coordinator. Live Activity has its own 3s
        // throttle — do not gate it behind shouldSync or updates land at 4s (2+3).
        let vehicleMark = liveActivityVehicleMark()
        if state.isActiveSession, let recordingStartedAt {
            RecordingLiveActivityService.ensureActiveIfNeeded(
                startedAt: recordingStartedAt,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: speedKmh,
                isPaused: isPaused,
                vehicleSystemImage: vehicleMark.systemImage,
                vehicleSymbolScaleX: vehicleMark.symbolScaleX,
                vehiclePhotoRevision: vehicleMark.photoRevision
            )
        }
        RecordingLiveActivityService.update(
            elapsed: elapsedTime,
            distanceMeters: currentDistanceMeters,
            currentSpeedKmh: speedKmh,
            isPaused: isPaused,
            force: force,
            vehicleSystemImage: vehicleMark.systemImage,
            vehicleSymbolScaleX: vehicleMark.symbolScaleX,
            vehiclePhotoRevision: vehicleMark.photoRevision
        )

        // Never reload home-screen timelines on the recording tick — the widget
        // extension also hosts Live Activity / Dynamic Island; thrashing timelines
        // kills Island presentation. Timer ticks via pre-scheduled entries; distance
        // refreshes when force == true (pause/resume/stop/start/vehicle change).
        if force {
            RecordingControlBridge.reloadHomeScreenWidgetTimelinesImmediately()
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        Self.elapsedTimerService = self
        let target = ElapsedTimerTarget()
        elapsedTimerTarget = target
        let timer = Timer(timeInterval: 1, target: target, selector: #selector(ElapsedTimerTarget.tick(_:)), userInfo: nil, repeats: true)
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateElapsedTime() {
        guard let startedAt = recordingStartedAt else { return }
        elapsedTime = Date().timeIntervalSince(startedAt)
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedTimerTarget = nil
        if Self.elapsedTimerService === self {
            Self.elapsedTimerService = nil
        }
    }

    fileprivate func handleElapsedTimerTick() {
        updateElapsedTime()
        refreshDisplaySnapshot()
        syncExternalState()
    }

    static func handleElapsedTimerTickFromBackground() {
        elapsedTimerService?.handleElapsedTimerTick()
    }
}

private nonisolated func dispatchElapsedTimerTickToMainActor() {
    Task { @MainActor in
        TripRecordingService.handleElapsedTimerTickFromBackground()
    }
}

private final class ElapsedTimerTarget: NSObject {
    @objc nonisolated func tick(_ timer: Timer) {
        dispatchElapsedTimerTickToMainActor()
    }
}

@MainActor
enum TripPostProcessor {
    static func process(
        tripUUID: UUID,
        container: ModelContainer
    ) async {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.id == tripUUID }
        )
        descriptor.fetchLimit = 1
        guard let trip = (try? context.fetch(descriptor))?.first else { return }

        // Recorded points are never reduced on disk — display decimation happens in
        // `RouteDisplayPath`. Deleting them here previously destroyed long trips.
        if !UITestSupport.isUnitTesting {
            await enrichTripWithAddresses(
                trip,
                context: context,
                geocodingService: GeocodingService()
            )
        }

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        PlaceMatchingService.matchPlaces(
            for: trip,
            places: places,
            privacyRadius: AppSettings.shared.privacyRadiusMeters
        )
        let vehicle = trip.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: context) }
        TripDerivedMetrics.recompute(
            for: trip,
            places: places,
            privacyRadius: AppSettings.shared.privacyRadiusMeters,
            fuelType: vehicle?.fuelType ?? .petrol,
            vehicle: vehicle
        )
        let allTrips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        TripCategorySuggestionService.refreshPending(
            on: trip,
            among: allTrips,
            places: places,
            enabled: AppSettings.shared.smartCategorySuggestionsEnabled,
            workHours: AppSettings.shared.workHours
        )
        try? context.save()
        TripRoutePathCache.shared.prewarm(tripID: tripUUID, container: container)
    }

    private static func enrichTripWithAddresses(
        _ trip: Trip,
        context: ModelContext,
        geocodingService: GeocodingService
    ) async {
        var success = true
        var startPlace = GeocodedPlace(suggestedName: nil, address: nil, locality: nil, countryCode: nil)
        var endPlace = GeocodedPlace(suggestedName: nil, address: nil, locality: nil, countryCode: nil)

        if let startCoordinate = trip.startCoordinate {
            let startLocation = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
            startPlace = await geocodingService.lookupPlace(at: startLocation)
            trip.startAddress = startPlace.address ?? startPlace.suggestedName
            if trip.startAddress == nil { success = false }
        }

        if let endCoordinate = trip.endCoordinate {
            let endLocation = CLLocation(latitude: endCoordinate.latitude, longitude: endCoordinate.longitude)
            endPlace = await geocodingService.lookupPlace(at: endLocation)
            trip.endAddress = endPlace.address ?? endPlace.suggestedName
            if trip.endAddress == nil { success = false }
        }

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        TripLocalityResolver.apply(
            to: trip,
            startLocality: startPlace.locality,
            startCountryCode: startPlace.countryCode,
            endLocality: endPlace.locality,
            endCountryCode: endPlace.countryCode,
            places: places,
            privacyRadius: AppSettings.shared.privacyRadiusMeters
        )

        trip.geocodeStatus = success ? .complete : .failed
        try? context.save()
    }
}
