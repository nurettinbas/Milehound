import CoreLocation
import MapKit
import SwiftUI

struct TravelJournalRouteOverlay: Identifiable, Equatable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    let isSelected: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.isSelected == rhs.isSelected
            && lhs.coordinates.count == rhs.coordinates.count
    }
}

struct TravelJournalMapLayer: View, Equatable {
    let style: TripDetailMapStyle
    let overlays: [TravelJournalRouteOverlay]
    let selectedSegments: [TripDetailRevealedRouteSegment]
    let cameraBox: TripDetailMapCameraBox

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style
            && lhs.overlays == rhs.overlays
            && lhs.selectedSegments == rhs.selectedSegments
    }

    var body: some View {
        Map(position: Bindable(cameraBox).position, interactionModes: .all) {
            ForEach(overlays) { overlay in
                if overlay.isSelected {
                    MapPolyline(coordinates: overlay.coordinates)
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

                MapPolyline(coordinates: overlay.coordinates)
                    .stroke(
                        overlay.color,
                        style: StrokeStyle(
                            lineWidth: overlay.isSelected ? TripRouteMapStroke.solidWidth : 5,
                            lineCap: TripRouteMapStroke.lineCap,
                            lineJoin: TripRouteMapStroke.lineJoin
                        )
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            }

            ForEach(selectedSegments) { segment in
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
        }
        .mapStyle(style.mapStyle())
        .mapControlVisibility(.hidden)
        .glassMapTopEdgeHidden()
    }
}
