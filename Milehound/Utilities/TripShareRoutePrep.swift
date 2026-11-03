import CoreLocation
import Foundation

/// Pure share-card path prep: privacy-clip once, then feed map strokes and the speed chart
/// from the same clipped samples. Safe to run off the main actor.
enum TripShareRoutePrep {
    struct Point: Sendable, Equatable {
        let latitude: Double
        let longitude: Double
        let timestamp: Date
        let speedMps: Double?
    }

    struct Place: Sendable, Equatable {
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
        let expandsClipRadius: Bool

        init(_ place: SavedPlace) {
            latitude = place.latitude
            longitude = place.longitude
            radiusMeters = place.radiusMeters
            expandsClipRadius = place.isPrivacyZone || place.kind == .home
        }

        init(
            latitude: Double,
            longitude: Double,
            radiusMeters: Double,
            expandsClipRadius: Bool
        ) {
            self.latitude = latitude
            self.longitude = longitude
            self.radiusMeters = radiusMeters
            self.expandsClipRadius = expandsClipRadius
        }
    }

    struct StrokeSegment: Sendable, Equatable {
        let latitudes: [Double]
        let longitudes: [Double]
        /// `SpeedBand.rawValue` — slow / medium / fast.
        let bandRawValue: Int

        var coordinates: [CLLocationCoordinate2D] {
            zip(latitudes, longitudes).map {
                CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1)
            }
        }

        var band: SpeedBand {
            SpeedBand(rawValue: bandRawValue) ?? .slow
        }
    }

    struct Result: Sendable, Equatable {
        let clippedPoints: [Point]
        let pieceCount: Int
        let start: Point?
        let end: Point?
        let chartSeries: SpeedChartSeries.Series
        let strokes: [StrokeSegment]
        /// Matches `TripDetailViewModel.speedChartMaxKmh` but from the clipped chart series.
        let chartMaxKmh: Double
    }

    nonisolated static func points(from samples: [RouteSample]) -> [Point] {
        samples.map {
            Point(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude,
                timestamp: $0.timestamp,
                speedMps: $0.speedMps
            )
        }
    }

    nonisolated static func prepare(
        points: [Point],
        privacyRadiusMeters: Double,
        places: [Place]
    ) -> Result {
        let samples = samples(from: points)
        let privacyPlaces = places.map {
            RoutePrivacyPlace(
                latitude: $0.latitude,
                longitude: $0.longitude,
                radiusMeters: $0.radiusMeters,
                expandsClipRadius: $0.expandsClipRadius
            )
        }
        let clippedRange = RoutePrivacyClipper.clippedRange(
            samples.map(\.coordinate),
            privacyRadiusMeters: privacyRadiusMeters,
            places: privacyPlaces
        )
        let clippedSamples = Array(samples[clippedRange])
        let pieces = RouteDisplayPath.displaySegments(samples: clippedSamples)
        let chartSeries = SpeedChartSeries.build(samples: clippedSamples)
        let strokes = SpeedColoredSegmentBuilder.build(pieces: pieces).map { segment in
            StrokeSegment(
                latitudes: segment.coordinates.map(\.latitude),
                longitudes: segment.coordinates.map(\.longitude),
                bandRawValue: segment.band.rawValue
            )
        }

        let peak = chartSeries.samples.map(\.speedKmh).max() ?? 0
        let chartMaxKmh = min(max(peak * 1.15, 80), 200)
        let clippedPoints = Self.points(from: clippedSamples)

        return Result(
            clippedPoints: clippedPoints,
            pieceCount: pieces.count,
            start: clippedPoints.first,
            end: clippedPoints.last,
            chartSeries: chartSeries,
            strokes: strokes,
            chartMaxKmh: chartMaxKmh
        )
    }

    nonisolated private static func samples(from points: [Point]) -> [RouteSample] {
        points.map {
            RouteSample(
                coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                timestamp: $0.timestamp,
                speedMps: $0.speedMps
            )
        }
    }
}
