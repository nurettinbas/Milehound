import CoreLocation
import MapKit
import SwiftUI

/// Trip detail map route: solid core + faint white casing under every color.
enum TripRouteMapStroke {
    static let solidWidth: CGFloat = 7.2
    static let casingWidth: CGFloat = 9.6
    static let casingColor = Color.white.opacity(0.45)
    static let lineCap: CGLineCap = .round
    static let lineJoin: CGLineJoin = .round
}

struct TripDetailRevealedRouteSegment: Identifiable, Equatable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id, lhs.coordinates.count == rhs.coordinates.count else { return false }
        return zip(lhs.coordinates, rhs.coordinates).allSatisfy {
            abs($0.latitude - $1.latitude) < 1e-12
                && abs($0.longitude - $1.longitude) < 1e-12
        }
    }
}

/// Map stroke inputs for route reveal: one growing polyline during ticks, colors when settled.
enum TripDetailRevealOverlays {
    static let settleProgress = 0.999

    struct Stroke {
        let revealedItems: [TripDetailRevealedRouteSegment]
        let revealedFallback: [CLLocationCoordinate2D]
        let drawCasing: Bool
    }

    /// Mid-reveal keeps a single fallback polyline so MapKit does not rebuild up to 60 color bands.
    static func stroke(
        progress: Double,
        coloredSegments: [SpeedColoredSegment],
        fallbackCoordinates: [CLLocationCoordinate2D]
    ) -> Stroke {
        if progress < settleProgress {
            return Stroke(
                revealedItems: [],
                revealedFallback: fallbackCoordinates,
                drawCasing: false
            )
        }
        let items = coloredSegments.map { segment in
            TripDetailRevealedRouteSegment(
                id: "\(segment.id)",
                coordinates: segment.coordinates,
                color: segment.color
            )
        }
        return Stroke(
            revealedItems: items,
            revealedFallback: items.isEmpty ? fallbackCoordinates : [],
            drawCasing: true
        )
    }
}

struct TripDetailMapStop: Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// Progress along the route at which this stop pin appears (ignored when `showAllStops`).
    let revealProgress: Double

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.revealProgress == rhs.revealProgress
            && abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 1e-12
            && abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 1e-12
    }
}

enum TripDetailMapStyle: Equatable {
    case standard
    case dark

    /// Picker default: follow the phone's appearance until the user chooses.
    static func matching(_ colorScheme: ColorScheme) -> TripDetailMapStyle {
        colorScheme == .dark ? .dark : .standard
    }

    /// Always force a scheme — `nil` would follow the system, so Light does nothing in Dark Mode.
    var forcedColorScheme: ColorScheme {
        switch self {
        case .standard: return .light
        case .dark: return .dark
        }
    }

    func mapStyle() -> MapStyle {
        // Always flat — realistic elevation remeshes on camera/layout changes and hitches.
        switch self {
        case .standard:
            return .standard(elevation: .flat)
        case .dark:
            return .standard(elevation: .flat, emphasis: .muted)
        }
    }
}

/// Camera box so the parent can rebuild without rewriting MapKit camera bindings.
@MainActor
@Observable
final class TripDetailMapCameraBox {
    var position: MapCameraPosition = .automatic
}

/// Isolated MapKit host for trip detail. Inputs exclude panel height so overlay
/// motion does not force MapKit to relayout or rebuild overlays.
/// Camera updates go through `cameraBox` only — never remount the Map (that flashes black).
struct TripDetailMapLayer: View, Equatable {
    let style: TripDetailMapStyle
    let interactive: Bool
    let routeRevealProgress: Double
    let drawCasing: Bool
    let revealedItems: [TripDetailRevealedRouteSegment]
    let revealedFallback: [CLLocationCoordinate2D]
    let startCoordinate: CLLocationCoordinate2D?
    let endCoordinate: CLLocationCoordinate2D?
    let startPinVisible: Bool
    let endPinVisible: Bool
    let showAllStops: Bool
    let stops: [TripDetailMapStop]
    let reduceMotion: Bool
    let cameraBox: TripDetailMapCameraBox

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style
            && lhs.interactive == rhs.interactive
            && lhs.routeRevealProgress == rhs.routeRevealProgress
            && lhs.drawCasing == rhs.drawCasing
            && lhs.revealedItems == rhs.revealedItems
            && lhs.revealedFallback.count == rhs.revealedFallback.count
            && lhs.startPinVisible == rhs.startPinVisible
            && lhs.endPinVisible == rhs.endPinVisible
            && lhs.showAllStops == rhs.showAllStops
            && lhs.stops == rhs.stops
            && lhs.reduceMotion == rhs.reduceMotion
            && Self.sameCoordinate(lhs.startCoordinate, rhs.startCoordinate)
            && Self.sameCoordinate(lhs.endCoordinate, rhs.endCoordinate)
    }

    private nonisolated static func sameCoordinate(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return abs(l.latitude - r.latitude) < 1e-12
                && abs(l.longitude - r.longitude) < 1e-12
        default:
            return false
        }
    }

    var body: some View {
        Map(position: Bindable(cameraBox).position, interactionModes: interactive ? .all : []) {
            if drawCasing {
                ForEach(revealedItems) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(
                            TripRouteMapStroke.casingColor,
                            style: StrokeStyle(
                                lineWidth: TripRouteMapStroke.casingWidth,
                                lineCap: TripRouteMapStroke.lineCap,
                                lineJoin: TripRouteMapStroke.lineJoin
                            )
                        )
                        .mapOverlayLevel(level: .aboveRoads)
                }
            }

            ForEach(revealedItems) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        segment.color,
                        style: StrokeStyle(
                            lineWidth: TripRouteMapStroke.solidWidth,
                            lineCap: TripRouteMapStroke.lineCap,
                            lineJoin: TripRouteMapStroke.lineJoin
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            }

            if revealedItems.isEmpty, revealedFallback.count >= 2 {
                if drawCasing {
                    MapPolyline(coordinates: revealedFallback)
                        .stroke(
                            TripRouteMapStroke.casingColor,
                            style: StrokeStyle(
                                lineWidth: TripRouteMapStroke.casingWidth,
                                lineCap: TripRouteMapStroke.lineCap,
                                lineJoin: TripRouteMapStroke.lineJoin
                            )
                        )
                }
                MapPolyline(coordinates: revealedFallback)
                    .stroke(
                        .cyan,
                        style: StrokeStyle(
                            lineWidth: TripRouteMapStroke.solidWidth,
                            lineCap: TripRouteMapStroke.lineCap,
                            lineJoin: TripRouteMapStroke.lineJoin
                        )
                    )
            }

            ForEach(stops) { stop in
                if showAllStops || routeRevealProgress >= stop.revealProgress {
                    Annotation(L10n.tripPointStop, coordinate: stop.coordinate) {
                        RouteMapPinMark(
                            kind: .stop,
                            popped: true,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }

            if startPinVisible, let start = startCoordinate {
                Annotation(L10n.tripPointStart, coordinate: start, anchor: .bottom) {
                    RouteMapPinMark(
                        kind: .start,
                        popped: startPinVisible,
                        reduceMotion: reduceMotion
                    )
                }
            }

            if endPinVisible, let end = endCoordinate {
                Annotation(L10n.tripPointEnd, coordinate: end, anchor: .bottom) {
                    RouteMapPinMark(
                        kind: .end,
                        popped: endPinVisible,
                        reduceMotion: reduceMotion
                    )
                }
            }
        }
        .mapStyle(style.mapStyle())
        .colorScheme(style.forcedColorScheme)
        .glassMapTopEdgeHidden()
    }
}

extension TripDetailMapStop: Identifiable {}
