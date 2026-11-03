import MapKit
import SwiftUI

enum FrequentRoutesMapCamera {
    static func visibleRect(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) -> MKMapRect {
        visibleRect(coordinates: [start, end])
    }

    static func visibleRect(coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null
        for coordinate in coordinates where CLLocationCoordinate2DIsValid(coordinate) {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        guard !rect.isNull, !rect.isEmpty else { return .null }
        let latitude = coordinates.first?.latitude ?? 0
        let metersPerPoint = MKMetersPerMapPointAtLatitude(latitude)
        let minPad = 520 / max(metersPerPoint, 0.001)
        let padX = max(rect.size.width * 0.28, minPad)
        let padY = max(rect.size.height * 0.28, minPad)
        return rect.insetBy(dx: -padX, dy: -padY)
    }

    static func visibleRect(
        covering aggregates: [FrequentRouteAggregate],
        paths: [String: [CLLocationCoordinate2D]] = [:]
    ) -> MKMapRect {
        var coords: [CLLocationCoordinate2D] = []
        for aggregate in aggregates where aggregate.hasValidCoordinates {
            if let path = paths[aggregate.pairKey], path.count >= 2 {
                coords.append(contentsOf: path)
            } else {
                coords.append(aggregate.startCoordinate)
                coords.append(aggregate.endCoordinate)
            }
        }
        let fitted = visibleRect(coordinates: coords)
        guard let featured = aggregates.first(where: \.hasValidCoordinates) else { return fitted }
        if spanMeters(fitted) > FrequentRouteOverlayBudget.maxCameraSpanMeters {
            if let path = paths[featured.pairKey], path.count >= 2 {
                return visibleRect(coordinates: path)
            }
            return visibleRect(start: featured.startCoordinate, end: featured.endCoordinate)
        }
        return fitted
    }

    static func spanMeters(_ rect: MKMapRect) -> CLLocationDistance {
        guard !rect.isNull else { return 0 }
        let a = MKMapPoint(x: rect.minX, y: rect.minY)
        let b = MKMapPoint(x: rect.maxX, y: rect.maxY)
        return a.distance(to: b)
    }

    static let edgePadding = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    /// Stable insets so the corridor does not slide when the host grows card → full screen.
    static func edgePadding(for size: CGSize) -> UIEdgeInsets {
        _ = size
        return edgePadding
    }
}

final class FrequentRoutesMapViewHost: MKMapView {
    var onLayout: ((MKMapView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

final class FrequentRoutePolyline: MKPolyline {
    var count: Int = 1
    var isBusiness: Bool = false
    var pairKey: String = ""
    var emphasis: CGFloat = 1

    static func make(
        coordinates: [CLLocationCoordinate2D],
        aggregate: FrequentRouteAggregate,
        emphasis: CGFloat
    ) -> FrequentRoutePolyline {
        var coords = coordinates
        let line = FrequentRoutePolyline(coordinates: &coords, count: coords.count)
        line.count = aggregate.count
        line.isBusiness = aggregate.isBusinessHeavy
        line.pairKey = aggregate.pairKey
        line.emphasis = min(1, max(0.28, emphasis))
        return line
    }
}

final class FrequentRoutesHeatmapOverlay: NSObject, MKOverlay {
    let samples: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(samples: [CLLocationCoordinate2D]) {
        self.samples = samples
        var rect = MKMapRect.null
        for sample in samples {
            let point = MKMapPoint(sample)
            let cell = MKMapRect(x: point.x - 40_000, y: point.y - 40_000, width: 80_000, height: 80_000)
            rect = rect.union(cell)
        }
        boundingMapRect = rect.isNull ? MKMapRect.world : rect
        coordinate = samples.first ?? CLLocationCoordinate2D()
        super.init()
    }
}

final class FrequentRoutesHeatmapRenderer: MKOverlayRenderer {
    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        overlay.boundingMapRect.intersects(mapRect)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FrequentRoutesHeatmapOverlay else { return }
        // Zoomed in: arcs carry the story, heatmap eases off. Zoomed out: cells merge.
        let fade = min(1, max(0, CGFloat(0.00012 / max(zoomScale, 0.00001))))
        guard fade > 0.04 else { return }
        let cell = max(24.0 / zoomScale, 8)
        var grid: [String: Int] = [:]
        for sample in overlay.samples {
            let mapPoint = MKMapPoint(sample)
            guard mapRect.contains(mapPoint) || mapRect.intersects(
                MKMapRect(x: mapPoint.x - cell, y: mapPoint.y - cell, width: cell * 2, height: cell * 2)
            ) else { continue }
            let point = point(for: mapPoint)
            let key = "\(Int(point.x / cell))|\(Int(point.y / cell))"
            grid[key, default: 0] += 1
        }
        let maxCount = max(grid.values.max() ?? 1, 1)
        for (key, count) in grid {
            let parts = key.split(separator: "|")
            guard parts.count == 2,
                  let gx = Int(parts[0]),
                  let gy = Int(parts[1]) else { continue }
            let rect = CGRect(x: CGFloat(gx) * cell, y: CGFloat(gy) * cell, width: cell, height: cell)
            let t = CGFloat(count) / CGFloat(maxCount)
            context.setFillColor(
                UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: (0.08 + 0.32 * t) * fade).cgColor
            )
            context.fillEllipse(in: rect.insetBy(dx: cell * 0.1, dy: cell * 0.1))
        }
    }
}

struct FrequentRoutesMapKitView: UIViewRepresentable {
    var aggregates: [FrequentRouteAggregate]
    var isDark: Bool
    var onSelect: ((FrequentRouteAggregate) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> FrequentRoutesMapViewHost {
        let map = FrequentRoutesMapViewHost(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.onLayout = { [weak coordinator = context.coordinator] host in
            coordinator?.handleLayout(host)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTapMap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        applyStyle(map)
        return map
    }

    func updateUIView(_ map: FrequentRoutesMapViewHost, context: Context) {
        context.coordinator.onSelect = onSelect
        applyStyle(map)
        let habits = FrequentRouteOverlayBudget.habitCorridors(aggregates)
        context.coordinator.replaceOverlays(on: map, aggregates: habits)
        context.coordinator.handleLayout(map)
    }

    private func applyStyle(_ map: MKMapView) {
        map.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: isDark ? .muted : .default
        )
        if isDark {
            map.overrideUserInterfaceStyle = .dark
        } else {
            map.overrideUserInterfaceStyle = .light
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onSelect: ((FrequentRouteAggregate) -> Void)?
        private var lastKeys: [String] = []
        private var byKey: [String: FrequentRouteAggregate] = [:]
        private var pathByKey: [String: [CLLocationCoordinate2D]] = [:]
        private var displayed: [FrequentRouteAggregate] = []
        private var selected: FrequentRouteAggregate?
        private var lastLayoutSize: CGSize = .zero
        private var pathLoadGeneration = 0

        init(onSelect: ((FrequentRouteAggregate) -> Void)?) {
            self.onSelect = onSelect
        }

        func handleLayout(_ map: MKMapView) {
            let size = map.bounds.size
            guard size.width >= 64, size.height >= 64 else { return }
            let changed = abs(size.width - lastLayoutSize.width) > 0.5
                || abs(size.height - lastLayoutSize.height) > 0.5
            lastLayoutSize = size
            guard changed else { return }
            pinCamera(on: map, animated: false)
        }

        /// Camera is for the full-screen map. The overlay scales that view into the card;
        /// resizing the MKMapView would pan tiles upward.
        private func pinCamera(on map: MKMapView, animated: Bool) {
            if let selected {
                focus(map, on: selected, animated: animated)
            } else {
                focusHabits(on: map, animated: animated)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func didTapMap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            let tap = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            var best: (FrequentRouteAggregate, CLLocationDistance)?
            for (key, aggregate) in byKey where aggregate.hasValidCoordinates {
                let samples = pathByKey[key] ?? [aggregate.startCoordinate, aggregate.endCoordinate]
                let nearest = samples.map {
                    tap.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                }.min() ?? .greatestFiniteMagnitude
                if nearest < 500, nearest < (best?.1 ?? .greatestFiniteMagnitude) {
                    best = (aggregate, nearest)
                }
            }
            if let best {
                selected = best.0
                onSelect?(best.0)
                focus(map, on: best.0, animated: true)
            }
        }

        func replaceOverlays(on map: MKMapView, aggregates: [FrequentRouteAggregate]) {
            let keys = aggregates.map(\.pairKey)
            guard keys != lastKeys else { return }
            lastKeys = keys
            displayed = aggregates
            byKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.pairKey, $0) })
            pathByKey = [:]
            selected = nil
            map.removeOverlays(map.overlays)
            focusHabits(on: map, animated: false)
            pathLoadGeneration += 1
            let generation = pathLoadGeneration
            let snapshot = aggregates
            Task { @MainActor [weak self, weak map] in
                guard let self, let map, generation == self.pathLoadGeneration else { return }
                var paths: [String: [CLLocationCoordinate2D]] = [:]
                for aggregate in snapshot where aggregate.hasValidCoordinates {
                    paths[aggregate.pairKey] = await FrequentRouteRoadPathCache.shared.path(
                        pairKey: aggregate.pairKey,
                        start: aggregate.startCoordinate,
                        end: aggregate.endCoordinate
                    )
                }
                guard generation == self.pathLoadGeneration else { return }
                self.pathByKey = paths
                self.installRoadOverlays(on: map)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FrequentRoutesHeatmapOverlay {
                return FrequentRoutesHeatmapRenderer(overlay: overlay)
            }
            guard let line = overlay as? FrequentRoutePolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            renderer.lineWidth = 3.2 + 5.0 * line.emphasis
            let alpha = 0.42 + 0.50 * line.emphasis
            renderer.strokeColor = line.isBusiness
                ? UIColor(red: 0.61, green: 0.50, blue: 0.91, alpha: alpha)
                : UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: alpha)
            return renderer
        }

        private func installRoadOverlays(on map: MKMapView) {
            map.removeOverlays(map.overlays)
            var samples: [CLLocationCoordinate2D] = []
            let heroCount = max(displayed.first?.count ?? 1, 1)
            for aggregate in displayed where aggregate.hasValidCoordinates {
                let coords = pathByKey[aggregate.pairKey] ?? [aggregate.startCoordinate, aggregate.endCoordinate]
                guard coords.count >= 2 else { continue }
                let emphasis = CGFloat(aggregate.count) / CGFloat(heroCount)
                map.addOverlay(
                    FrequentRoutePolyline.make(coordinates: coords, aggregate: aggregate, emphasis: emphasis),
                    level: .aboveRoads
                )
                samples.append(contentsOf: FrequentRouteRoadPathCache.heatmapSamples(
                    coords,
                    count: FrequentRouteOverlayBudget.heatmapSamplesPerArc
                ))
            }
            if !samples.isEmpty {
                map.addOverlay(FrequentRoutesHeatmapOverlay(samples: samples), level: .aboveLabels)
            }
            // Keep the first camera. Reframing when roads arrive would pan during the expand.
        }

        private func focusHabits(on map: MKMapView, animated: Bool) {
            let rect = FrequentRoutesMapCamera.visibleRect(covering: displayed, paths: pathByKey)
            guard !rect.isNull, !rect.isEmpty else { return }
            map.setVisibleMapRect(
                rect,
                edgePadding: FrequentRoutesMapCamera.edgePadding(for: map.bounds.size),
                animated: animated
            )
        }

        private func focus(_ map: MKMapView, on aggregate: FrequentRouteAggregate, animated: Bool) {
            guard aggregate.hasValidCoordinates else { return }
            let coords = pathByKey[aggregate.pairKey] ?? [aggregate.startCoordinate, aggregate.endCoordinate]
            map.setVisibleMapRect(
                FrequentRoutesMapCamera.visibleRect(coordinates: coords),
                edgePadding: FrequentRoutesMapCamera.edgePadding(for: map.bounds.size),
                animated: animated
            )
        }
    }
}

/// Static MapKit snapshot of the top frequent-route arcs. Never walks GPS polylines.
@MainActor
final class FrequentRoutesSnapshotCache {
    static let shared = FrequentRoutesSnapshotCache()

    private var memory: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let cacheDirectory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = support.appendingPathComponent("FrequentRouteSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Stable across equivalent coordinates. Rounded so a later open hits the same disk file.
    nonisolated static func cacheKey(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        count: Int,
        isBusiness: Bool,
        size: CGSize
    ) -> String {
        func rounded(_ value: Double) -> String {
            String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        let startToken = "\(rounded(start.latitude)),\(rounded(start.longitude))"
        let endToken = "\(rounded(end.latitude)),\(rounded(end.longitude))"
        return "pair:\(startToken):\(endToken):\(count):\(isBusiness):\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    func snapshot(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        count: Int,
        isBusiness: Bool,
        size: CGSize = CGSize(width: 280, height: 160)
    ) async -> UIImage? {
        let key = Self.cacheKey(start: start, end: end, count: count, isBusiness: isBusiness, size: size)
        if let cached = memory[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }
        let diskURL = cacheDirectory.appendingPathComponent("\(Self.stableName(for: key)).jpg")
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            memory[key] = image
            return image
        }
        let task = Task<UIImage?, Never> {
            let path = await FrequentRouteRoadPathCache.shared.path(
                pairKey: "snapshot",
                start: start,
                end: end
            )
            return await Self.render(path: path, count: count, isBusiness: isBusiness, size: size)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory[key] = image
            if let data = image.jpegData(compressionQuality: 0.72) {
                try? data.write(to: diskURL, options: .atomic)
            }
        }
        return image
    }

    func snapshot(
        for aggregates: [FrequentRouteAggregate],
        size: CGSize = CGSize(width: 320, height: 140)
    ) async -> UIImage? {
        let featured = FrequentRouteOverlayBudget.habitCorridors(aggregates).first
            ?? FrequentRouteOverlayBudget.topAggregates(aggregates).first(where: \.hasValidCoordinates)
        guard let featured else { return nil }
        let key = "road:\(featured.pairKey):\(featured.count)"
        if let cached = memory[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }
        let diskURL = cacheDirectory.appendingPathComponent("\(Self.stableName(for: key)).jpg")
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            memory[key] = image
            return image
        }
        let path = await FrequentRouteRoadPathCache.shared.path(
            pairKey: featured.pairKey,
            start: featured.startCoordinate,
            end: featured.endCoordinate
        )
        let copies = SnapshotStroke(
            path: path,
            isBusiness: featured.isBusinessHeavy,
            count: featured.count
        )
        let task = Task<UIImage?, Never> {
            await Self.render(path: copies.path, count: copies.count, isBusiness: copies.isBusiness, size: size)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory[key] = image
            if let data = image.jpegData(compressionQuality: 0.72) {
                try? data.write(to: diskURL, options: .atomic)
            }
        }
        return image
    }

    func dropMemory() {
        memory.removeAll(keepingCapacity: true)
    }

    private static func stableName(for key: String) -> String {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private struct SnapshotStroke {
        let path: [CLLocationCoordinate2D]
        let isBusiness: Bool
        let count: Int
    }

    private static func render(
        path: [CLLocationCoordinate2D],
        count: Int,
        isBusiness: Bool,
        size: CGSize
    ) async -> UIImage? {
        guard path.count >= 2 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.mapRect = FrequentRoutesMapCamera.visibleRect(coordinates: path)
        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let line = CGMutablePath()
            line.move(to: snapshot.point(for: path[0]))
            for coordinate in path.dropFirst() {
                line.addLine(to: snapshot.point(for: coordinate))
            }
            cg.addPath(line)
            let alpha: CGFloat = 0.55 + min(0.35, CGFloat(log2(Double(max(count, 1)))) * 0.08)
            let color = isBusiness
                ? UIColor(red: 0.61, green: 0.50, blue: 0.91, alpha: alpha)
                : UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: alpha)
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(2.6 + CGFloat(log2(Double(max(count, 1)))))
            cg.strokePath()
        }
    }
}
