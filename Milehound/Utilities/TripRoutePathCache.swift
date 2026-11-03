import CoreLocation
import Foundation
import SwiftData

/// Fingerprint of the trip fields that decide whether a cached display path is still valid.
/// Uses only stored properties so validation never faults the `points` relationship.
struct TripRoutePathFingerprint: Equatable, Sendable {
    let distanceMeters: Double
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let startLatitude: Double
    let startLongitude: Double
    let endLatitude: Double
    let endLongitude: Double

    /// Sentinel for missing optionals — must not be NaN because NaN != NaN breaks Equatable.
    static let missingCoordinate = -1_000_000.0
    static let missingEndedAt = -1.0

    static func make(from trip: Trip) -> TripRoutePathFingerprint {
        TripRoutePathFingerprint(
            distanceMeters: trip.distanceMeters,
            startedAt: trip.startedAt.timeIntervalSince1970,
            endedAt: trip.endedAt?.timeIntervalSince1970 ?? missingEndedAt,
            startLatitude: trip.startLatitude ?? missingCoordinate,
            startLongitude: trip.startLongitude ?? missingCoordinate,
            endLatitude: trip.endLatitude ?? missingCoordinate,
            endLongitude: trip.endLongitude ?? missingCoordinate
        )
    }
}

/// Plain transfer values for a single display point — free of CoreLocation / SwiftData so they
/// can cross actor boundaries and round-trip through the binary cache.
struct CachedRoutePoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: TimeInterval
    let speedMps: Double?

    var asRouteSample: RouteSample {
        RouteSample(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            timestamp: Date(timeIntervalSince1970: timestamp),
            speedMps: speedMps
        )
    }

    init(latitude: Double, longitude: Double, timestamp: TimeInterval, speedMps: Double?) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.speedMps = speedMps
    }

    init(_ sample: RouteSample) {
        latitude = sample.coordinate.latitude
        longitude = sample.coordinate.longitude
        timestamp = sample.timestamp.timeIntervalSince1970
        speedMps = sample.speedMps
    }
}

struct TripRoutePathPayload: Equatable, Sendable {
    let fingerprint: TripRoutePathFingerprint
    let pieces: [[CachedRoutePoint]]

    var routeSamples: [[RouteSample]] {
        pieces.map { $0.map(\.asRouteSample) }
    }

    static func from(samples pieces: [[RouteSample]], fingerprint: TripRoutePathFingerprint) -> TripRoutePathPayload {
        TripRoutePathPayload(
            fingerprint: fingerprint,
            pieces: pieces.map { $0.map(CachedRoutePoint.init) }
        )
    }
}

/// Memory + disk cache of decimated display paths. Original `TripPoint` rows are never written here.
@MainActor
final class TripRoutePathCache {
    static let shared = TripRoutePathCache()

    /// Test seam: how many times the worker was asked to build a path.
    private(set) var workerInvocationCount = 0

    private var memoryCache: [UUID: TripRoutePathPayload] = [:]
    private var inFlight: [UUID: Task<TripRoutePathPayload?, Never>] = [:]
    private let cacheDirectory: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("TripRoutePaths", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    /// Memory hit only — never touches disk.
    func cachedPath(for tripID: UUID, fingerprint: TripRoutePathFingerprint) -> [[RouteSample]]? {
        guard let payload = memoryCache[tripID], payload.fingerprint == fingerprint else { return nil }
        return payload.routeSamples
    }

    func path(for trip: Trip, container: ModelContainer) async -> [[RouteSample]] {
        await path(
            tripID: trip.id,
            fingerprint: TripRoutePathFingerprint.make(from: trip),
            container: container
        )
    }

    func path(
        tripID: UUID,
        fingerprint: TripRoutePathFingerprint,
        container: ModelContainer
    ) async -> [[RouteSample]] {
        if let cached = cachedPath(for: tripID, fingerprint: fingerprint) {
            return cached
        }

        if let existingTask = inFlight[tripID] {
            if let payload = await existingTask.value, payload.fingerprint == fingerprint {
                return payload.routeSamples
            }
        }

        if let stored = await Self.readPayload(at: fileURL(for: tripID)) {
            if stored.fingerprint == fingerprint {
                memoryCache[tripID] = stored
                return stored.routeSamples
            }
            remove(for: tripID)
        }

        let payload = await buildAndStore(tripID: tripID, container: container)
        return payload?.routeSamples ?? []
    }

    /// Builds and stores the display path in the background so the first detail open is warm.
    /// Skips work when memory, an in-flight build, or a disk payload already covers `tripID`.
    /// Fingerprint validation stays on `path(...)` at detail open — stale disk is rejected there.
    func prewarm(tripID: UUID, container: ModelContainer) {
        if memoryCache[tripID] != nil { return }
        if inFlight[tripID] != nil { return }

        Task { @MainActor in
            if memoryCache[tripID] != nil { return }
            if inFlight[tripID] != nil { return }

            if let stored = await Self.readPayload(at: fileURL(for: tripID)) {
                memoryCache[tripID] = stored
                return
            }

            _ = await buildAndStore(tripID: tripID, container: container)
        }
    }

    func remove(for tripID: UUID) {
        memoryCache.removeValue(forKey: tripID)
        inFlight[tripID]?.cancel()
        inFlight.removeValue(forKey: tripID)
        let url = fileURL(for: tripID)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Test helper — drops only the in-memory layer so the next read exercises disk.
    func clearMemory() {
        memoryCache.removeAll(keepingCapacity: true)
    }

    /// Test helper — resets worker invocation counter.
    func resetWorkerInvocationCount() {
        workerInvocationCount = 0
    }

    /// Test helper — writes a payload without going through the worker.
    func storeForTesting(_ payload: TripRoutePathPayload, for tripID: UUID) {
        store(payload, for: tripID)
    }

    /// Test helper — reads whatever is on disk for `tripID`, ignoring fingerprint.
    func readDiskForTesting(tripID: UUID) async -> TripRoutePathPayload? {
        await Self.readPayload(at: fileURL(for: tripID))
    }

    private func buildAndStore(tripID: UUID, container: ModelContainer) async -> TripRoutePathPayload? {
        if let existingTask = inFlight[tripID] {
            return await existingTask.value
        }

        let task = Task<TripRoutePathPayload?, Never> { @MainActor in
            defer { inFlight[tripID] = nil }
            workerInvocationCount += 1
            let worker = TripRoutePathWorker(modelContainer: container)
            guard let payload = await worker.build(tripID: tripID) else { return nil }
            store(payload, for: tripID)
            return payload
        }
        inFlight[tripID] = task
        return await task.value
    }

    private func store(_ payload: TripRoutePathPayload, for tripID: UUID) {
        memoryCache[tripID] = payload
        let url = fileURL(for: tripID)
        Task.detached(priority: .utility) {
            TripRoutePathCodec.write(payload, to: url)
        }
    }

    private func fileURL(for tripID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(tripID.uuidString).bin")
    }

    private static func readPayload(at url: URL) async -> TripRoutePathPayload? {
        await Task.detached(priority: .utility) {
            TripRoutePathCodec.read(from: url)
        }.value
    }
}
