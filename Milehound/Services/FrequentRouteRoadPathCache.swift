import CoreLocation
import Foundation
import MapKit

/// Driving polylines for frequent-route overlays. Cached so Stats never walks GPS `points`.
@MainActor
final class FrequentRouteRoadPathCache {
    static let shared = FrequentRouteRoadPathCache()

    static let maxPoints = 96

    private var memory: [String: [CLLocationCoordinate2D]] = [:]
    private var inFlight: [String: Task<[CLLocationCoordinate2D], Never>] = [:]
    private let cacheDirectory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = support.appendingPathComponent("FrequentRouteRoadPaths", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func path(
        pairKey: String,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        let key = Self.cacheKey(pairKey: pairKey, start: start, end: end)
        if let cached = memory[key], cached.count >= 2 { return cached }
        if let existing = inFlight[key] { return await existing.value }
        if let disk = readDisk(key), disk.count >= 2 {
            memory[key] = disk
            return disk
        }
        let task = Task<[CLLocationCoordinate2D], Never> {
            await Self.requestDrivingPath(start: start, end: end)
        }
        inFlight[key] = task
        let coords = await task.value
        inFlight[key] = nil
        let usable = coords.count >= 2 ? coords : [start, end]
        memory[key] = usable
        writeDisk(key, coordinates: usable)
        return usable
    }

    static func decimate(_ coordinates: [CLLocationCoordinate2D], maxCount: Int = maxPoints) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maxCount, maxCount >= 3 else { return coordinates }
        let step = Double(coordinates.count - 1) / Double(maxCount - 1)
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(maxCount)
        for index in 0..<(maxCount - 1) {
            result.append(coordinates[Int((Double(index) * step).rounded(.down))])
        }
        if let last = coordinates.last {
            result.append(last)
        }
        return result
    }

    static func heatmapSamples(_ coordinates: [CLLocationCoordinate2D], count: Int) -> [CLLocationCoordinate2D] {
        decimate(coordinates, maxCount: max(count, 2))
    }

    private static func requestDrivingPath(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return [] }
            var coords = Array(
                repeating: kCLLocationCoordinate2DInvalid,
                count: route.polyline.pointCount
            )
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: coords.count))
            return decimate(coords.filter { CLLocationCoordinate2DIsValid($0) })
        } catch {
            return []
        }
    }

    private static func cacheKey(
        pairKey: String,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> String {
        String(
            format: "%@:%.4f,%.4f:%.4f,%.4f",
            pairKey,
            start.latitude,
            start.longitude,
            end.latitude,
            end.longitude
        )
    }

    private func diskURL(_ key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(Self.stableName(for: key)).bin")
    }

    private func readDisk(_ key: String) -> [CLLocationCoordinate2D]? {
        guard let data = try? Data(contentsOf: diskURL(key)), data.count >= 16 else { return nil }
        let count = data.count / 16
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Double.self).baseAddress else { return [] }
            return (0..<count).map { index in
                CLLocationCoordinate2D(latitude: base[index * 2], longitude: base[index * 2 + 1])
            }
        }
    }

    private func writeDisk(_ key: String, coordinates: [CLLocationCoordinate2D]) {
        var values: [Double] = []
        values.reserveCapacity(coordinates.count * 2)
        for coordinate in coordinates {
            values.append(coordinate.latitude)
            values.append(coordinate.longitude)
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: diskURL(key), options: .atomic)
    }

    private static func stableName(for key: String) -> String {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
