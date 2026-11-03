import MapKit
import SwiftData
import SwiftUI
import UIKit

/// Light vs dark MapKit snapshot. Disk and memory keep both; share cards use the same appearance.
enum MapSnapshotAppearance: String, Hashable, CaseIterable, Sendable {
    case light
    case dark

    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    func fileName(for tripID: UUID) -> String {
        "\(tripID.uuidString)-\(rawValue).jpg"
    }

    static func fileNames(for tripID: UUID) -> [String] {
        allCases.map { $0.fileName(for: tripID) }
    }

    /// Pre-theme files were `{uuid}.jpg` with whatever style happened to render first.
    static func isLegacyUnstyledFileName(_ name: String) -> Bool {
        guard name.lowercased().hasSuffix(".jpg") else { return false }
        let stem = String(name.dropLast(4))
        return UUID(uuidString: stem) != nil
    }
}

@MainActor
final class TripMapSnapshotCache {
    static let shared = TripMapSnapshotCache()

    private struct SnapshotKey: Hashable {
        let tripID: UUID
        let appearance: MapSnapshotAppearance
    }

    private var memoryCache: [SnapshotKey: UIImage] = [:]
    private var inFlight: [SnapshotKey: Task<UIImage?, Never>] = [:]
    private var startedRenders: Set<SnapshotKey> = []
    private let renderGate = SnapshotRenderGate()

    /// Test seam: increments only when the MapKit (or injected) renderer actually runs.
    private(set) var renderInvocationCount = 0

    /// Test seam: replaces MapKit so unit tests never call `MKMapSnapshotter`.
    var testRenderer: (() async -> UIImage?)?

    /// Resolved once. As a computed property this issued a `fileExists` syscall for every row
    /// that scrolled into view.
    private let cacheDirectory: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("TripMapSnapshots", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        let directory = cacheDirectory
        Self.diskQueue.async {
            Self.purgeLegacyUnstyledSnapshots(in: directory)
        }
    }

    /// Memory hit only — never touches disk, so it is safe to call while scrolling.
    func cachedImage(for tripID: UUID, appearance: MapSnapshotAppearance) -> UIImage? {
        memoryCache[SnapshotKey(tripID: tripID, appearance: appearance)]
    }

    func snapshot(
        for trip: Trip,
        appearance: MapSnapshotAppearance,
        container: ModelContainer,
        size: CGSize = CGSize(width: 88, height: 88)
    ) async -> UIImage? {
        let key = SnapshotKey(tripID: trip.id, appearance: appearance)
        if let cached = memoryCache[key] {
            return cached
        }

        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        // Reading and decoding the JPEG on the main actor stalled scrolling once the list had
        // more than a handful of trips.
        if let stored = await Self.readImage(at: fileURL(for: trip.id, appearance: appearance)) {
            memoryCache[key] = stored
            return stored
        }

        let task = Task<UIImage?, Never> { @MainActor in
            defer { inFlight[key] = nil }
            if Task.isCancelled { return nil }

            let samples = await TripRoutePathCache.shared.path(for: trip, container: container)
            if Task.isCancelled { return nil }
            let pieces = samples.map { $0.map(\.coordinate) }
            guard pieces.contains(where: { $0.count >= 2 }) else { return nil }

            let acquired = await renderGate.acquire()
            guard acquired else { return nil }
            defer { renderGate.release() }
            if Task.isCancelled { return nil }

            startedRenders.insert(key)
            defer { startedRenders.remove(key) }

            renderInvocationCount += 1
            let image: UIImage?
            if let testRenderer {
                image = await testRenderer()
            } else if UITestSupport.shouldSkipExternalEffects {
                image = nil
            } else {
                image = await renderSnapshot(
                    pieces: pieces,
                    size: size,
                    appearance: appearance
                )
            }
            if let image {
                store(image, for: key)
            }
            return image
        }

        inFlight[key] = task
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in
                self.cancelRenderIfNotStarted(key: key, task: task)
            }
        }
    }

    func remove(for tripID: UUID) {
        for appearance in MapSnapshotAppearance.allCases {
            let key = SnapshotKey(tripID: tripID, appearance: appearance)
            memoryCache.removeValue(forKey: key)
            inFlight[key]?.cancel()
            inFlight.removeValue(forKey: key)
            startedRenders.remove(key)
        }
        let urls = MapSnapshotAppearance.allCases.map { fileURL(for: tripID, appearance: $0) }
            + [legacyFileURL(for: tripID)]
        Self.diskQueue.async {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Test helper — drops only the in-memory layer so the next read exercises disk.
    func clearMemory() {
        memoryCache.removeAll(keepingCapacity: true)
    }

    func resetRenderInvocationCount() {
        renderInvocationCount = 0
    }

    func resetTestRenderer() {
        testRenderer = nil
    }

    func storeForTesting(_ image: UIImage, tripID: UUID, appearance: MapSnapshotAppearance) {
        store(image, for: SnapshotKey(tripID: tripID, appearance: appearance))
    }

    private func cancelRenderIfNotStarted(key: SnapshotKey, task: Task<UIImage?, Never>) {
        guard !startedRenders.contains(key) else { return }
        task.cancel()
    }

    private func fileURL(for tripID: UUID, appearance: MapSnapshotAppearance) -> URL {
        cacheDirectory.appendingPathComponent(appearance.fileName(for: tripID))
    }

    private func legacyFileURL(for tripID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(tripID.uuidString).jpg")
    }

    private func store(_ image: UIImage, for key: SnapshotKey) {
        memoryCache[key] = image
        let url = fileURL(for: key.tripID, appearance: key.appearance)
        Self.diskQueue.async {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// One serial queue for every file operation. Besides keeping encode/decode off the main
    /// actor, FIFO ordering means a delete can never be overtaken by an in-flight write and
    /// leave a snapshot behind for a trip the user removed.
    private static let diskQueue = DispatchQueue(
        label: "com.milehound.TripMapSnapshotCache.disk",
        qos: .utility
    )

    private static func readImage(at url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(data: data))
            }
        }
    }

    nonisolated private static func purgeLegacyUnstyledSnapshots(in directory: URL) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where MapSnapshotAppearance.isLegacyUnstyledFileName(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func renderSnapshot(
        pieces: [[CLLocationCoordinate2D]],
        size: CGSize,
        appearance: MapSnapshotAppearance
    ) async -> UIImage? {
        guard let region = mapRegion(for: pieces.flatMap { $0 }) else { return nil }

        let scale = UIScreen.main.scale
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = scale
        options.mapType = .standard
        options.traitCollection = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = appearance.userInterfaceStyle
            mutableTraits.displayScale = scale
        }

        let snapshotter = MKMapSnapshotter(options: options)

        return await withCheckedContinuation { continuation in
            let resume = OnceResume()
            snapshotter.start { snapshot, _ in
                guard let snapshot else {
                    resume.finish(continuation, SendableSnapshot(image: nil))
                    return
                }

                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    snapshot.image.draw(at: .zero)

                    // One sub-path per piece: real gaps must not be bridged by a straight line.
                    let path = UIBezierPath()
                    for piece in pieces where piece.count >= 2 {
                        for (index, coordinate) in piece.enumerated() {
                            let point = snapshot.point(for: coordinate)
                            if index == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                    }
                    UIColor.systemBlue.setStroke()
                    path.lineWidth = 2.5
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }

                resume.finish(continuation, SendableSnapshot(image: image))
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                snapshotter.cancel()
                resume.finish(continuation, SendableSnapshot(image: nil))
            }
        }.image
    }

    private func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.008, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.008, (maxLon - minLon) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// Serialises MapKit snapshot work. Cancelled waiters leave the line without holding the slot.
private final class SnapshotRenderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var order: [UUID] = []
    private var cancelledIDs: Set<UUID> = []

    func acquire() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if cancelledIDs.remove(id) != nil || Task.isCancelled {
                    lock.unlock()
                    continuation.resume(returning: false)
                    return
                }
                if !busy {
                    busy = true
                    lock.unlock()
                    continuation.resume(returning: true)
                    return
                }
                waiters[id] = continuation
                order.append(id)
                lock.unlock()
            }
        } onCancel: {
            cancelWaiter(id)
        }
    }

    func release() {
        lock.lock()
        let next: CheckedContinuation<Bool, Never>?
        if let nextID = order.first {
            order.removeFirst()
            next = waiters.removeValue(forKey: nextID)
        } else {
            busy = false
            next = nil
        }
        lock.unlock()
        next?.resume(returning: true)
    }

    private func cancelWaiter(_ id: UUID) {
        lock.lock()
        order.removeAll { $0 == id }
        if let continuation = waiters.removeValue(forKey: id) {
            lock.unlock()
            continuation.resume(returning: false)
            return
        }
        cancelledIDs.insert(id)
        lock.unlock()
    }
}

/// MapKit's snapshot callback can stall; resume the continuation at most once.
private struct SendableSnapshot: @unchecked Sendable {
    let image: UIImage?
}

private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false

    func finish(
        _ continuation: CheckedContinuation<SendableSnapshot, Never>,
        _ value: SendableSnapshot
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        didFinish = true
        continuation.resume(returning: value)
    }
}
