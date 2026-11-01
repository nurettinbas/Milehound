import CoreLocation
import Foundation
import MapKit
import UIKit

/// Session-local map pins for live follow (not a SwiftData schema change).
enum LiveFollowMapPinKind: String, Equatable {
    case start
    case pause
    case tripStop
    /// Planned-route destination. Same red end pin as trip detail.
    case destination
}

struct LiveFollowMapPin: Identifiable, Equatable {
    let id: String
    let kind: LiveFollowMapPinKind
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: String, kind: LiveFollowMapPinKind, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.kind = kind
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    static func == (lhs: LiveFollowMapPin, rhs: LiveFollowMapPin) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
    }
}

/// Builds the pin list shown on the live follow map.
enum LiveFollowMapPinBuilder {
    /// Prefer the latched first breadcrumb; otherwise the live path start; otherwise GPS.
    static func resolvedStartCoordinate(
        latched: CLLocationCoordinate2D?,
        breadcrumbStart: CLLocationCoordinate2D?,
        fallback: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        latched ?? breadcrumbStart ?? fallback
    }

    /// Start pin once from the first breadcrumb / trip start. Pause pins accumulate;
    /// resume must not remove them. Trip stops from automatic dwell detection are included.
    static func pins(
        startCoordinate: CLLocationCoordinate2D?,
        pauseCoordinates: [CLLocationCoordinate2D],
        tripStopCoordinates: [CLLocationCoordinate2D],
        destinationCoordinate: CLLocationCoordinate2D? = nil
    ) -> [LiveFollowMapPin] {
        var result: [LiveFollowMapPin] = []
        if let startCoordinate {
            result.append(
                LiveFollowMapPin(
                    id: "start",
                    kind: .start,
                    coordinate: startCoordinate
                )
            )
        }
        for (index, coordinate) in pauseCoordinates.enumerated() {
            result.append(
                LiveFollowMapPin(
                    id: "pause-\(index)",
                    kind: .pause,
                    coordinate: coordinate
                )
            )
        }
        for (index, coordinate) in tripStopCoordinates.enumerated() {
            result.append(
                LiveFollowMapPin(
                    id: "stop-\(index)",
                    kind: .tripStop,
                    coordinate: coordinate
                )
            )
        }
        if let destinationCoordinate, CLLocationCoordinate2DIsValid(destinationCoordinate) {
            result.append(
                LiveFollowMapPin(
                    id: "destination",
                    kind: .destination,
                    coordinate: destinationCoordinate
                )
            )
        }
        return result
    }
}

/// Live-follow route geometry: GPS history pieces + a growing tail to the puck.
/// Display-only — does not write SwiftData / breadcrumbs.
///
/// History and tip never share interior vertices. Real GPS gaps stay as separate
/// pieces (no bird-flight chord). The tip is dropped rather than invented across a gap.
enum LiveFollowGrowingRoute {
    /// Keep the newest raw GPS points so Douglas-Peucker cannot rewrite the growing tail.
    static let liveTailKeep = 40
    /// Short sessions stay raw; decimate only the aged prefix of a long drive.
    static let liveRawUntil = 500
    /// Refuse a tip chord longer than this (GPS gap / dead-reckon runaway).
    static let tipMaxGapMeters: CLLocationDistance = 120
    /// Ignore sub-pixel jitter so a parked puck does not draw a 2-point stub.
    static let tipMinGapMeters: CLLocationDistance = 0.05
    /// Floor for a point-sized trail box so the rect is not zero. Camera air is applied later.
    static let overviewMinPadMeters: CLLocationDistance = 120

    /// Last live segment: aged prefix may be decimated; the newest points stay raw.
    static func liveActiveCoordinates(_ raw: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard raw.count > liveRawUntil else { return raw }
        let tipCount = min(liveTailKeep, raw.count)
        let prefix = Array(raw.dropLast(tipCount))
        let tip = Array(raw.suffix(tipCount))
        guard prefix.count >= 2 else { return raw }
        let samples = prefix.enumerated().map { index, coordinate in
            RouteSample(
                coordinate: coordinate,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                speedMps: nil
            )
        }
        let decimated = RouteDisplayPath.decimate(
            samples: samples,
            maxCount: 1_200,
            chordCapMeters: RouteDisplayPath.baseChordLimitMeters
        )
        return decimated.map(\.coordinate) + tip
    }

    /// GPS body only — pieces with fewer than two points cannot form a polyline.
    static func historyPieces(from segments: [[CLLocationCoordinate2D]]) -> [[CLLocationCoordinate2D]] {
        segments.filter { $0.count >= 2 }
    }

    /// Last recorded vertex of the active run — the tip starts here.
    static func tipAnchor(from segments: [[CLLocationCoordinate2D]]) -> CLLocationCoordinate2D? {
        segments.last { !$0.isEmpty }?.last
    }

    /// Vertex before the anchor — gives the tip a direction of travel to agree with.
    static func tipApproach(from segments: [[CLLocationCoordinate2D]]) -> CLLocationCoordinate2D? {
        guard let piece = segments.last(where: { $0.count >= 2 }) else { return nil }
        return piece[piece.count - 2]
    }

    /// Two-point `[anchor, vehicle]` stroke, or `nil` when it would invent a chord.
    ///
    /// A tip pointing against the direction of travel would render as blue road *ahead*
    /// of the vehicle and snap back on the next breadcrumb, so it is dropped instead.
    static func tipSegment(
        anchor: CLLocationCoordinate2D?,
        previous: CLLocationCoordinate2D? = nil,
        vehicle: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D]? {
        guard let anchor, let vehicle else { return nil }
        let delta = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            .distance(from: CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude))
        guard delta > tipMinGapMeters, delta <= tipMaxGapMeters else { return nil }
        if let previous, isBackward(previous: previous, anchor: anchor, vehicle: vehicle) {
            return nil
        }
        return [anchor, vehicle]
    }

    /// Growing-run stroke: uncommitted history vertices, extended to the live vehicle
    /// when that extension passes the `tipSegment` guards. Falls back to the bare tail
    /// (when drawable) so recorded points never vanish just because the chord is refused.
    static func tailSegment(
        tail: [CLLocationCoordinate2D],
        vehicle: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D]? {
        guard let anchor = tail.last else { return nil }
        let previous = tail.count >= 2 ? tail[tail.count - 2] : nil
        if let tip = tipSegment(anchor: anchor, previous: previous, vehicle: vehicle),
           let vehiclePoint = tip.last
        {
            return tail + [vehiclePoint]
        }
        return tail.count >= 2 ? tail : nil
    }

    /// Dot product of `previous → anchor` with `anchor → vehicle`, in local metres.
    private static func isBackward(
        previous: CLLocationCoordinate2D,
        anchor: CLLocationCoordinate2D,
        vehicle: CLLocationCoordinate2D
    ) -> Bool {
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = metresPerDegreeLat * cos(anchor.latitude * .pi / 180)
        let travelX = (anchor.longitude - previous.longitude) * metresPerDegreeLon
        let travelY = (anchor.latitude - previous.latitude) * metresPerDegreeLat
        let tipX = (vehicle.longitude - anchor.longitude) * metresPerDegreeLon
        let tipY = (vehicle.latitude - anchor.latitude) * metresPerDegreeLat
        guard travelX * travelX + travelY * travelY > 0.01 else { return false }
        return travelX * tipX + travelY * tipY < 0
    }

    /// Tight box around the traveled path and the puck. A short axis grows to
    /// `overviewMinPadMeters`; a long drive is not padded by a fraction of itself.
    /// With a planned route, the destination joins the box so the whole drive ahead shows too.
    static func overviewMapRect(
        historyPieces: [[CLLocationCoordinate2D]],
        vehicle: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D? = nil
    ) -> MKMapRect {
        var rect = MKMapRect.null
        func include(_ coordinate: CLLocationCoordinate2D) {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: point, size: .init(width: 0, height: 0)))
        }
        for piece in historyPieces {
            for coordinate in piece {
                include(coordinate)
            }
        }
        if let vehicle {
            include(vehicle)
        }
        if let destination, CLLocationCoordinate2DIsValid(destination) {
            include(destination)
        }
        guard !rect.isNull else { return .null }
        let latitude = MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude
        let metersPerPoint = MKMetersPerMapPointAtLatitude(latitude)
        let minPad = overviewMinPadMeters / max(metersPerPoint, 1e-9)
        if rect.size.width < minPad {
            let grow = minPad - rect.size.width
            rect = rect.insetBy(dx: -grow / 2, dy: 0)
        }
        if rect.size.height < minPad {
            let grow = minPad - rect.size.height
            rect = rect.insetBy(dx: 0, dy: -grow / 2)
        }
        return rect
    }
}

/// One-shot north-up frame for Show entire route. Does not touch the follow camera.
enum LiveFollowOverviewFit {
    /// Pitch 0: visible ground height ÷ eye distance. Measured across phone, pad, and landscape.
    static let fallbackVisibleHeightPerDistance: Double = 0.536
    /// Extra air around the trail inside the clear band (about 15%).
    static let airMargin: Double = 1.15
    /// Just-started trip stays a neighborhood, not a rooftop.
    static let minimumContextMeters: CLLocationDistance = 400
    static let minimumEyeDistance: CLLocationDistance = 220
    /// Same length as the follow/recenter flight.
    static let easeDuration: CFTimeInterval = 0.58
    static let easeDurationMax: CFTimeInterval = 0.85

    struct Target {
        var center: CLLocationCoordinate2D
        var distanceMeters: CLLocationDistance
        /// Full view the camera shows, before chrome. Tests check the trail against this.
        var visibleRect: MKMapRect
    }

    /// Place `routeRect` in the unobstructed band of `mapSize`.
    ///
    /// Eye distance is `visible height ÷ visibleHeightPerDistance` at pitch 0.
    /// The ratio is read from the live map when it is already flat; otherwise the fallback.
    static func target(
        routeRect: MKMapRect,
        mapSize: CGSize,
        contentInsets: UIEdgeInsets,
        visibleHeightPerDistance: Double
    ) -> Target? {
        guard !routeRect.isNull, mapSize.width > 1, mapSize.height > 1 else { return nil }
        let eyeScale = visibleHeightPerDistance > 0.05
            ? visibleHeightPerDistance
            : fallbackVisibleHeightPerDistance

        let mid = MKMapPoint(x: routeRect.midX, y: routeRect.midY).coordinate
        let metersPerPoint = MKMetersPerMapPointAtLatitude(mid.latitude)
        guard metersPerPoint > 1e-9 else { return nil }

        var fitted = routeRect
        let minPoints = minimumContextMeters / metersPerPoint
        if fitted.size.width < minPoints {
            let grow = minPoints - fitted.size.width
            fitted = fitted.insetBy(dx: -grow / 2, dy: 0)
        }
        if fitted.size.height < minPoints {
            let grow = minPoints - fitted.size.height
            fitted = fitted.insetBy(dx: 0, dy: -grow / 2)
        }

        let usableWidth = max(mapSize.width - contentInsets.left - contentInsets.right, 48)
        let usableHeight = max(mapSize.height - contentInsets.top - contentInsets.bottom, 48)
        let pointsPerView = max(
            fitted.size.width / usableWidth,
            fitted.size.height / usableHeight
        ) * airMargin

        let fullWidth = pointsPerView * mapSize.width
        let fullHeight = pointsPerView * mapSize.height
        let routeCenter = MKMapPoint(x: fitted.midX, y: fitted.midY)
        let clearCenterX = contentInsets.left + usableWidth / 2
        let clearCenterY = contentInsets.top + usableHeight / 2
        let mapCenterX = routeCenter.x + (0.5 - clearCenterX / mapSize.width) * fullWidth
        let mapCenterY = routeCenter.y + (0.5 - clearCenterY / mapSize.height) * fullHeight
        let visible = MKMapRect(
            x: mapCenterX - fullWidth / 2,
            y: mapCenterY - fullHeight / 2,
            width: fullWidth,
            height: fullHeight
        )
        let distance = max(minimumEyeDistance, (fullHeight * metersPerPoint) / eyeScale)
        let center = MKMapPoint(x: mapCenterX, y: mapCenterY).coordinate
        return Target(center: center, distanceMeters: distance, visibleRect: visible)
    }

    /// Overview blends eye distance in log space so the scale moves evenly.
    /// Recenter stays linear — same formula the flight used before.
    static func easedDistance(
        from: CLLocationDistance,
        to: CLLocationDistance,
        t: Double,
        logarithmic: Bool
    ) -> CLLocationDistance {
        let clamped = min(1, max(0, t))
        if logarithmic, from > 1, to > 1 {
            return from * pow(to / from, clamped)
        }
        return from + (to - from) * clamped
    }

    /// 0.58 s when the zoom barely changes; up to 0.85 s on a large pull-back.
    static func overviewDuration(
        fromDistance: CLLocationDistance,
        toDistance: CLLocationDistance
    ) -> CFTimeInterval {
        let near = max(min(fromDistance, toDistance), 1)
        let far = max(fromDistance, toDistance)
        let zoom = log2(far / near)
        let extra = min(1, max(0, zoom) / 3) * (easeDurationMax - easeDuration)
        return easeDuration + extra
    }
}
