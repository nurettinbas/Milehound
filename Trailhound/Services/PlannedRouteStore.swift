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
    /// Apple's step list. Empty when the provider has no instructions. Not saved.
    var steps: [RouteStep] = []

    static func == (lhs: DrivingRoute, rhs: DrivingRoute) -> Bool {
        lhs.distanceMeters == rhs.distanceMeters
            && lhs.expectedTravelTime == rhs.expectedTravelTime
            && lhs.steps == rhs.steps
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
            expectedTravelTime: route.expectedTravelTime,
            steps: route.steps.map {
                RouteStep(instruction: $0.instructions, distanceMeters: $0.distance)
            }
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
    /// True for a moment after the estimate jumps up, so the chip says it is calculating.
    private(set) var showsRecalculatingETA = false
    /// The car left the planned road. Cleared once a fix is back on the line.
    private(set) var missedTurn = false
    /// A replacement route is in flight after a miss. The previous line stays up meanwhile.
    private(set) var isRerouting = false
    /// Next Apple maneuver and the distance until it. Memory only, same as the route.
    private(set) var upcomingManeuver: UpcomingManeuver?

    /// Change stamp for the MapKit coordinator (read on display ticks, not in a body).
    @ObservationIgnored private(set) var version = 0
    @ObservationIgnored var provider: DrivingRouteProviding
    @ObservationIgnored var isConnected: () -> Bool
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private(set) var requestTask: Task<Void, Never>?
    @ObservationIgnored private var cumulative: [CLLocationDistance] = []
    @ObservationIgnored private var offRouteStreak = 0
    /// True after this departure already asked for a new route. The next ask waits for the
    /// throttle, so a route that is still settling cannot request on every fix.
    @ObservationIgnored private var reroutedThisDeparture = false
    @ObservationIgnored private var lastRequestAt: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastVehicle: CLLocationCoordinate2D?
    /// When `remainingTravelTime` was last written. The chip counts down from there between fixes.
    @ObservationIgnored private var etaAnchoredAt: Date?
    @ObservationIgnored private var etaRecalcTask: Task<Void, Never>?

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
        etaAnchoredAt = nil
        showsRecalculatingETA = false
        etaRecalcTask?.cancel()
        upcomingManeuver = nil
        offRouteStreak = 0
        reroutedThisDeparture = false
        missedTurn = false
        isRerouting = false
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
        etaAnchoredAt = nil
        showsRecalculatingETA = false
        etaRecalcTask?.cancel()
        upcomingManeuver = nil
        offRouteStreak = 0
        reroutedThisDeparture = false
        missedTurn = false
        isRerouting = false
        lastRequestAt = nil
        lastVehicle = nil
        status = .idle
        if hadContent {
            bumpVersion()
        }
    }

    /// Every recorded GPS fix. Updates progress, clears on arrival, and reroutes when off route.
    /// `course` and `speed` come from the same fix; negative means Core Location has none.
    func noteVehicle(
        _ vehicle: CLLocationCoordinate2D,
        course: CLLocationDirection = -1,
        speed: CLLocationSpeed = -1
    ) {
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

        let headingMiss = PlannedRouteProgress.missedTheTurn(
            course: course,
            speed: speed,
            routeBearing: measure.segmentBearing
        )
        let away = measure.offRouteMeters > PlannedRouteProgress.offRouteMeters
        if away || headingMiss {
            offRouteStreak += 1
        } else {
            offRouteStreak = 0
            missedTurn = false
            reroutedThisDeparture = false
        }
        applyRemaining(measure.remainingMeters, route: route)

        let confirmed = PlannedRouteProgress.confirmedMiss(offRouteStreak: offRouteStreak)
        if confirmed {
            missedTurn = true
        }
        guard requestTask == nil, confirmed else {
            refreshForTraffic(from: vehicle)
            return
        }
        // The first miss of this departure recalculates immediately. The route that was
        // just fetched does not count, so a turn missed a few seconds into the drive is
        // not held back by that request. A further miss waits out the short throttle.
        if reroutedThisDeparture {
            guard PlannedRouteProgress.shouldReroute(
                offRouteStreak: offRouteStreak,
                lastRequestAt: lastRequestAt,
                now: now()
            ) else { return }
        }
        reroutedThisDeparture = true
        request(from: vehicle, reroute: true)
    }

    /// Minutes still to drive, counting down from the last estimate until the next one.
    func displayedRemaining(at now: Date) -> TimeInterval? {
        guard let remainingTravelTime else { return nil }
        let elapsed = etaAnchoredAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, remainingTravelTime - elapsed)
    }

    /// The new estimate is at least a minute longer. The chip says it is calculating, then shows the minutes.
    private func noteETAIncreased() {
        showsRecalculatingETA = true
        etaRecalcTask?.cancel()
        etaRecalcTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            showsRecalculatingETA = false
        }
    }

    /// A new route while still on the road. A longer result flashes “calculating”, then the new minutes.
    private func refreshForTraffic(from vehicle: CLLocationCoordinate2D) {
        guard route != nil, requestTask == nil, !missedTurn, !isRerouting else { return }
        guard PlannedRouteProgress.canRequest(
            lastRequestAt: lastRequestAt,
            now: now(),
            interval: PlannedRouteProgress.trafficRefresh
        ) else { return }
        request(from: vehicle)
    }

    private func request(from origin: CLLocationCoordinate2D, reroute: Bool = false) {
        guard let destination else { return }
        cancelRequest()
        lastRequestAt = now()
        offRouteStreak = 0
        if reroute {
            isRerouting = true
        } else if route == nil {
            status = .loading
        }
        guard isConnected() else {
            isRerouting = false
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
                self.isRerouting = false
                if self.route == nil {
                    self.status = self.isConnected() ? .failed : .offline
                    self.missedTurn = false
                }
            }
        }
    }

    private func apply(_ fetched: DrivingRoute, origin: CLLocationCoordinate2D) {
        let valid = fetched.coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count >= 2 else {
            isRerouting = false
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
            expectedTravelTime: max(0, fetched.expectedTravelTime),
            steps: fetched.steps
        )
        route = next
        cumulative = PlannedRouteProgress.cumulativeDistances(display)
        status = .ready
        offRouteStreak = 0
        missedTurn = false
        isRerouting = false
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
            let showing = displayedRemaining(at: now()) ?? 0
            let jumped = remainingTravelTime != nil && roundedTime >= showing + 60
            remainingTravelTime = roundedTime
            etaAnchoredAt = now()
            if jumped {
                noteETAIncreased()
            }
        }
        let traveled = max(0, route.distanceMeters - roadMeters)
        let next = PlannedRouteProgress.upcomingManeuver(traveledMeters: traveled, steps: route.steps)
        if upcomingManeuver != next {
            upcomingManeuver = next
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
