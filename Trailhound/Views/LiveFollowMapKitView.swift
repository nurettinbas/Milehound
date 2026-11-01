import MapKit
import SwiftUI
import UIKit

/// Live-follow route stroke — single solid palette tint (no casing).
///
/// Applied to MapKit's own vector polyline renderers on purpose: `lineWidth` stays
/// a constant screen width under any zoom *and* under camera pitch, which a custom
/// `MKOverlayRenderer` cannot do (MapKit rasterises those flat, then warps the
/// bitmap, so the stroke fattens toward the bottom of a 3D view and seams while panning).
enum LiveFollowRouteStrokeStyle {
    static let solidWidth: CGFloat = 7.2
    /// White edge showing on each side of the traveled trail.
    static let casingInset: CGFloat = 1.8
    static var casingWidth: CGFloat { solidWidth + casingInset * 2 }

    static func solidColor(for palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        UIColor(palette.tintColor(for: scheme))
    }

    static func applyCasing(to renderer: MKOverlayPathRenderer) {
        renderer.strokeColor = .white
        renderer.lineWidth = casingWidth
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.miterLimit = 1
        renderer.lineDashPattern = nil
    }

    static func apply(to renderer: MKOverlayPathRenderer, color: UIColor) {
        renderer.strokeColor = color
        renderer.lineWidth = solidWidth
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.miterLimit = 1
        renderer.lineDashPattern = nil
    }

    /// Paints `overlay` by its role: the traveled trail solid, the planned route a lighter road.
    static func apply(to renderer: MKOverlayPathRenderer, for overlay: MKOverlay, color: UIColor) {
        switch LiveFollowOverlayRole.of(overlay) {
        case .traveled:
            apply(to: renderer, color: color)
        case .casing:
            applyCasing(to: renderer)
        case .planned:
            LiveFollowPlannedRouteStrokeStyle.apply(to: renderer, color: color)
        }
    }
}

/// Road still ahead: one solid line, the trail's width, the theme tint lightened toward
/// white. Opaque, so it stays visible on the road. A second stroke separates in 3D.
enum LiveFollowPlannedRouteStrokeStyle {
    static let width: CGFloat = LiveFollowRouteStrokeStyle.solidWidth
    /// Share of the way from the theme tint toward white.
    static let lighten: CGFloat = 0.30

    static func apply(to renderer: MKOverlayPathRenderer, color: UIColor) {
        renderer.strokeColor = lightened(color)
        renderer.lineWidth = width
        // Chunks and the lead share a vertex; round caps would overlap there as darker dots.
        renderer.lineCap = .butt
        renderer.lineJoin = .round
        renderer.miterLimit = 1
        renderer.lineDashPattern = nil
    }

    static func lightened(_ color: UIColor) -> UIColor {
        let resolved = color.resolvedColor(with: .current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return color }
        return UIColor(
            red: red + (1 - red) * lighten,
            green: green + (1 - green) * lighten,
            blue: blue + (1 - blue) * lighten,
            alpha: 1
        )
    }
}

/// Planned route line. Its own type so the trail restyle never paints it solid.
final class PlannedRoutePolyline: MKPolyline {}

/// Geometry for the road still ahead. The route is cut into fixed chunks that are uploaded
/// once and dropped as the car passes them. A short lead line runs from the puck's centre
/// and eases onto the route centreline, so the plan leaves the car exactly where the trail
/// ends even when GPS sits a lane or a carriageway off Apple's line. Only the lead is
/// swapped while driving. Lengths are in map points.
enum LiveFollowPlannedAhead {
    /// Farther than this from the line, the cut holds still (off route, or a parallel road).
    static let toleranceMeters: CLLocationDistance = 75
    /// The search only looks this far ahead of the last cut, so a later part of the route
    /// that runs close by (a U-turn, the other carriageway) can never jump the cut forward.
    static let windowMeters: CLLocationDistance = 400
    /// Farther than this from the line, the lead lets go of the puck. A longer bridge is the
    /// snake that reaches back to a turn the car has left.
    static let attachMeters: CLLocationDistance = 35
    /// The lead eases from the puck onto the route over this distance.
    static let blendMeters: CLLocationDistance = 80
    /// Sample spacing inside the blend, so the ease is a curve and not one long chord.
    static let blendStepMeters: CLLocationDistance = 8
    /// Vertices per fixed chunk. Neighbours share their boundary vertex.
    static let chunkPoints = 32

    static func chunkCount(pointCount: Int) -> Int {
        pointCount < 2 ? 0 : (pointCount - 2) / chunkPoints + 1
    }

    static func chunkStartVertex(_ chunk: Int) -> Int {
        chunk * chunkPoints
    }

    static func chunk(_ chunk: Int, of points: [MKMapPoint]) -> ArraySlice<MKMapPoint> {
        let start = chunkStartVertex(chunk)
        let end = min(start + chunkPoints, points.count - 1)
        return points[start...end]
    }

    /// First chunk drawn as a fixed overlay: it starts at least `blendMeters` past the cut.
    /// Returns `chunkCount` when the lead reaches the end of the route on its own.
    static func firstFixedChunk(along: Double, cumulative: [Double], metersPerPoint: Double) -> Int {
        let count = chunkCount(pointCount: cumulative.count)
        let target = along + blendMeters / max(metersPerPoint, .leastNonzeroMagnitude)
        var chunk = 0
        while chunk < count, cumulative[chunkStartVertex(chunk)] < target {
            chunk += 1
        }
        return chunk
    }

    /// Point on the route `along` map points from its start, walking forward from `segment`.
    private static func point(
        at along: Double,
        points: [MKMapPoint],
        cumulative: [Double],
        segment: inout Int
    ) -> MKMapPoint {
        while segment < points.count - 2, cumulative[segment + 1] < along {
            segment += 1
        }
        let a = points[segment]
        let b = points[segment + 1]
        let length = cumulative[segment + 1] - cumulative[segment]
        let t = length > 0 ? min(1, max(0, (along - cumulative[segment]) / length)) : 0
        return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Lead line from the car to `endVertex`. Starts on `vehicle` (the puck centre) and eases
    /// onto the route over `blendMeters`; nil `vehicle` starts on the route itself.
    static func lead(
        vehicle: MKMapPoint?,
        segment: Int,
        along: Double,
        points: [MKMapPoint],
        cumulative: [Double],
        endVertex: Int,
        metersPerPoint: Double
    ) -> [MKMapPoint] {
        guard points.count >= 2, cumulative.count == points.count else { return [] }
        let last = points.count - 1
        let end = min(max(endVertex, 0), last)
        let endAlong = cumulative[end]
        guard endAlong > along else { return [] }
        var walk = min(max(segment, 0), points.count - 2)
        let origin = point(at: along, points: points, cumulative: cumulative, segment: &walk)
        let offsetX = vehicle.map { $0.x - origin.x } ?? 0
        let offsetY = vehicle.map { $0.y - origin.y } ?? 0
        let blend = blendMeters / max(metersPerPoint, .leastNonzeroMagnitude)
        let step = blendStepMeters / max(metersPerPoint, .leastNonzeroMagnitude)

        var stations: [Double] = []
        var s = along
        while s < min(along + blend, endAlong) {
            stations.append(s)
            s += step
        }
        var vertex = min(max(segment, 0), last) + 1
        while vertex <= end {
            if cumulative[vertex] > along + blend {
                stations.append(cumulative[vertex])
            }
            vertex += 1
        }
        if stations.last.map({ $0 < endAlong }) ?? true {
            stations.append(endAlong)
        }

        walk = min(max(segment, 0), points.count - 2)
        var result: [MKMapPoint] = []
        result.reserveCapacity(stations.count)
        for station in stations {
            let base = point(at: station, points: points, cumulative: cumulative, segment: &walk)
            let u = blend > 0 ? min(1, (station - along) / blend) : 1
            let weight = 0.5 * (1 + cos(Double.pi * u))
            result.append(MKMapPoint(x: base.x + offsetX * weight, y: base.y + offsetY * weight))
        }
        return result
    }

    static func cumulative(_ points: [MKMapPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result: [Double] = [0]
        result.reserveCapacity(points.count)
        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            result.append(result[index - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        return result
    }

    /// The lead holds the puck only while the car is still on the road. Past `attachMeters`,
    /// or pointed away from it while already well off the centreline, the line stays on the
    /// route instead of stretching back to the car.
    static func attachesLead(
        distanceMeters: CLLocationDistance,
        course: CLLocationDirection,
        routeBearing: CLLocationDirection
    ) -> Bool {
        if distanceMeters > attachMeters { return false }
        if distanceMeters > 18,
           course >= 0,
           routeBearing >= 0,
           PlannedRouteProgress.angleDelta(course, routeBearing) >= PlannedRouteProgress.missedTurnDegrees
        {
            return false
        }
        return true
    }

    /// Next cut from `fromSegment` onward, or nil when the vehicle is not on the line.
    /// `recover` scans past the window. Only the moment a route is loaded uses it, so a
    /// missed turn cannot jump the cut onto a later stretch and erase the line in between.
    /// A valid `course` lets a following cut that fell behind the window (backgrounded, paused,
    /// GPS gap) catch up, but only onto a stretch the car is on and driving along. Otherwise
    /// the passed road keeps its planned line beside the trail.
    static func advance(
        vehicle: MKMapPoint,
        points: [MKMapPoint],
        cumulative: [Double],
        fromSegment: Int,
        recover: Bool = false,
        course: CLLocationDirection = -1
    ) -> (segment: Int, along: Double, distanceMeters: CLLocationDistance)? {
        guard points.count >= 2, cumulative.count == points.count, let total = cumulative.last, total > 0 else {
            return nil
        }
        let metersPerPoint = MKMetersPerMapPointAtLatitude(vehicle.coordinate.latitude)
        guard metersPerPoint > 0 else { return nil }
        let tolerance = toleranceMeters / metersPerPoint
        let first = min(max(0, fromSegment), points.count - 2)
        let windowEnd = cumulative[first] + windowMeters / metersPerPoint
        func project(_ index: Int) -> (along: Double, distance: Double) {
            let a = points[index]
            let b = points[index + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? min(1, max(0, ((vehicle.x - a.x) * dx + (vehicle.y - a.y) * dy) / lengthSquared))
                : 0
            let distance = hypot(a.x + dx * t - vehicle.x, a.y + dy * t - vehicle.y)
            return (cumulative[index] + (cumulative[index + 1] - cumulative[index]) * t, distance)
        }
        var best: (segment: Int, along: Double, distance: Double)?
        var index = first
        while index < points.count - 1, cumulative[index] <= windowEnd {
            let hit = project(index)
            if hit.distance <= tolerance, hit.distance < (best?.distance ?? .infinity) {
                best = (index, hit.along, hit.distance)
            }
            index += 1
        }
        if let best {
            return (best.segment, best.along, best.distance * metersPerPoint)
        }
        // The car is past the window: the map was reopened after a long drive, or GPS dropped
        // out. Pick up the first stretch ahead that the car is on, and refine from there.
        // While already following, a loose miss stays a miss — scanning here is what made the
        // line leap to a later part of the route and vanish in between.
        guard recover else {
            guard course >= 0 else { return nil }
            let snug = attachMeters / metersPerPoint
            while index < points.count - 1 {
                let bearing = PlannedRouteProgress.bearing(points[index].coordinate, points[index + 1].coordinate)
                if bearing >= 0,
                   PlannedRouteProgress.angleDelta(course, bearing) < PlannedRouteProgress.missedTurnDegrees,
                   project(index).distance <= snug
                {
                    return advance(vehicle: vehicle, points: points, cumulative: cumulative, fromSegment: index)
                }
                index += 1
            }
            return nil
        }
        while index < points.count - 1 {
            if project(index).distance <= tolerance {
                return advance(
                    vehicle: vehicle,
                    points: points,
                    cumulative: cumulative,
                    fromSegment: index,
                    recover: true
                )
            }
            index += 1
        }
        return nil
    }
}

/// White edge under the traveled trail. Its own type so it is never restyled as the trail.
final class TrailCasingPolyline: MKPolyline {}

enum LiveFollowOverlayRole: Equatable {
    case traveled
    case casing
    case planned

    static func of(_ overlay: MKOverlay) -> LiveFollowOverlayRole {
        if overlay is PlannedRoutePolyline { return .planned }
        if overlay is TrailCasingPolyline { return .casing }
        return .traveled
    }
}

/// Forwards bounds changes so live-follow can stop writing the camera while the
/// window rotates. A camera write in that window cancels the orientation change.
private final class RotationPassthroughMapView: MKMapView {
    var onBoundsChange: ((CGSize) -> Void)?
    /// Upright fold: the legal mark belongs in the pane corner, not above the tab-bar inset.
    var pinAttributionToBottomCorner = false
    /// Follow point sits on this map view's midpoint. A window camera inset
    /// (the other pane, or the side tab) must not slide it left.
    var centersOnScreenMidpoint = false
    private var isApplyingSpeedLimitInset = false

    override var safeAreaInsets: UIEdgeInsets {
        guard centersOnScreenMidpoint else { return super.safeAreaInsets }
        var insets = super.safeAreaInsets
        insets.left = 0
        insets.right = 0
        return insets
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onBoundsChange?(bounds.size)
        guard !isApplyingSpeedLimitInset else { return }
        isApplyingSpeedLimitInset = true
        if !centersOnScreenMidpoint {
            pullSpeedLimitOffCamera()
        }
        pinLegalMarkToBottomCorner()
        if centersOnScreenMidpoint {
            keepFollowPointOnScreenMidpoint()
        }
        isApplyingSpeedLimitInset = false
    }

    /// Equal side margins. A wider trailing inset (the camera hole) otherwise
    /// parks the followed route left of the screen midpoint.
    private func keepFollowPointOnScreenMidpoint() {
        insetsLayoutMarginsFromSafeArea = false
        var margins = directionalLayoutMargins
        guard margins.leading != 0 || margins.trailing != 0 else { return }
        margins.leading = 0
        margins.trailing = 0
        directionalLayoutMargins = margins
    }

    /// The fold pane does not include the tab bar. Cancel that inset so "Maps" sits in the corner.
    private func pinLegalMarkToBottomCorner() {
        guard pinAttributionToBottomCorner else { return }
        insetsLayoutMarginsFromSafeArea = false
        var margins = directionalLayoutMargins
        let leading: CGFloat = 8
        let bottom: CGFloat = 6
        if abs(margins.leading - leading) > 0.5
            || abs(margins.bottom - bottom) > 0.5
            || margins.top > 0.5
        {
            margins.top = 0
            margins.leading = leading
            margins.bottom = bottom
            directionalLayoutMargins = margins
        }
        guard let label = attributionLabel(in: self), label.bounds.height > 1 else { return }
        let x: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? bounds.width - label.bounds.width - leading
            : leading
        let y = bounds.height - label.bounds.height - bottom
        guard abs(label.frame.minX - x) > 1 || abs(label.frame.minY - y) > 1 else { return }
        label.frame.origin = CGPoint(x: x, y: y)
    }

    private func attributionLabel(in view: UIView) -> UIView? {
        if NSStringFromClass(type(of: view)).contains("Attribution") { return view }
        for child in view.subviews {
            if let found = attributionLabel(in: child) { return found }
        }
        return nil
    }

    /// MapKit pins the speed-limit chip to the trailing corner. On a landscape
    /// fold that corner is the camera housing, so the chip slides left of it.
    private func pullSpeedLimitOffCamera() {
        guard let window else { return }
        let safe = window.safeAreaInsets
        let cameraOnTrailing = safe.right >= safe.left && safe.right > 20
        let cameraOnLeading = safe.left > safe.right && safe.left > 20
        guard cameraOnTrailing || cameraOnLeading else { return }
        var margins = directionalLayoutMargins
        if cameraOnTrailing {
            let next = safe.right + 12
            guard margins.trailing < next - 0.5 else { return }
            margins.trailing = next
        } else {
            let next = safe.left + 12
            guard margins.leading < next - 0.5 else { return }
            margins.leading = next
        }
        directionalLayoutMargins = margins
    }
}
/// MapKit host for live follow — display-link camera, GPS history + growing tail tip, pins + puck.
/// Route geometry is pulled by the coordinator from the session on display ticks
/// (see `syncRouteIfNeeded`), not passed through SwiftUI: a 1 Hz breadcrumb append
/// used to trigger a body re-render + `updateUIView` + history-overlay swap every
/// GPS fix, which dropped frames once a second at speed.
struct LiveFollowMapKitView: UIViewRepresentable {
    var pinsAttributionToBottomCorner: Bool = false
    var centersOnScreenMidpoint: Bool = false
    var session: LiveFollowSession
    var isFollowing: Bool
    var isPaused: Bool
    /// Card frame, written outside SwiftUI. Read only when overview is tapped.
    var hudAnchor: RecordingCardAnchorBox
    /// Bumped when the user asks to fit start + traveled path + puck (north-up 2D).
    var overviewRequestToken: Int
    /// Bumped when the user asks to re-lock follow (animated, same ease as overview).
    var recenterRequestToken: Int
    var pins: [LiveFollowMapPin]
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var puckRevealed: Bool
    /// 0…1 — MapKit puck view alpha (handoff crossfade with SwiftUI hero).
    var puckAlpha: CGFloat
    /// Bumped when puck alpha should animate (open/close handoff).
    var puckFadeToken: Int
    var isMoving: Bool
    var onUserBreakFollow: () -> Void
    /// Once MapKit has laid out, reports the puck circle center in map-view coordinates.
    var onPuckCircleScreenPoint: ((CGPoint) -> Void)?
    var routeStrokeColor: UIColor
    var puckPlateColor: UIColor
    var puckChevronColors: [UIColor]
    var themeSignature: String
    /// Trips stays mounted under the other tabs. MapKit keeps compositing the puck
    /// and the route over the next tab unless drawing stops while this is false.
    var isSceneVisible: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onUserBreakFollow: onUserBreakFollow)
    }

    private func applyInteractionLock(on map: MKMapView, paused: Bool) {
        map.isScrollEnabled = !paused
        map.isZoomEnabled = !paused
        map.isRotateEnabled = !paused
        map.isPitchEnabled = !paused
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = RotationPassthroughMapView(frame: .zero)
        map.onBoundsChange = { [weak coordinator = context.coordinator] size in
            coordinator?.noteMapBounds(size)
        }
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = false
        applyInteractionLock(on: map, paused: isPaused)
        map.clipsToBounds = true
        map.layer.masksToBounds = true
        map.pointOfInterestFilter = .excludingAll
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        }
        map.pinAttributionToBottomCorner = pinsAttributionToBottomCorner
        map.centersOnScreenMidpoint = centersOnScreenMidpoint
        context.coordinator.mapView = map
        context.coordinator.hudAnchor = hudAnchor
        context.coordinator.bindSession()
        context.coordinator.installGestureBreak(on: map)
        context.coordinator.syncRouteIfNeeded(on: map)
        context.coordinator.syncPlannedRouteIfNeeded(on: map)
        if let pose = session.pose {
            context.coordinator.applyCamera(pose, on: map)
        }
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.setSceneVisible(isSceneVisible, on: mapView)
        guard isSceneVisible else { return }
        if let mapView = mapView as? RotationPassthroughMapView {
            mapView.pinAttributionToBottomCorner = pinsAttributionToBottomCorner
            mapView.centersOnScreenMidpoint = centersOnScreenMidpoint
        }
        let shouldRecenter = context.coordinator.lastRecenterRequestToken != recenterRequestToken
            && recenterRequestToken > 0
        if shouldRecenter {
            context.coordinator.lastRecenterRequestToken = recenterRequestToken
            // Hold follow writes *before* `isFollowing` flips, or the next display
            // tick would snap the camera and kill the ease.
            context.coordinator.beginCameraEase()
        }
        context.coordinator.session = session
        context.coordinator.hudAnchor = hudAnchor
        context.coordinator.isFollowing = isFollowing
        let pauseChanged = context.coordinator.isPaused != isPaused
        context.coordinator.isPaused = isPaused
        context.coordinator.onUserBreakFollow = onUserBreakFollow
        context.coordinator.onPuckCircleScreenPoint = onPuckCircleScreenPoint
        context.coordinator.desiredPuckAlpha = puckAlpha
        let themeChanged = context.coordinator.themeSignature != themeSignature
        context.coordinator.routeStrokeColor = routeStrokeColor
        context.coordinator.puckPlateColor = puckPlateColor
        context.coordinator.puckChevronColors = puckChevronColors
        context.coordinator.themeSignature = themeSignature
        context.coordinator.bindSession()
        if themeChanged {
            context.coordinator.refreshRouteStroke(on: mapView)
        }

        if #available(iOS 16.0, *) {
            if !(mapView.preferredConfiguration is MKStandardMapConfiguration) {
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            }
        }

        context.coordinator.syncRouteIfNeeded(on: mapView)
        context.coordinator.syncPlannedRouteIfNeeded(on: mapView)
        if pauseChanged {
            applyInteractionLock(on: mapView, paused: isPaused)
            context.coordinator.refreshTipForPauseChange(on: mapView)
        }
        context.coordinator.syncPins(pins, on: mapView)
        context.coordinator.syncPuck(
            coordinate: session.vehicleCoordinate,
            revealed: puckRevealed,
            photo: vehiclePhoto,
            systemImage: vehicleSystemImage,
            isMoving: isMoving,
            updateCoordinate: false,
            on: mapView
        )
        let shouldAnimatePuck = context.coordinator.lastPuckFadeToken != puckFadeToken
        if shouldAnimatePuck {
            context.coordinator.lastPuckFadeToken = puckFadeToken
            context.coordinator.applyPuckAlpha(puckAlpha, animated: true, on: mapView)
        } else if abs(context.coordinator.desiredPuckAlpha - puckAlpha) > 0.001 {
            context.coordinator.applyPuckAlpha(puckAlpha, animated: false, on: mapView)
        } else {
            context.coordinator.desiredPuckAlpha = puckAlpha
        }
        if context.coordinator.lastOverviewRequestToken != overviewRequestToken {
            context.coordinator.lastOverviewRequestToken = overviewRequestToken
            if overviewRequestToken > 0 {
                context.coordinator.applyOverviewCamera(on: mapView)
            }
        }
        if shouldRecenter {
            context.coordinator.applyRecenterCamera(on: mapView)
        }
        context.coordinator.reportPuckCircleScreenPointIfPossible(on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var session: LiveFollowSession
        var isFollowing = true
        var isPaused = false
        var onUserBreakFollow: () -> Void
        var onPuckCircleScreenPoint: ((CGPoint) -> Void)?
        var desiredPuckAlpha: CGFloat = 1
        var lastPuckFadeToken: Int = 0
        var lastOverviewRequestToken: Int = 0
        var lastRecenterRequestToken: Int = 0
        var routeStrokeColor: UIColor = LiveFollowRouteStrokeStyle.solidColor(for: .sky, scheme: .light)
        var puckPlateColor: UIColor = UIColor(ShellPalette.sky.tintColor(for: .light))
        var puckChevronColors: [UIColor] = [
            UIColor(ShellPalette.sky.glowColor(for: .light)),
            UIColor(ShellPalette.sky.tintColor(for: .light)),
            UIColor(ShellPalette.sky.chromeColor(for: .light))
        ]
        var themeSignature = "sky-l"
        weak var mapView: MKMapView?
        var hudAnchor: RecordingCardAnchorBox?
        private var isApplyingCamera = false
        private var pinAnnotations: [String: LiveFollowPinAnnotation] = [:]
        private var puckAnnotation: LiveFollowPuckAnnotation?
        private var gestureRecognizersInstalled = false
        private var lastReportedPuckPoint: CGPoint?
        private var lastTipVehicle: CLLocationCoordinate2D?
        private var lastTipWriteAt: CFTimeInterval = 0
        private var tipOverlay: MKPolyline?
        private var tipCasing: TrailCasingPolyline?
        private var lastCommittedPieces: [[CLLocationCoordinate2D]] = []
        private var lastRouteVersion = Int.min
        private var plannedChunks: [Int: PlannedRoutePolyline] = [:]
        private var plannedLead: PlannedRoutePolyline?
        private var plannedDistanceMeters: CLLocationDistance = 0
        private var lastPlannedRouteVersion = Int.min
        private var plannedPoints: [MKMapPoint] = []
        private var plannedCumulative: [Double] = []
        private var plannedSegment = 0
        private var plannedAlong: Double = 0
        private var plannedFirstFixed = 0
        private var lastPlannedLeadAt: CFTimeInterval = 0
        private var lastPlannedLeadVehicle: MKMapPoint?
        /// Last car position the lead was considered for, whether or not the line held the puck.
        private var lastPlannedSample: MKMapPoint?
        /// Uncommitted remainder of the growing run — rendered in the tip overlay, so a
        /// new breadcrumb never swaps a history polyline (that 1 Hz remove+add next to
        /// the puck is what read as the route being "glued on in pieces").
        private var tailPoints: [CLLocationCoordinate2D] = []
        /// Pose / follow-camera writes skip while a owned camera ease is running.
        private var cameraEaseUntil: CFTimeInterval = 0
        private var cameraEase: CameraEase?
        private let easeClock = DisplayLinkClock()
        /// Device rotation swaps the map bounds. Writing `camera` in that window
        /// cancels the orientation change and the Duo stays landscape.
        private var lastMapBounds: CGSize = .zero
        private var suppressCameraUntil: CFTimeInterval = 0
        /// Last follow pose actually written to `map.camera`. Cleared whenever something
        /// else may have moved the camera, so the next follow tick is never skipped.
        private var lastFollowCameraPose: LiveFollowCamera.Pose?
        /// Another tab is selected. Pose ticks must not put the puck or the route back.
        private var drawingSuspended = false

        private var cameraWritesPaused: Bool {
            CACurrentMediaTime() < suppressCameraUntil
        }

        func noteMapBounds(_ size: CGSize) {
            let previous = lastMapBounds
            lastMapBounds = size
            guard previous != .zero else { return }
            let jumped = abs(size.width - previous.width) > 48
                || abs(size.height - previous.height) > 48
            if jumped {
                suppressCameraUntil = CACurrentMediaTime() + 0.75
                lastFollowCameraPose = nil
            }
        }

        /// Ease-in-out camera flight. `setCamera(animated:)` jumps heading in the model
        /// and then starts the pan a beat later — that's the "appears from nowhere" hitch.
        private static let cameraEaseDuration: CFTimeInterval = 0.58

        private struct CameraEase {
            var fromCenter: MKMapPoint
            var fromDistance: CLLocationDistance
            var fromPitch: Double
            var fromHeading: CLLocationDirection
            var toCenter: MKMapPoint
            var toDistance: CLLocationDistance
            var toPitch: Double
            var toHeading: CLLocationDirection
            var startedAt: CFTimeInterval
            var retargetFollow: Bool
            /// Overview only. Recenter keeps a linear distance blend.
            var logarithmicDistance: Bool
            var duration: CFTimeInterval
        }

        /// History is cut into fixed-size polylines. Everything but the growing tail
        /// chunk is immutable, so a breadcrumb only ever re-uploads ≤ `historyChunkPoints`
        /// vertices. Rebuilding the whole route each second stalls the main thread once
        /// a fast drive has accumulated thousands of points.
        private struct HistoryChunkKey: Hashable {
            let piece: Int
            let chunk: Int
        }

        private static let historyChunkPoints = 240
        private var historyChunks: [HistoryChunkKey: MKPolyline] = [:]
        private var historyCasings: [HistoryChunkKey: TrailCasingPolyline] = [:]
        private var historyChunkCounts: [HistoryChunkKey: Int] = [:]

        /// Hard ceiling of 10 Hz on tip geometry swaps. The puck itself still moves every
        /// frame, so the worst case is ~3 m of tail lag at motorway speed — hidden under the
        /// puck artwork, and far cheaper than churning the overlay set.
        private static let tipRefreshInterval: CFTimeInterval = 0.10
        private static let tipRefreshMeters: CLLocationDistance = 0.8

        /// MapKit fades a newly added overlay in over roughly a quarter second. Dropping the
        /// stroke it replaces in the same pass leaves the trail half transparent for that
        /// fade — invisible under the puck up close, a pale flash along the whole trail when
        /// zoomed out. Replaced trail overlays stay under their successor this long.
        private static let trailRetireDelay: CFTimeInterval = 0.45
        private var retiredTrail: [(overlay: MKOverlay, at: CFTimeInterval)] = []
        private var retireFlushScheduled = false

        init(
            session: LiveFollowSession,
            onUserBreakFollow: @escaping () -> Void
        ) {
            self.session = session
            self.onUserBreakFollow = onUserBreakFollow
            super.init()
            easeClock.onTick = { [weak self] _ in
                self?.tickCameraEase()
            }
        }

        @objc private func userGesture(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard !isApplyingCamera else { return }
            // Open hero still writes the follow camera; a pan in that window would
            // break follow and leave the curved flight chasing a sliding map.
            guard session.openSettled else { return }
            cancelCameraEase()
            breakFollow()
            onUserBreakFollow()
        }

        /// Stop follow immediately — don't wait for SwiftUI `updateUIView`.
        private func breakFollow() {
            session.isFollowing = false
            isFollowing = false
            lastFollowCameraPose = nil
        }

        private var isFollowLocked: Bool {
            session.isFollowing && isFollowing
        }

        func bindSession() {
            session.onPoseWrite = { [weak self] pose, vehicle in
                guard let self, !self.drawingSuspended, let map = self.mapView else { return }
                let following = self.isFollowLocked

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if following, CACurrentMediaTime() >= self.cameraEaseUntil, !self.cameraWritesPaused {
                    // Sub-pixel pose: skip the camera assignment. MapKit re-renders the
                    // whole scene on every write, including while stopped at a light.
                    if self.lastFollowCameraPose?.isVisuallySame(as: pose) != true {
                        self.applyCamera(pose, on: map, withinTransaction: true)
                        // A bounds jump during the write clears the cache and pauses
                        // follow. Don't store a pose the map may no longer be showing.
                        if !self.cameraWritesPaused {
                            self.lastFollowCameraPose = pose
                        }
                    }
                }
                if let vehicle, let puck = self.puckAnnotation {
                    // `coordinate` is KVO-observable; an equal assignment still relayouts the puck.
                    if abs(puck.coordinate.latitude - vehicle.latitude) > 1e-9
                        || abs(puck.coordinate.longitude - vehicle.longitude) > 1e-9
                    {
                        puck.coordinate = vehicle
                    }
                    puck.headingDegrees = self.session.vehicleHeadingDegrees
                }
                if CACurrentMediaTime() >= self.cameraEaseUntil {
                    self.applyPuckHeading(
                        self.session.vehicleHeadingDegrees,
                        mapHeading: following ? pose.headingDegrees : nil,
                        on: map,
                        animated: false
                    )
                }
                // Breadcrumbs land here, inside the camera transaction — never through
                // a SwiftUI body pass (which cost a re-render + updateUIView per fix).
                self.syncRouteIfNeeded(on: map)
                self.syncPlannedRouteIfNeeded(on: map)
                self.updatePlannedAhead(vehicle: vehicle, on: map)
                self.updateRouteTip(vehicle: vehicle, on: map)
                CATransaction.commit()
            }
        }

        func installGestureBreak(on map: MKMapView) {
            guard !gestureRecognizersInstalled else { return }
            gestureRecognizersInstalled = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 2
            map.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            pinch.delegate = self
            map.addGestureRecognizer(pinch)
            let rotate = UIRotationGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            rotate.delegate = self
            map.addGestureRecognizer(rotate)
        }

        func applyCamera(
            _ pose: LiveFollowCamera.Pose,
            on map: MKMapView,
            preserveCenter: Bool = false,
            withinTransaction: Bool = false
        ) {
            let center = preserveCenter ? map.camera.centerCoordinate : pose.center
            let camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: pose.distanceMeters,
                pitch: pose.pitchDegrees,
                heading: preserveCenter ? map.camera.heading : pose.headingDegrees
            )
            isApplyingCamera = true
            if !withinTransaction {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
            }
            map.camera = camera
            if !withinTransaction {
                CATransaction.commit()
            }
            isApplyingCamera = false
            // Follow-path caller stores the pose after this returns. Every other caller
            // (bootstrap, ease, reduce-motion snap) leaves it nil so follow rewrites.
            lastFollowCameraPose = nil
        }

        /// Drop the puck and the route while another tab is selected. The trips
        /// page stays in the tab controller, and MapKit otherwise keeps drawing both
        /// on top of the tab that just appeared. Coming back rebuilds from the session.
        func setSceneVisible(_ visible: Bool, on map: MKMapView) {
            if !visible {
                map.isHidden = true
                guard !drawingSuspended else { return }
                drawingSuspended = true
                map.removeOverlays(map.overlays)
                retiredTrail.removeAll()
                tipOverlay = nil
                tipCasing = nil
                plannedChunks.removeAll()
                plannedLead = nil
                lastPlannedRouteVersion = .min
                resetPlannedAhead(points: [])
                historyChunks.removeAll()
                historyCasings.removeAll()
                historyChunkCounts.removeAll()
                tailPoints = []
                lastCommittedPieces = []
                lastRouteVersion = .min
                lastTipVehicle = nil
                lastTipWriteAt = 0
                if let puckAnnotation {
                    map.removeAnnotation(puckAnnotation)
                    self.puckAnnotation = nil
                }
                for annotation in pinAnnotations.values {
                    map.removeAnnotation(annotation)
                }
                pinAnnotations.removeAll()
                return
            }
            let resume = drawingSuspended
            drawingSuspended = false
            map.isHidden = false
            if resume {
                syncRouteIfNeeded(on: map)
                syncPlannedRouteIfNeeded(on: map)
            }
        }

        /// Pulls the live route straight from the session when its version stamp moved.
        func syncRouteIfNeeded(on map: MKMapView) {
            guard !drawingSuspended else { return }
            let version = session.routeVersion
            guard version != lastRouteVersion else { return }
            lastRouteVersion = version
            syncRoute(session.routeSegments, on: map)
        }

        /// Planned route at the bottom of `.aboveRoads`, so the traveled trail and its tip
        /// always draw over it. Fixed chunks are rebuilt only for a new route or a reroute.
        func syncPlannedRouteIfNeeded(on map: MKMapView) {
            guard !drawingSuspended else { return }
            let version = session.plannedRouteVersion
            guard version != lastPlannedRouteVersion else { return }
            lastPlannedRouteVersion = version
            let previous: [MKOverlay] = plannedOverlays()
            plannedChunks.removeAll()
            plannedLead = nil
            let coordinates = session.plannedRouteCoordinates
            if coordinates.count >= 2 {
                resetPlannedAhead(points: coordinates.map { MKMapPoint($0) })
                var vehicle = session.vehicleCoordinate
                if let car = vehicle, !advancePlannedCut(to: MKMapPoint(car), recover: true) {
                    vehicle = nil
                } else if let car = vehicle, !leadHoldsPuck(MKMapPoint(car)) {
                    vehicle = nil
                }
                let metersPerPoint = MKMetersPerMapPointAtLatitude(coordinates[0].latitude)
                plannedFirstFixed = LiveFollowPlannedAhead.firstFixedChunk(
                    along: plannedAlong,
                    cumulative: plannedCumulative,
                    metersPerPoint: metersPerPoint
                )
                let count = LiveFollowPlannedAhead.chunkCount(pointCount: plannedPoints.count)
                for index in plannedFirstFixed..<max(plannedFirstFixed, count) {
                    insertPlannedChunk(index, on: map)
                }
                replacePlannedLead(vehicle: vehicle.map { MKMapPoint($0) }, on: map)
            } else {
                resetPlannedAhead(points: [])
            }
            if !previous.isEmpty {
                map.removeOverlays(previous)
            }
        }

        private func resetPlannedAhead(points: [MKMapPoint]) {
            plannedPoints = points
            plannedCumulative = LiveFollowPlannedAhead.cumulative(points)
            plannedSegment = 0
            plannedAlong = 0
            plannedFirstFixed = 0
            plannedDistanceMeters = 0
            lastPlannedLeadAt = 0
            lastPlannedLeadVehicle = nil
            lastPlannedSample = nil
        }

        private func plannedOverlays() -> [MKOverlay] {
            var overlays: [MKOverlay] = Array(plannedChunks.values)
            if let plannedLead {
                overlays.append(plannedLead)
            }
            return overlays
        }

        /// Moves the cut forward to the car. False when the car is off the line.
        /// `recover` is only for a route that was just loaded, with the cut back at the start.
        @discardableResult
        private func advancePlannedCut(to vehicle: MKMapPoint, recover: Bool) -> Bool {
            guard let cut = LiveFollowPlannedAhead.advance(
                vehicle: vehicle,
                points: plannedPoints,
                cumulative: plannedCumulative,
                fromSegment: plannedSegment,
                recover: recover,
                course: session.vehicleHeadingDegrees
            ) else { return false }
            plannedDistanceMeters = cut.distanceMeters
            if cut.along > plannedAlong {
                plannedSegment = cut.segment
                plannedAlong = cut.along
            }
            return true
        }

        private func leadHoldsPuck(_ vehicle: MKMapPoint) -> Bool {
            let index = min(max(0, plannedSegment), max(0, plannedPoints.count - 2))
            let bearing = plannedPoints.count >= 2
                ? PlannedRouteProgress.bearing(
                    plannedPoints[index].coordinate,
                    plannedPoints[index + 1].coordinate
                )
                : -1
            return LiveFollowPlannedAhead.attachesLead(
                distanceMeters: plannedDistanceMeters,
                course: session.vehicleHeadingDegrees,
                routeBearing: bearing
            )
        }

        private func insertPlannedChunk(_ index: Int, on map: MKMapView) {
            let chunk = Array(LiveFollowPlannedAhead.chunk(index, of: plannedPoints))
            guard chunk.count >= 2 else { return }
            let line = PlannedRoutePolyline(points: chunk, count: chunk.count)
            plannedChunks[index] = line
            map.insertOverlay(line, at: 0, level: .aboveRoads)
        }

        /// Follows the car on the tip's 10 Hz gate: drops fixed chunks the car has passed and
        /// swaps the short lead line. Fixed chunks are never re-uploaded while driving.
        private func updatePlannedAhead(vehicle: CLLocationCoordinate2D?, on map: MKMapView) {
            guard !plannedPoints.isEmpty, let vehicle, !isPaused else { return }
            let now = CACurrentMediaTime()
            guard now - lastPlannedLeadAt >= Self.tipRefreshInterval else { return }
            let point = MKMapPoint(vehicle)
            let metersPerPoint = MKMetersPerMapPointAtLatitude(vehicle.latitude)
            if let last = lastPlannedSample,
               hypot(point.x - last.x, point.y - last.y) * metersPerPoint < Self.tipRefreshMeters
            {
                return
            }
            lastPlannedLeadAt = now
            lastPlannedSample = point
            let onRoute = advancePlannedCut(to: point, recover: false)
            let firstFixed = LiveFollowPlannedAhead.firstFixedChunk(
                along: plannedAlong,
                cumulative: plannedCumulative,
                metersPerPoint: metersPerPoint
            )
            if firstFixed > plannedFirstFixed {
                let passed = (plannedFirstFixed..<firstFixed).compactMap { plannedChunks.removeValue(forKey: $0) }
                plannedFirstFixed = firstFixed
                if !passed.isEmpty {
                    map.removeOverlays(passed)
                }
            }
            let holdsPuck = onRoute && leadHoldsPuck(point)
            if holdsPuck {
                replacePlannedLead(vehicle: point, on: map)
            } else if onRoute || lastPlannedLeadVehicle != nil {
                // Left the road: the line stays on the route. It does not stretch back to the car.
                replacePlannedLead(vehicle: nil, on: map)
            }
        }

        private func replacePlannedLead(vehicle: MKMapPoint?, on map: MKMapView) {
            let endVertex = plannedFirstFixed < LiveFollowPlannedAhead.chunkCount(pointCount: plannedPoints.count)
                ? LiveFollowPlannedAhead.chunkStartVertex(plannedFirstFixed)
                : plannedPoints.count - 1
            let latitude = (vehicle ?? plannedPoints.first)?.coordinate.latitude ?? 0
            let points = LiveFollowPlannedAhead.lead(
                vehicle: vehicle,
                segment: plannedSegment,
                along: plannedAlong,
                points: plannedPoints,
                cumulative: plannedCumulative,
                endVertex: endVertex,
                metersPerPoint: MKMetersPerMapPointAtLatitude(latitude)
            )
            lastPlannedLeadVehicle = vehicle
            let previous = plannedLead
            if points.count >= 2 {
                let next = PlannedRoutePolyline(points: points, count: points.count)
                plannedLead = next
                map.insertOverlay(next, at: 0, level: .aboveRoads)
            } else {
                plannedLead = nil
            }
            if let previous {
                map.removeOverlay(previous)
            }
        }

        func syncRoute(_ pieces: [[CLLocationCoordinate2D]], on map: MKMapView) {
            let unchanged = Self.samePieces(pieces, lastCommittedPieces)
            lastCommittedPieces = pieces
            if !unchanged {
                replaceHistoryOverlay(pieces, on: map)
                // New breadcrumb ⇒ the tip geometry moved; refresh past the throttle.
                lastTipWriteAt = 0
                lastTipVehicle = nil
            }
            updateRouteTip(vehicle: session.vehicleCoordinate, on: map)
        }

        /// Pause flips must redraw the tip immediately (frozen tail, no vehicle chord).
        func refreshTipForPauseChange(on map: MKMapView) {
            lastTipWriteAt = 0
            lastTipVehicle = nil
            updateRouteTip(vehicle: session.vehicleCoordinate, on: map)
        }

        private func updateRouteTip(vehicle: CLLocationCoordinate2D?, on map: MKMapView) {
            if isPaused {
                lastTipVehicle = nil
                // Keep the recorded-but-uncommitted tail on screen; only the live
                // vehicle chord is dropped while frozen.
                replaceTipOverlay(tailPoints.count >= 2 ? tailPoints : nil, on: map)
                return
            }
            // Both gates must pass. Swapping a MapKit overlay is a render-tree mutation,
            // and this runs inside the 60 Hz camera transaction — letting distance alone
            // trigger it means ~34 swaps/s at motorway speed, which is what made the
            // picture judder harder the faster you drove.
            let now = CACurrentMediaTime()
            if now - lastTipWriteAt < Self.tipRefreshInterval {
                return
            }
            if let vehicle, let lastTipVehicle {
                let moved = CLLocation(latitude: lastTipVehicle.latitude, longitude: lastTipVehicle.longitude)
                    .distance(from: CLLocation(latitude: vehicle.latitude, longitude: vehicle.longitude))
                if moved < Self.tipRefreshMeters {
                    return
                }
            }
            lastTipVehicle = vehicle
            lastTipWriteAt = now
            let points = LiveFollowGrowingRoute.tailSegment(
                tail: tailPoints,
                vehicle: vehicle
            )
            replaceTipOverlay(points, on: map)
        }

        /// The old stroke stays under the replacement until its fade-in is over, so it never blinks.
        private func replaceTipOverlay(_ points: [CLLocationCoordinate2D]?, on map: MKMapView) {
            let previous = tipOverlay
            let previousCasing = tipCasing
            if let points, points.count >= 2 {
                let casing = TrailCasingPolyline(coordinates: points, count: points.count)
                tipCasing = casing
                addTrailCasing(casing, on: map)
                let next = MKPolyline(coordinates: points, count: points.count)
                tipOverlay = next
                map.addOverlay(next, level: .aboveRoads)
            } else {
                tipOverlay = nil
                tipCasing = nil
            }
            retireTrailOverlays([previous, previousCasing].compactMap { $0 }, on: map)
        }

        /// Under every traveled stroke, not on top of the stroke it replaces: a white edge
        /// fading in over the old trail reads as the trail flashing pale.
        private func addTrailCasing(_ casing: TrailCasingPolyline, on map: MKMapView) {
            if let lowestTrail = map.overlays(in: .aboveRoads).first(where: {
                LiveFollowOverlayRole.of($0) == .traveled
            }) {
                map.insertOverlay(casing, below: lowestTrail)
            } else {
                map.addOverlay(casing, level: .aboveRoads)
            }
        }

        private func retireTrailOverlays(_ overlays: [MKOverlay], on map: MKMapView) {
            let now = CACurrentMediaTime()
            flushRetiredTrail(on: map, now: now)
            guard !overlays.isEmpty else { return }
            retiredTrail.append(contentsOf: overlays.map { (overlay: $0, at: now) })
            scheduleRetiredTrailFlush()
        }

        private func flushRetiredTrail(on map: MKMapView, now: CFTimeInterval) {
            let expired = retiredTrail.prefix { now - $0.at >= Self.trailRetireDelay }
            guard !expired.isEmpty else { return }
            map.removeOverlays(expired.map { $0.overlay })
            retiredTrail.removeFirst(expired.count)
        }

        /// Pause and a stopped car stop the tip swaps, so expired strokes need their own pass.
        private func scheduleRetiredTrailFlush() {
            guard !retireFlushScheduled, let oldest = retiredTrail.first else { return }
            retireFlushScheduled = true
            let wait = max(0, oldest.at + Self.trailRetireDelay - CACurrentMediaTime()) + 0.02
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.retireFlushScheduled = false
                guard let map = self.mapView else { return }
                self.flushRetiredTrail(on: map, now: CACurrentMediaTime())
                self.scheduleRetiredTrailFlush()
            }
        }

        private func replaceHistoryOverlay(_ pieces: [[CLLocationCoordinate2D]], on map: MKMapView) {
            let drawable = LiveFollowGrowingRoute.historyPieces(from: pieces)
            let growingPiece = pieces.last(where: { !$0.isEmpty })
            // The growing run is the last drawable piece exactly when it can be drawn;
            // a fresh 1-point gap piece stays tip-only until it has two vertices.
            let growingIsDrawable = (growingPiece?.count ?? 0) >= 2
            var liveKeys = Set<HistoryChunkKey>()

            for (pieceIndex, coordinates) in drawable.enumerated() {
                // Only *complete* chunks of the growing run become history overlays;
                // its remainder rides in the tip so a breadcrumb never re-uploads here.
                let isGrowing = growingIsDrawable && pieceIndex == drawable.count - 1
                let lastIndex = coordinates.count - 1
                let committedEnd = isGrowing
                    ? (lastIndex / Self.historyChunkPoints) * Self.historyChunkPoints
                    : lastIndex
                var start = 0
                var chunkIndex = 0
                while start < committedEnd {
                    // Chunks share their boundary vertex so the stroke stays continuous.
                    let end = min(start + Self.historyChunkPoints, committedEnd)
                    let key = HistoryChunkKey(piece: pieceIndex, chunk: chunkIndex)
                    liveKeys.insert(key)

                    let count = end - start + 1
                    if historyChunkCounts[key] != count {
                        let slice = Array(coordinates[start...end])
                        let casing = TrailCasingPolyline(coordinates: slice, count: slice.count)
                        let line = MKPolyline(coordinates: slice, count: slice.count)
                        let previous = historyChunks[key]
                        let previousCasing = historyCasings[key]
                        historyCasings[key] = casing
                        historyChunks[key] = line
                        historyChunkCounts[key] = count
                        addTrailCasing(casing, on: map)
                        map.addOverlay(line, level: .aboveRoads)
                        retireTrailOverlays([previous, previousCasing].compactMap { $0 }, on: map)
                    }

                    start = end
                    chunkIndex += 1
                }
            }

            for (key, overlay) in historyChunks where !liveKeys.contains(key) {
                map.removeOverlay(overlay)
                if let casing = historyCasings[key] {
                    map.removeOverlay(casing)
                }
                historyChunks.removeValue(forKey: key)
                historyCasings.removeValue(forKey: key)
                historyChunkCounts.removeValue(forKey: key)
            }

            // Tail shares its first vertex with the last committed chunk.
            if let growingPiece, growingIsDrawable {
                let lastIndex = growingPiece.count - 1
                let committedEnd = (lastIndex / Self.historyChunkPoints) * Self.historyChunkPoints
                tailPoints = Array(growingPiece[committedEnd...])
            } else if let growingPiece {
                tailPoints = growingPiece
            } else {
                tailPoints = []
            }
        }

        func applyOverviewCamera(on map: MKMapView) {
            let pieces = LiveFollowGrowingRoute.historyPieces(from: lastCommittedPieces)
            let rect = LiveFollowGrowingRoute.overviewMapRect(
                historyPieces: pieces,
                vehicle: session.vehicleCoordinate ?? LiveFollowGrowingRoute.tipAnchor(from: lastCommittedPieces),
                destination: session.plannedRouteDestination
            )
            guard !rect.isNull else { return }
            let size = map.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            guard let fit = LiveFollowOverviewFit.target(
                routeRect: rect,
                mapSize: size,
                contentInsets: overviewContentInsets(on: map),
                visibleHeightPerDistance: pitch0VisibleHeightPerDistance(on: map)
            ) else { return }
            lastFollowCameraPose = nil
            breakFollow()
            onUserBreakFollow()
            let target = MKMapCamera(
                lookingAtCenter: fit.center,
                fromDistance: fit.distanceMeters,
                pitch: 0,
                heading: 0
            )
            startCameraEase(to: target, retargetFollow: false, logarithmicDistance: true, on: map)
        }

        /// Pitch 0 only. A read — the camera is not moved. Pitched follow uses the fallback.
        private func pitch0VisibleHeightPerDistance(on map: MKMapView) -> Double {
            let distance = map.camera.centerCoordinateDistance
            guard map.camera.pitch < 1, distance > 1 else {
                return LiveFollowOverviewFit.fallbackVisibleHeightPerDistance
            }
            let rect = map.visibleMapRect
            guard !rect.isNull, rect.size.height > 1 else {
                return LiveFollowOverviewFit.fallbackVisibleHeightPerDistance
            }
            let mid = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
            let meters = rect.size.height * MKMetersPerMapPointAtLatitude(mid.latitude)
            let ratio = meters / distance
            guard ratio > 0.05, ratio < 20 else {
                return LiveFollowOverviewFit.fallbackVisibleHeightPerDistance
            }
            return ratio
        }

        /// Top chips, the recording card, and a camera-hole side inset.
        /// A wide card clears the bottom band. A corner card (landscape cover) clears that side.
        private func overviewContentInsets(on map: MKMapView) -> UIEdgeInsets {
            let bounds = map.bounds
            var insets = UIEdgeInsets(
                top: max(64, map.safeAreaInsets.top + 44),
                left: 16,
                bottom: 20,
                right: 16
            )
            if map.safeAreaInsets.right >= 20 {
                insets.right = max(insets.right, map.safeAreaInsets.right + 8)
            } else if map.safeAreaInsets.left >= 20 {
                insets.left = max(insets.left, map.safeAreaInsets.left + 8)
            }

            let card = hudAnchor?.value.rect ?? .zero
            guard card.width > 1, card.height > 1 else {
                insets.bottom = max(insets.bottom, 220)
                return clampedOverviewInsets(insets, in: bounds)
            }
            let inMap = map.convert(card, from: map.window)
            let overlap = inMap.intersection(bounds.insetBy(dx: -4, dy: -4))
            guard overlap.width > 1, overlap.height > 1 else {
                insets.bottom = max(insets.bottom, 220)
                return clampedOverviewInsets(insets, in: bounds)
            }
            if overlap.width > bounds.width * 0.55 {
                insets.bottom = max(insets.bottom, bounds.maxY - overlap.minY + 12)
            } else if overlap.midX < bounds.midX {
                insets.left = max(insets.left, overlap.maxX - bounds.minX + 12)
            } else {
                insets.right = max(insets.right, bounds.maxX - overlap.minX + 12)
            }
            return clampedOverviewInsets(insets, in: bounds)
        }

        private func clampedOverviewInsets(_ insets: UIEdgeInsets, in bounds: CGRect) -> UIEdgeInsets {
            var insets = insets
            if bounds.height - insets.top - insets.bottom < 48 {
                insets.bottom = max(20, bounds.height - insets.top - 48)
            }
            if bounds.width - insets.left - insets.right < 48 {
                insets.left = 16
                insets.right = 16
            }
            return insets
        }

        func beginCameraEase() {
            cameraEaseUntil = CACurrentMediaTime() + Self.cameraEaseDuration
        }

        /// Fly back to heading follow from whatever the map currently shows.
        func applyRecenterCamera(on map: MKMapView) {
            lastFollowCameraPose = nil
            if let location = session.locationService?.lastLocation {
                session.camera.forceRecenter(location: location)
            } else {
                session.camera.snapDimensionMode()
            }
            guard let pose = session.pose else { return }
            let target = MKMapCamera(
                lookingAtCenter: pose.center,
                fromDistance: pose.distanceMeters,
                pitch: pose.pitchDegrees,
                heading: pose.headingDegrees
            )
            startCameraEase(to: target, retargetFollow: true, logarithmicDistance: false, on: map)
        }

        /// Snapshot the *visible* camera and interpolate toward `target` on the display
        /// link. Never `setCamera(animated:)` — MapKit jumps heading in the model and
        /// then starts the pan a frame later, which reads as a hitch from nowhere.
        ///
        /// `logarithmicDistance` is the overview pull-back only. Recenter stays linear
        /// over `cameraEaseDuration`.
        private func startCameraEase(
            to target: MKMapCamera,
            retargetFollow: Bool,
            logarithmicDistance: Bool,
            on map: MKMapView
        ) {
            if session.reduceMotion {
                cameraEase = nil
                easeClock.stop()
                cameraEaseUntil = 0
                applyCamera(
                    LiveFollowCamera.Pose(
                        center: target.centerCoordinate,
                        headingDegrees: target.heading,
                        distanceMeters: target.centerCoordinateDistance,
                        pitchDegrees: target.pitch
                    ),
                    on: map
                )
                if session.pose != nil {
                    applyPuckHeading(
                        session.vehicleHeadingDegrees,
                        mapHeading: target.heading,
                        on: map,
                        animated: false
                    )
                }
                return
            }
            let from = map.camera
            let duration = logarithmicDistance
                ? LiveFollowOverviewFit.overviewDuration(
                    fromDistance: from.centerCoordinateDistance,
                    toDistance: target.centerCoordinateDistance
                )
                : Self.cameraEaseDuration
            cameraEase = CameraEase(
                fromCenter: MKMapPoint(from.centerCoordinate),
                fromDistance: from.centerCoordinateDistance,
                fromPitch: from.pitch,
                fromHeading: from.heading,
                toCenter: MKMapPoint(target.centerCoordinate),
                toDistance: target.centerCoordinateDistance,
                toPitch: target.pitch,
                toHeading: target.heading,
                startedAt: CACurrentMediaTime(),
                retargetFollow: retargetFollow,
                logarithmicDistance: logarithmicDistance,
                duration: duration
            )
            cameraEaseUntil = CACurrentMediaTime() + duration
            easeClock.start()
            tickCameraEase()
        }

        private func cancelCameraEase() {
            cameraEase = nil
            cameraEaseUntil = 0
            easeClock.stop()
            lastFollowCameraPose = nil
        }

        private func tickCameraEase() {
            guard var ease = cameraEase, let map = mapView else {
                easeClock.stop()
                return
            }
            if ease.retargetFollow, let pose = session.pose {
                ease.toCenter = MKMapPoint(pose.center)
                ease.toDistance = pose.distanceMeters
                ease.toPitch = pose.pitchDegrees
                ease.toHeading = pose.headingDegrees
                cameraEase = ease
            }
            let elapsed = CACurrentMediaTime() - ease.startedAt
            let duration = max(ease.duration, 0.01)
            let linear = min(1, max(0, elapsed / duration))
            let t = Self.smootherstep(linear)
            let x = ease.fromCenter.x + (ease.toCenter.x - ease.fromCenter.x) * t
            let y = ease.fromCenter.y + (ease.toCenter.y - ease.fromCenter.y) * t
            let center = MKMapPoint(x: x, y: y).coordinate
            let distance = LiveFollowOverviewFit.easedDistance(
                from: ease.fromDistance,
                to: ease.toDistance,
                t: t,
                logarithmic: ease.logarithmicDistance
            )
            let pitch = ease.fromPitch + (ease.toPitch - ease.fromPitch) * t
            let heading = LiveFollowCamera.smoothedHeading(
                from: ease.fromHeading,
                toward: ease.toHeading,
                factor: t
            )
            let pose = LiveFollowCamera.Pose(
                center: center,
                headingDegrees: heading,
                distanceMeters: distance,
                pitchDegrees: pitch
            )
            applyCamera(pose, on: map)
            if session.pose != nil {
                applyPuckHeading(session.vehicleHeadingDegrees, mapHeading: heading, on: map, animated: false)
            }
            if linear >= 1 {
                cancelCameraEase()
            }
        }

        /// Zero derivative at both ends — no pop at start, no slam at finish.
        private static func smootherstep(_ t: Double) -> Double {
            let x = min(1, max(0, t))
            return x * x * x * (x * (x * 6 - 15) + 10)
        }

        /// Chevron + photo face travel. While following the camera already does that
        /// (rotation stays identity). After overview / pan, the map heading diverges
        /// and the artwork has to rotate around the photo-circle centre.
        func applyPuckHeading(
            _ travelHeading: CLLocationDirection,
            mapHeading: CLLocationDirection? = nil,
            on map: MKMapView,
            animated: Bool
        ) {
            guard let puckAnnotation, let view = map.view(for: puckAnnotation) as? LiveFollowPuckAnnotationView else {
                return
            }
            let mapDegrees: CLLocationDirection
            if cameraEase != nil {
                mapDegrees = mapHeading ?? map.camera.heading
            } else if session.isFollowing {
                // The follow camera eases behind the vehicle heading; rotate by the gap.
                mapDegrees = mapHeading ?? session.pose?.headingDegrees ?? travelHeading
            } else {
                mapDegrees = mapHeading ?? map.camera.heading
            }
            view.applyHeading(travelHeading, mapHeading: mapDegrees, animated: animated)
        }

        private static func samePieces(
            _ lhs: [[CLLocationCoordinate2D]],
            _ rhs: [[CLLocationCoordinate2D]]
        ) -> Bool {
            guard lhs.count == rhs.count else { return false }
            for (a, b) in zip(lhs, rhs) {
                guard a.count == b.count else { return false }
                if let al = a.last, let bl = b.last,
                   abs(al.latitude - bl.latitude) > 1e-9
                    || abs(al.longitude - bl.longitude) > 1e-9
                {
                    return false
                }
                if let af = a.first, let bf = b.first,
                   abs(af.latitude - bf.latitude) > 1e-9
                    || abs(af.longitude - bf.longitude) > 1e-9
                {
                    return false
                }
            }
            return true
        }

        func syncPins(_ pins: [LiveFollowMapPin], on map: MKMapView) {
            let nextIDs = Set(pins.map(\.id))
            for (id, annotation) in pinAnnotations where !nextIDs.contains(id) {
                map.removeAnnotation(annotation)
                pinAnnotations.removeValue(forKey: id)
            }
            for pin in pins {
                if let existing = pinAnnotations[pin.id] {
                    if existing.coordinate.latitude != pin.latitude
                        || existing.coordinate.longitude != pin.longitude
                    {
                        existing.coordinate = pin.coordinate
                    }
                    existing.kind = pin.kind
                } else {
                    let annotation = LiveFollowPinAnnotation(pin: pin)
                    pinAnnotations[pin.id] = annotation
                    map.addAnnotation(annotation)
                }
            }
        }

        func syncPuck(
            coordinate: CLLocationCoordinate2D?,
            revealed: Bool,
            photo: UIImage?,
            systemImage: String,
            isMoving: Bool,
            updateCoordinate: Bool = true,
            on map: MKMapView
        ) {
            guard revealed, let coordinate else {
                if let puckAnnotation {
                    map.removeAnnotation(puckAnnotation)
                    self.puckAnnotation = nil
                }
                return
            }
            if let puckAnnotation {
                if updateCoordinate {
                    puckAnnotation.coordinate = coordinate
                }
                puckAnnotation.vehiclePhoto = photo
                puckAnnotation.vehicleSystemImage = systemImage
                puckAnnotation.isMoving = isMoving
                if session.pose != nil {
                    puckAnnotation.headingDegrees = session.vehicleHeadingDegrees
                }
                if let view = map.view(for: puckAnnotation) as? LiveFollowPuckAnnotationView {
                    view.isHidden = false
                    view.apply(puckAnnotation)
                    view.applyTheme(plate: puckPlateColor, chevronColors: puckChevronColors)
                    applyPuckHeading(puckAnnotation.headingDegrees, on: map, animated: false)
                }
            } else {
                let annotation = LiveFollowPuckAnnotation(
                    coordinate: coordinate,
                    vehiclePhoto: photo,
                    vehicleSystemImage: systemImage,
                    isMoving: isMoving,
                    headingDegrees: session.pose != nil ? session.vehicleHeadingDegrees : 0
                )
                puckAnnotation = annotation
                map.addAnnotation(annotation)
            }
        }

        func applyPuckAlpha(_ alpha: CGFloat, animated: Bool, on map: MKMapView) {
            desiredPuckAlpha = alpha
            let apply = {
                if let puckAnnotation = self.puckAnnotation, let view = map.view(for: puckAnnotation) {
                    view.alpha = alpha
                    view.isHidden = false
                }
            }
            if animated {
                UIView.animate(
                    withDuration: TrailhoundMotion.liveFollowHandoffDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState]
                ) {
                    apply()
                }
            } else {
                apply()
            }
        }

        /// Projects the live vehicle into map-view space and reports the photo-circle center.
        func reportPuckCircleScreenPointIfPossible(on map: MKMapView) {
            guard let onPuckCircleScreenPoint else { return }
            guard map.bounds.width > 1, map.bounds.height > 1 else { return }
            guard let coordinate = session.vehicleCoordinate else { return }
            let projected = map.convert(coordinate, toPointTo: map)
            let circle = LiveFollowPresentation.puckCircleCenter(fromProjectedAnnotationPoint: projected)
            if let last = lastReportedPuckPoint,
               abs(last.x - circle.x) < 0.5,
               abs(last.y - circle.y) < 0.5
            {
                return
            }
            lastReportedPuckPoint = circle
            onPuckCircleScreenPoint(circle)
        }

        func refreshRouteStroke(on map: MKMapView) {
            for overlay in map.overlays {
                guard let renderer = map.renderer(for: overlay) as? MKOverlayPathRenderer else { continue }
                LiveFollowRouteStrokeStyle.apply(to: renderer, for: overlay, color: routeStrokeColor)
                renderer.setNeedsDisplay()
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if drawingSuspended {
                return MKOverlayRenderer(overlay: overlay)
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                LiveFollowRouteStrokeStyle.apply(to: renderer, for: overlay, color: routeStrokeColor)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let puck = annotation as? LiveFollowPuckAnnotation {
                let reuse = "live-follow-puck"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? LiveFollowPuckAnnotationView)
                    ?? LiveFollowPuckAnnotationView(annotation: puck, reuseIdentifier: reuse)
                view.apply(puck)
                view.applyTheme(plate: puckPlateColor, chevronColors: puckChevronColors)
                view.alpha = desiredPuckAlpha
                view.isHidden = false
                view.applyHeading(puck.headingDegrees, mapHeading: mapView.camera.heading, animated: false)
                return view
            }
            if let pin = annotation as? LiveFollowPinAnnotation {
                let reuse = "live-follow-pin-\(pin.kind.rawValue)"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? LiveFollowPinAnnotationView)
                    ?? LiveFollowPinAnnotationView(annotation: pin, reuseIdentifier: reuse)
                view.apply(pin)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            if drawingSuspended {
                for view in views {
                    view.alpha = 0
                    view.isHidden = true
                }
                return
            }
            for view in views where view is LiveFollowPuckAnnotationView {
                view.alpha = desiredPuckAlpha
                view.isHidden = false
            }
            if let puckAnnotation {
                applyPuckHeading(puckAnnotation.headingDegrees, on: mapView, animated: false)
            }
            reportPuckCircleScreenPointIfPossible(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard CACurrentMediaTime() >= cameraEaseUntil else { return }
            guard !session.isFollowing, let puckAnnotation else { return }
            applyPuckHeading(puckAnnotation.headingDegrees, on: mapView, animated: false)
        }
    }
}

extension LiveFollowMapKitView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Annotations

final class LiveFollowPuckAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var isMoving: Bool
    var headingDegrees: CLLocationDirection

    init(
        coordinate: CLLocationCoordinate2D,
        vehiclePhoto: UIImage?,
        vehicleSystemImage: String,
        isMoving: Bool,
        headingDegrees: CLLocationDirection = 0
    ) {
        self.coordinate = coordinate
        self.vehiclePhoto = vehiclePhoto
        self.vehicleSystemImage = vehicleSystemImage
        self.isMoving = isMoving
        self.headingDegrees = headingDegrees
    }
}

final class LiveFollowPinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var kind: LiveFollowMapPinKind

    init(pin: LiveFollowMapPin) {
        self.coordinate = pin.coordinate
        self.kind = pin.kind
    }
}

final class LiveFollowPuckAnnotationView: MKAnnotationView {
    private let circleSize: CGFloat = 56
    private let chevronSize = CGSize(width: 52, height: 38)
    private let chevronOverlap: CGFloat = 18
    private let photoBorder: CGFloat = 5
    private let photoGap: CGFloat = 3
    /// Opaque plate so the traveled path cannot show through the photo.
    private var plateColor = UIColor(ShellPalette.sky.tintColor(for: .light))
    private var lastChevronSignature: String = ""
    /// Last non-animated heading transform. Equal writes still open a CATransaction.
    private var lastAppliedRadians: CGFloat?

    /// Artwork rotates around the photo-circle centre so the trail still meets the puck.
    private let headingContent = UIView()
    private let badge = UIView()
    private let photoView = UIImageView()
    private let symbolView = UIImageView()
    private let chevron = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        clipsToBounds = false
        zPriority = .max
        displayPriority = .required
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        lastAppliedRadians = nil
    }

    private func setup() {
        let frameHeight = circleSize + chevronSize.height - chevronOverlap + 14
        let frameWidth = max(circleSize, chevronSize.width) + 24
        frame = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
        centerOffset = LiveFollowPresentation.puckAnnotationCenterOffset

        headingContent.clipsToBounds = false
        headingContent.isUserInteractionEnabled = false
        headingContent.bounds = CGRect(origin: .zero, size: CGSize(width: frameWidth, height: frameHeight))
        // Rotate around the photo-circle centre, not the view's geometric centre
        // (the chevron hangs below, so those two points are ~17 pt apart).
        headingContent.layer.anchorPoint = CGPoint(x: 0.5, y: circleSize / 2 / frameHeight)
        headingContent.center = CGPoint(x: frameWidth / 2, y: circleSize / 2)
        addSubview(headingContent)

        badge.isOpaque = true
        badge.backgroundColor = plateColor
        badge.layer.cornerRadius = circleSize / 2
        badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.borderWidth = photoBorder
        badge.clipsToBounds = true
        headingContent.addSubview(badge)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        badge.addSubview(photoView)

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = .white
        badge.addSubview(symbolView)

        chevron.contentMode = .scaleAspectFit
        chevron.image = Self.makeChevronImage(
            size: chevronSize,
            colors: [
                UIColor(ShellPalette.sky.glowColor(for: .light)),
                UIColor(ShellPalette.sky.tintColor(for: .light)),
                UIColor(ShellPalette.sky.chromeColor(for: .light))
            ]
        )
        chevron.layer.zPosition = 2
        headingContent.addSubview(chevron)

        let side = circleSize
        badge.frame = CGRect(x: (frameWidth - side) / 2, y: 0, width: side, height: side)
        let inset = photoBorder + photoGap
        photoView.frame = badge.bounds.insetBy(dx: inset, dy: inset)
        photoView.layer.cornerRadius = photoView.bounds.width / 2
        symbolView.frame = photoView.frame
        chevron.frame = CGRect(
            x: (frameWidth - chevronSize.width) / 2,
            y: side - chevronOverlap,
            width: chevronSize.width,
            height: chevronSize.height
        )
    }

    func applyTheme(plate: UIColor, chevronColors: [UIColor]) {
        plateColor = plate
        badge.backgroundColor = plate
        let signature = chevronColors.map { $0.description }.joined(separator: "|")
        guard signature != lastChevronSignature else { return }
        lastChevronSignature = signature
        chevron.image = Self.makeChevronImage(size: chevronSize, colors: chevronColors)
    }

    func apply(_ annotation: LiveFollowPuckAnnotation) {
        zPriority = .max
        displayPriority = .required
        isHidden = false
        lastAppliedRadians = nil
        if let photo = annotation.vehiclePhoto {
            photoView.image = photo
            photoView.isHidden = false
            symbolView.isHidden = true
        } else {
            photoView.isHidden = true
            symbolView.isHidden = false
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            symbolView.image = UIImage(systemName: annotation.vehicleSystemImage, withConfiguration: config)
        }
    }

    func applyHeading(
        _ travelHeading: CLLocationDirection,
        mapHeading: CLLocationDirection,
        animated: Bool
    ) {
        let radians = LiveFollowPresentation.puckRotationRadians(
            travelHeadingDegrees: travelHeading,
            mapHeadingDegrees: mapHeading
        )
        // Animated handoff always runs. Settled follow frames mostly repeat the same angle.
        if !animated, let lastAppliedRadians, abs(radians - lastAppliedRadians) < 0.0005 {
            return
        }
        lastAppliedRadians = radians
        let transform = CGAffineTransform(rotationAngle: radians)
        let apply = {
            CATransaction.begin()
            CATransaction.setDisableActions(!animated)
            self.headingContent.transform = transform
            CATransaction.commit()
        }
        if animated {
            UIView.animate(
                withDuration: 0.45,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                self.headingContent.transform = transform
            }
        } else {
            apply()
        }
    }

    /// Four-point chevron (V notch). Tests and drawing both use `points.last`.
    static func chevronOutlinePoints(size: CGSize) -> [CGPoint] {
        let w = size.width
        let h = size.height
        return [
            CGPoint(x: w * 0.50, y: h * 0.04),
            CGPoint(x: w * 0.97, y: h * 0.92),
            CGPoint(x: w * 0.50, y: h * 0.72),
            CGPoint(x: w * 0.03, y: h * 0.92)
        ]
    }

    private static func makeChevronImage(size: CGSize, colors: [UIColor]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let w = size.width
            let h = size.height
            let points = Self.chevronOutlinePoints(size: size)
            let radius = min(w, h) * 0.12
            let cg = CGMutablePath()
            guard let last = points.last else { return }
            let first = points[0]
            cg.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
            for index in points.indices {
                let current = points[index]
                let next = points[(index + 1) % points.count]
                cg.addArc(tangent1End: current, tangent2End: next, radius: radius)
            }
            cg.closeSubpath()
            let rounded = UIBezierPath(cgPath: cg)

            let fallback = [
                UIColor(ShellPalette.sky.glowColor(for: .light)),
                UIColor(ShellPalette.sky.tintColor(for: .light)),
                UIColor(ShellPalette.sky.chromeColor(for: .light))
            ]
            let stops = (colors.count >= 3 ? colors : fallback).map(\.cgColor)
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops as CFArray,
                locations: [0, 0.5, 1]
            )!
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(rounded.cgPath)
            ctx.cgContext.clip()
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: w / 2, y: 0),
                end: CGPoint(x: w / 2, y: h),
                options: []
            )
            ctx.cgContext.restoreGState()
            UIColor.white.setStroke()
            rounded.lineWidth = 4
            rounded.lineJoinStyle = .round
            rounded.lineCapStyle = .round
            rounded.stroke()
        }
    }
}

final class LiveFollowPinAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .none
        displayPriority = .required
        // Below the puck (`.max`) so the vehicle stays on top if they overlap,
        // but high enough that MapKit never treats the start flag as occluded.
        zPriority = MKAnnotationViewZPriority(rawValue: 750)
        if let pin = annotation as? LiveFollowPinAnnotation {
            apply(pin)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        if let pin = annotation as? LiveFollowPinAnnotation {
            apply(pin)
        }
    }

    func apply(_ annotation: LiveFollowPinAnnotation) {
        displayPriority = .required
        collisionMode = .none
        zPriority = MKAnnotationViewZPriority(rawValue: 750)
        let routeKind: RouteMapPinKind = {
            switch annotation.kind {
            case .start: return .start
            case .pause, .tripStop: return .stop
            case .destination: return .end
            }
        }()
        let pinImage = RouteMapPinImage.uiImage(for: routeKind)
        image = pinImage
        centerOffset = routeKind.isEndpoint
            ? CGPoint(x: 0, y: -pinImage.size.height / 2)
            : .zero
        accessibilityLabel = {
            switch annotation.kind {
            case .start: return L10n.string("recording.live_map.start_pin")
            case .pause: return L10n.string("recording.live_map.pause_pin")
            case .tripStop: return L10n.tripPointStop
            case .destination: return L10n.string("recording.live_map.destination_pin")
            }
        }()
    }
}
