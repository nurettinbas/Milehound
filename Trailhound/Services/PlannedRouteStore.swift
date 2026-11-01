import CoreLocation
import Foundation
import MapKit

struct PlannedRouteDestination: Equatable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct DrivingRoute: Equatable {
    var coordinates: [CLLocationCoordinate2D]
    var distanceMeters: CLLocationDistance
    var expectedTravelTime: TimeInterval

    static func == (lhs: DrivingRoute, rhs: DrivingRoute) -> Bool {
        lhs.distanceMeters == rhs.distanceMeters
            && lhs.expectedTravelTime == rhs.expectedTravelTime
            && lhs.coordinates.count == rhs.coordinates.count
            && zip(lhs.coordinates, rhs.coordinates).allSatisfy {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
    }
}

protocol DrivingRouteProviding: Sendable {
    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> DrivingRoute
}

enum DrivingRouteError: Error {
    case noRoute
}

/// Apple Maps driving directions. The request goes to Apple; nothing reaches a Trailhound server.
struct MapKitDrivingRouteProvider: DrivingRouteProviding {
    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> DrivingRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first, route.polyline.pointCount >= 2 else {
            throw DrivingRouteError.noRoute
        }
        var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        return DrivingRoute(
            coordinates: coordinates.filter { CLLocationCoordinate2DIsValid($0) },
            distanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime
        )
    }
}

/// Straight line at 50 km/h. UI tests only — no network, no real GPS.
struct UITestDrivingRouteProvider: DrivingRouteProviding {
    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> DrivingRoute {
        let distance = PlannedRouteProgress.meters(origin, destination)
        return DrivingRoute(
            coordinates: [origin, destination],
            distanceMeters: distance,
            expectedTravelTime: distance / (50 / 3.6)
        )
    }
}

enum PlannedRouteStatus: Equatable {
    case idle
    /// Destination set; waiting for a GPS fix or for MapKit.
    case loading
    case ready
    case offline
    case failed
}

/// Destination and planned driving route for the active recording.
///
/// Memory only: never written to SwiftData or disk. `TripRecordingService` owns it so the
/// destination survives closing and reopening the live map, and clears it when the trip ends.
@Observable
@MainActor
final class PlannedRouteStore {
    /// MapKit gets at most this many vertices, same budget as the trip detail route.
    static let maxDisplayPoints = 1_500

    private(set) var destination: PlannedRouteDestination?
    private(set) var status: PlannedRouteStatus = .idle
    private(set) var route: DrivingRoute?
    /// Rounded to 10 m so a 1 Hz fix does not re-render the chip for sub-step changes.
    private(set) var remainingMeters: CLLocationDistance?
    private(set) var remainingTravelTime: TimeInterval?

    /// Change stamp for the MapKit coordinator (read on display ticks, not in a body).
    @ObservationIgnored private(set) var version = 0
    @ObservationIgnored var provider: DrivingRouteProviding
    @ObservationIgnored var isConnected: () -> Bool
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private(set) var requestTask: Task<Void, Never>?
    @ObservationIgnored private var cumulative: [CLLocationDistance] = []
    @ObservationIgnored private var offRouteStreak = 0
    @ObservationIgnored private var lastRequestAt: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastVehicle: CLLocationCoordinate2D?

    var hasDestination: Bool { destination != nil }

    init(
        provider: DrivingRouteProviding? = nil,
        isConnected: (() -> Bool)? = nil
    ) {
        self.provider = provider
            ?? (UITestSupport.seedsPlannedRoute ? UITestDrivingRouteProvider() : MapKitDrivingRouteProvider())
        self.isConnected = isConnected ?? { NetworkMonitor.shared.isConnected }
    }

    /// Sets the destination and asks for a route. Without a GPS fix yet, the request waits
    /// for the first `noteVehicle`.
    func setDestination(_ destination: PlannedRouteDestination, origin: CLLocationCoordinate2D?) {
        guard CLLocationCoordinate2DIsValid(destination.coordinate) else { return }
        cancelRequest()
        generation &+= 1
        self.destination = destination
        route = nil
        cumulative = []
        remainingMeters = nil
        remainingTravelTime = nil
        offRouteStreak = 0
        lastRequestAt = nil
        status = .loading
        bumpVersion()
        let start = origin.flatMap { CLLocationCoordinate2DIsValid($0) ? $0 : nil } ?? lastVehicle
        if let start {
            request(from: start)
        }
    }

    func clear() {
        cancelRequest()
        generation &+= 1
        let hadContent = destination != nil || route != nil
        destination = nil
        route = nil
        cumulative = []
        remainingMeters = nil
        remainingTravelTime = nil
        offRouteStreak = 0
        lastRequestAt = nil
        lastVehicle = nil
        status = .idle
        if hadContent {
            bumpVersion()
        }
    }

    /// Every recorded GPS fix. Updates progress, clears on arrival, and reroutes when off route.
    func noteVehicle(_ vehicle: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(vehicle) else { return }
        lastVehicle = vehicle
        guard let destination else { return }

        if PlannedRouteProgress.hasArrived(vehicle: vehicle, destination: destination.coordinate) {
            clear()
            return
        }

        guard let route else {
            if requestTask == nil, PlannedRouteProgress.canRequest(lastRequestAt: lastRequestAt, now: now()) {
                request(from: vehicle)
            }
            return
        }

        guard let measure = PlannedRouteProgress.measure(
            vehicle: vehicle,
            along: route.coordinates,
            cumulative: cumulative
        ) else { return }

        if measure.offRouteMeters > PlannedRouteProgress.offRouteMeters {
            offRouteStreak += 1
        } else {
            offRouteStreak = 0
        }
        applyRemaining(measure.remainingMeters, route: route)

        if requestTask == nil,
           PlannedRouteProgress.shouldReroute(
               offRouteStreak: offRouteStreak,
               lastRequestAt: lastRequestAt,
               now: now()
           )
        {
            request(from: vehicle)
        }
    }

    private func request(from origin: CLLocationCoordinate2D) {
        guard let destination else { return }
        cancelRequest()
        lastRequestAt = now()
        offRouteStreak = 0
        if route == nil {
            status = .loading
        }
        guard isConnected() else {
            if route == nil {
                status = .offline
            }
            return
        }
        let token = generation
        let provider = provider
        let target = destination.coordinate
        requestTask = Task { @MainActor [weak self] in
            let result: Result<DrivingRoute, Error>
            do {
                result = .success(try await provider.route(from: origin, to: target))
            } catch {
                result = .failure(error)
            }
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.requestTask = nil
            switch result {
            case .success(let fetched):
                self.apply(fetched, origin: origin)
            case .failure:
                if self.route == nil {
                    self.status = self.isConnected() ? .failed : .offline
                }
            }
        }
    }

    private func apply(_ fetched: DrivingRoute, origin: CLLocationCoordinate2D) {
        let valid = fetched.coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 2 else {
            if route == nil {
                status = .failed
            }
            return
        }
        let display = FrequentRouteRoadPathCache.decimate(valid, maxCount: Self.maxDisplayPoints)
        let next = DrivingRoute(
            coordinates: display,
            distanceMeters: fetched.distanceMeters > 0
                ? fetched.distanceMeters
                : PlannedRouteProgress.cumulativeDistances(display).last ?? 0,
            expectedTravelTime: max(0, fetched.expectedTravelTime)
        )
        route = next
        cumulative = PlannedRouteProgress.cumulativeDistances(display)
        status = .ready
        offRouteStreak = 0
        let from = lastVehicle ?? origin
        if let measure = PlannedRouteProgress.measure(vehicle: from, along: display, cumulative: cumulative) {
            applyRemaining(measure.remainingMeters, route: next)
        } else {
            applyRemaining(next.distanceMeters, route: next)
        }
        bumpVersion()
    }

    private func applyRemaining(_ meters: CLLocationDistance, route: DrivingRoute) {
        let lineLength = cumulative.last ?? route.distanceMeters
        // MapKit's distance follows roads; the decimated line is a little shorter.
        let scale = lineLength > 0 ? route.distanceMeters / lineLength : 1
        let roadMeters = max(0, meters * scale)
        let rounded = (roadMeters / 10).rounded() * 10
        if remainingMeters != rounded {
            remainingMeters = rounded
        }
        let time = PlannedRouteProgress.remainingTravelTime(
            remainingMeters: roadMeters,
            routeMeters: route.distanceMeters,
            expectedTravelTime: route.expectedTravelTime
        )
        let roundedTime = (time / 30).rounded() * 30
        if remainingTravelTime != roundedTime {
            remainingTravelTime = roundedTime
        }
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
    }

    private func bumpVersion() {
        version &+= 1
    }
}
