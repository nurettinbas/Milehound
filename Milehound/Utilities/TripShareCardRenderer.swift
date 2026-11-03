import MapKit
import SwiftUI
import UIKit

@MainActor
enum TripShareCardRenderer {
    /// Same 9:16 canvas as recap / badge share so Instagram Stories fills edge-to-edge.
    static let defaultSize = RecapShareRenderer.pixelSize

    fileprivate enum Layout {
        /// Snapshot is taller than the flexible map slot so `scaledToFill` stays sharp.
        static let mapHeightFraction: CGFloat = 0.45
        /// Keep the brand mark above Instagram’s story chrome (~200 px at 1080).
        static var bottomReserve: CGFloat {
            RecapShareRenderer.layoutWidth * 200 / RecapShareRenderer.pixelSize.width
        }
    }

    static func render(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        size: CGSize = defaultSize,
        palette: ShellPalette,
        scheme: ColorScheme
    ) async -> UIImage? {
        // Fault points once on the main actor, then hop off for clip / decimate / chart / bands.
        let points = TripShareRoutePrep.points(
            from: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let placeInputs = places.map(TripShareRoutePrep.Place.init)
        let displayScale = UIScreen.main.scale

        let prep = await Task.detached(priority: .userInitiated) {
            TripShareRoutePrep.prepare(
                points: points,
                privacyRadiusMeters: privacyRadius,
                places: placeInputs
            )
        }.value

        let mapHeight = size.height * Layout.mapHeightFraction
        let mapSize = CGSize(width: size.width, height: mapHeight)
        let coordinates = prep.strokes.flatMap(\.coordinates)

        let mapImage: UIImage
        if coordinates.count >= 2 {
            mapImage = await renderMap(
                strokes: prep.strokes,
                start: prep.start.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                },
                end: prep.end.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                },
                size: mapSize,
                displayScale: displayScale,
                appearance: MapSnapshotAppearance(scheme)
            ) ?? UIImage()
        } else {
            mapImage = UIImage()
        }

        return composeCard(
            mapImage: mapImage,
            trip: trip,
            places: places,
            privacyRadius: privacyRadius,
            size: size,
            palette: palette,
            scheme: scheme
        )
    }

    // MARK: - Map

    private static func renderMap(
        strokes: [TripShareRoutePrep.StrokeSegment],
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?,
        size: CGSize,
        displayScale: CGFloat,
        appearance: MapSnapshotAppearance
    ) async -> UIImage? {
        let coordinates = strokes.flatMap(\.coordinates)
        guard !coordinates.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = regionFor(coordinates: coordinates)
        options.size = size
        options.mapType = .standard
        options.traitCollection = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = appearance.userInterfaceStyle
            mutableTraits.displayScale = displayScale
        }

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await snapshotter.start()
        } catch {
            return nil
        }

        return drawRoute(on: snapshot, strokes: strokes, start: start, end: end)
    }

    private static func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        strokes: [TripShareRoutePrep.StrokeSegment],
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            for stroke in strokes where stroke.coordinates.count >= 2 {
                let points = stroke.coordinates.map { snapshot.point(for: $0) }
                strokePolyline(points: points, color: uiColor(for: stroke.band))
            }

            if let start {
                drawPin(
                    at: snapshot.point(for: start),
                    systemName: "flag.fill",
                    fill: .systemGreen
                )
            }
            if let end, strokes.contains(where: { $0.coordinates.count > 1 }) {
                drawPin(
                    at: snapshot.point(for: end),
                    systemName: "mappin.circle.fill",
                    fill: .systemRed
                )
            }

            drawLegend(in: CGRect(origin: .zero, size: snapshot.image.size))
        }
    }

    private static func strokePolyline(points: [CGPoint], color: UIColor) {
        guard points.count >= 2 else { return }
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.lineWidth = 11
        color.withAlphaComponent(0.35).setStroke()
        path.stroke()

        path.lineWidth = 5
        color.setStroke()
        path.stroke()
    }

    private static func drawPin(at point: CGPoint, systemName: String, fill: UIColor) {
        let diameter: CGFloat = 28
        let rect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let circle = UIBezierPath(ovalIn: rect)
        fill.setFill()
        circle.fill()
        UIColor.white.withAlphaComponent(0.9).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
        let symbolSize = symbol.size
        symbol.draw(
            at: CGPoint(
                x: point.x - symbolSize.width / 2,
                y: point.y - symbolSize.height / 2
            )
        )
    }

    private static func drawLegend(in bounds: CGRect) {
        let items: [(UIColor, String)] = [
            (.systemGreen, L10n.speedLegendSlow),
            (.systemYellow, L10n.speedLegendMedium),
            (.systemRed, L10n.speedLegendFast)
        ]
        let font = UIFont.systemFont(ofSize: 18, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        let spacing: CGFloat = 18
        let pillHeight: CGFloat = 34
        let horizontalPad: CGFloat = 14
        let dotSize: CGFloat = 10

        var totalWidth: CGFloat = horizontalPad * 2
        var itemWidths: [CGFloat] = []
        for (index, item) in items.enumerated() {
            let textWidth = (item.1 as NSString).size(withAttributes: attributes).width
            let width = dotSize + 8 + textWidth
            itemWidths.append(width)
            totalWidth += width
            if index < items.count - 1 { totalWidth += spacing }
        }

        let pillWidth = totalWidth
        let pillRect = CGRect(
            x: (bounds.width - pillWidth) / 2,
            y: bounds.height - pillHeight - 20,
            width: pillWidth,
            height: pillHeight
        )
        let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillHeight / 2)
        UIColor.black.withAlphaComponent(0.55).setFill()
        pill.fill()

        var x = pillRect.minX + horizontalPad
        let midY = pillRect.midY
        for (index, item) in items.enumerated() {
            let dotRect = CGRect(
                x: x,
                y: midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            item.0.setFill()
            UIBezierPath(ovalIn: dotRect).fill()

            let textX = x + dotSize + 8
            (item.1 as NSString).draw(
                at: CGPoint(x: textX, y: midY - font.lineHeight / 2),
                withAttributes: attributes
            )
            x += itemWidths[index] + spacing
        }
    }

    // MARK: - Card

    private static func composeCard(
        mapImage: UIImage,
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        size: CGSize,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> UIImage {
        let viewModel = TripDetailViewModel(trip: trip, places: places, privacyRadius: privacyRadius)
        let layout = RecapShareRenderer.layoutSize
        let poster = TripShareStoryPoster(
            mapImage: mapImage,
            viewModel: viewModel
        )
        .frame(width: layout.width, height: layout.height)
        .environment(\.shellPalette, palette)
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)
        .milehoundShareCaptureEnvironment()

        let renderer = ImageRenderer(content: poster)
        renderer.proposedSize = ProposedViewSize(width: layout.width, height: layout.height)
        renderer.scale = size.width / layout.width
        return renderer.uiImage ?? UIImage()
    }

    // MARK: - Helpers

    private static func uiColor(for band: SpeedBand) -> UIColor {
        switch band {
        case .slow: return .systemGreen
        case .medium: return .systemYellow
        case .fast: return .systemRed
        }
    }

    private static func regionFor(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

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
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct TripShareStoryPoster: View {
    let mapImage: UIImage
    let viewModel: TripDetailViewModel

    private var metrics: [TripSummaryMetric] { viewModel.summaryMetrics }

    var body: some View {
        VStack(spacing: 0) {
            mapSlot
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.routeSummary)
                        .font(.headline)
                        .glassPrimaryInk()
                        .lineLimit(2)
                    Text(viewModel.dateText)
                        .font(.caption)
                        .glassSecondaryInk()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                metricGrid
            }
            .padding(.horizontal, GlassTokens.listContentHorizontalInset)
            .padding(.top, 14)

            Spacer(minLength: 8)

            MilehoundBrandMark(showsWordmark: true, symbolSize: 36)
                .padding(.bottom, TripShareCardRenderer.Layout.bottomReserve)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AtmosphericBackground() }
        .onGlassShell()
        .clipped()
    }

    private var mapSlot: some View {
        Group {
            if mapImage.size.width > 2 {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160, maxHeight: .infinity)
        .clipped()
    }

    private var metricGrid: some View {
        let rowCount = (metrics.count + 2) / 3
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index < metrics.count {
                            TripSummaryMetricTile(
                                metric: metrics[index],
                                progress: 1,
                                frozen: true,
                                showsHelp: false
                            )
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Theme

struct TripShareCardTheme: Equatable {
    var palette: ShellPalette
    var scheme: ColorScheme

    var atmosphere: ShellAtmosphere { palette.atmosphere(for: scheme) }

    var title: UIColor { .white }

    var secondary: UIColor {
        UIColor.white.withAlphaComponent(0.72)
    }

    var tileFill: UIColor {
        UIColor.white.withAlphaComponent(scheme == .dark ? 0.12 : 0.22)
    }

    var chart: UIColor {
        atmosphere.tint.uiColor
    }
}

extension ShellRGB {
    var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Caption

@MainActor
enum TripShareCaption {
    static func build(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String {
        let viewModel = TripDetailViewModel(trip: trip, places: places, privacyRadius: privacyRadius)
        var lines = [
            viewModel.routeSummary,
            whenLine(for: trip)
        ]

        var parts: [String] = [
            viewModel.durationText,
            viewModel.distanceText
        ]
        if let maxSpeed = viewModel.maxSpeedText {
            parts.append("\(L10n.maxAbbr) \(maxSpeed)")
        }
        if let average = viewModel.averageSpeedKmh {
            parts.append("\(L10n.avgAbbr) \(L10n.formatSpeedKmh(average))")
        }
        if let fuel = viewModel.fuelText {
            parts.append(fuel)
        }
        lines.append(parts.joined(separator: " · "))
        return lines.joined(separator: "\n")
    }

    static func whenLine(for trip: Trip) -> String {
        let date = DateFormatters.tripDateOnly.string(from: trip.startedAt)
        let start = DateFormatters.tripTime.string(from: trip.startedAt)
        if let endedAt = trip.endedAt {
            let end = DateFormatters.tripTime.string(from: endedAt)
            return L10n.shareCaptionWhenRange(date: date, start: start, end: end)
        }
        return L10n.shareCaptionWhenStart(date: date, start: start)
    }
}
