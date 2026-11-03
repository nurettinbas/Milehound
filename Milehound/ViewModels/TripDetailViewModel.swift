import Charts
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct SpeedColoredSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let band: SpeedBand

    var color: Color { band.color }

    init(id: Int, coordinates: [CLLocationCoordinate2D], band: SpeedBand) {
        self.id = id
        self.coordinates = coordinates
        self.band = band
    }
}

struct TripSummaryMetric: Identifiable {
    enum Kind {
        case duration(TimeInterval)
        case distance(Double)
        case maxSpeedKmh(Double)
        case averageSpeedKmh(Double)
        case cruiseSpeedKmh(Double)
        case mostCommonSpeedKmh(Double)
        case medianSpeedKmh(Double)
        case p90SpeedKmh(Double)
        case stopDuration(TimeInterval)
        /// Cost plus optional volume label (e.g. "₺19 · 0,3 L").
        case fuel(cost: Double, detail: String?)
        /// Cost plus optional volume label (e.g. "₺142 · 2,1 L").
        case dynamicFuel(cost: Double, detail: String?)
        case efficiency(score: Double)
        case traffic(level: FuelTrafficLevel)
        case measuredFuel(detail: String)
    }

    let id: String
    let icon: String
    let title: String
    let kind: Kind
    var helpTitle: String? = nil
    var helpBody: String? = nil

    var showsHelp: Bool { helpTitle != nil && helpBody != nil }

    func formatted(progress: Double) -> String {
        let p = min(1, max(0, progress))
        // Ease-out so the last digits land softly.
        let eased = 1 - pow(1 - p, 2.2)
        switch kind {
        case .duration(let seconds):
            return DateFormatters.formatDuration(seconds * eased)
        case .distance(let meters):
            return DateFormatters.formatDistance(meters * eased)
        case .maxSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .averageSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .cruiseSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .mostCommonSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .medianSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .p90SpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .stopDuration(let seconds):
            return DateFormatters.formatDuration(seconds * eased)
        case .fuel(let cost, let detail), .dynamicFuel(let cost, let detail):
            let costText = FuelCostCalculator.formatCost(cost * eased)
            if let detail, !detail.isEmpty, p >= 0.99 {
                return "\(costText) · \(detail)"
            }
            return costText
        case .efficiency(let score):
            return "\(Int((score * eased).rounded()))"
        case .traffic(let level):
            return Self.trafficText(level)
        case .measuredFuel(let detail):
            return detail
        }
    }

    static func trafficText(_ level: FuelTrafficLevel) -> String {
        switch level {
        case .low: return L10n.fuelTrafficLow
        case .moderate: return L10n.fuelTrafficModerate
        case .heavy: return L10n.fuelTrafficHeavy
        case .unknown: return L10n.fuelTrafficUnknown
        }
    }

    static func factorTitle(_ kind: FuelFactorKind) -> String {
        switch kind {
        case .coldStart: return L10n.fuelFactorColdStart
        case .idleTraffic: return L10n.fuelFactorIdle
        case .transientAcceleration: return L10n.fuelFactorAccel
        case .highSpeed: return L10n.fuelFactorHighSpeed
        case .lowSpeed: return L10n.fuelFactorLowSpeed
        case .steadyEfficientSpeed: return L10n.fuelFactorSteady
        }
    }
}

@MainActor
struct TripDetailViewModel {
    /// Fractional insets (0...1) describing UI that covers the map; used to zoom/pan so the route fits the visible area.
    struct MapFitContext: Equatable {
        var top: Double
        var bottom: Double
        var horizontal: Double
        /// Map view width / height. Needed so latitude/longitude spans match the portrait
        /// aspect — equal spans make MapKit expand latitude and defeat the vertical offset.
        var aspectWidthOverHeight: Double

        /// Visible strip above the default balanced overlay panel (full-screen map).
        /// `top` is only status/nav chrome over the map (transparent bar); keep it measured in the view.
        static let detailWithPanel = MapFitContext(
            top: 0.10,
            bottom: 0.60,
            horizontal: 0.06,
            aspectWidthOverHeight: 0.46
        )
        static let fullscreen = MapFitContext(
            top: 0.11,
            bottom: 0.10,
            horizontal: 0.06,
            aspectWidthOverHeight: 0.46
        )
        static let cinematicReveal = MapFitContext(
            top: 0.10,
            bottom: 0.08,
            horizontal: 0.06,
            aspectWidthOverHeight: 0.46
        )

        /// Fit for a live overlay panel on a full-screen map.
        /// - topChromeFraction: status + nav overlay on the map (from GeometryReader)
        /// - panelFraction: opaque card height / map height
        /// Bottom adds legend + pin clearance so the route centers in the clear map, not under chrome.
        static func detailOverlay(
            panelFraction: Double,
            aspectWidthOverHeight: Double,
            topChromeFraction: Double = 0.10
        ) -> MapFitContext {
            let top = max(0.06, min(topChromeFraction, 0.16))
            // Speed legend + start/end pin labels sit above the card in the map strip.
            let bottomChrome = 0.09
            let minVisible = 0.18
            let bottom = min(
                max(panelFraction + bottomChrome, 0.34),
                1 - top - minVisible
            )
            return MapFitContext(
                top: top,
                bottom: bottom,
                horizontal: 0.06,
                aspectWidthOverHeight: max(0.35, min(aspectWidthOverHeight, 0.7))
            )
        }
    }

    let trip: Trip
    let places: [SavedPlace]
    let privacyRadius: Double
    /// Decimated drawable pieces from `TripRoutePathCache`. `nil` until the async load finishes.
    let displayPieces: [[RouteSample]]?
    let routeFingerprint: TripRoutePathFingerprint

    private struct SpeedSegmentCacheEntry {
        let fingerprint: TripRoutePathFingerprint
        let displayPointCount: Int
        let segments: [SpeedColoredSegment]
    }

    private static var speedSegmentCache: [UUID: SpeedSegmentCacheEntry] = [:]

    private struct ChartSeriesCacheEntry {
        let fingerprint: TripRoutePathFingerprint
        let series: SpeedChartSeries.Series
    }

    /// The chart series is read several times per body pass — samples, median interval, axis
    /// scale — and building it walks every point, so it is built once per trip.
    private static var chartSeriesCache: [UUID: ChartSeriesCacheEntry] = [:]

    static func invalidateSpeedSegmentCache(for tripID: UUID) {
        speedSegmentCache.removeValue(forKey: tripID)
        chartSeriesCache.removeValue(forKey: tripID)
    }

    init(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        displayPieces: [[RouteSample]]? = nil
    ) {
        self.trip = trip
        self.places = places
        self.privacyRadius = privacyRadius
        self.displayPieces = displayPieces
        self.routeFingerprint = TripRoutePathFingerprint.make(from: trip)
    }

    /// SwiftUI can keep one `TripDetailView` alive while its `trip` changes (a replaced
    /// navigation path, a new pane selection). A model built for another trip must never
    /// draw, measure, or lend its route to the current one.
    func belongs(to trip: Trip) -> Bool {
        self.trip.id == trip.id
    }

    /// Route pieces safe to carry into a rebuilt model for `trip`; `nil` when `existing`
    /// was built for a different trip.
    static func reusablePieces(from existing: TripDetailViewModel?, for trip: Trip) -> [[RouteSample]]? {
        guard let existing, existing.belongs(to: trip) else { return nil }
        return existing.displayPieces
    }

    /// UI-test readout: which trip the drawn route came from and whether it starts at the
    /// trip's own start pin (`loading`, `match`, `mismatch`).
    func routeIdentityLabel(for trip: Trip) -> String {
        let state: String
        if let first = displayPieces?.first?.first?.coordinate {
            if let lat = trip.startLatitude, let lon = trip.startLongitude {
                let close = abs(first.latitude - lat) < 0.001 && abs(first.longitude - lon) < 0.001
                state = belongs(to: trip) && close ? "match" : "mismatch"
            } else {
                state = belongs(to: trip) ? "match" : "mismatch"
            }
        } else {
            state = "loading"
        }
        return "trip=\(trip.id.uuidString) model=\(self.trip.id.uuidString) route=\(state)"
    }

    var durationText: String {
        guard let duration = trip.duration else { return "—" }
        return DateFormatters.formatDuration(duration)
    }

    var distanceText: String {
        DateFormatters.formatDistance(trip.distanceMeters)
    }

    var dateText: String {
        DateFormatters.tripDate.string(from: trip.startedAt)
    }

    var routeSummary: String {
        TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
    }

    var hasDisplayPath: Bool {
        displayPieces != nil
    }

    /// Flattened coordinates of the prepared display path (empty while loading).
    var displayCoordinates: [CLLocationCoordinate2D] {
        (displayPieces ?? []).flatMap { $0.map(\.coordinate) }
    }

    /// Start/end markers sit at the ends of the drawn route. Prefer denormalised endpoints so
    /// opening detail never faults every GPS point just to place two pins.
    var routeStartCoordinate: CLLocationCoordinate2D? {
        if let first = displayPieces?.first?.first?.coordinate {
            return first
        }
        return trip.startCoordinate
    }

    var routeEndCoordinate: CLLocationCoordinate2D? {
        if let last = displayPieces?.last?.last?.coordinate {
            return last
        }
        return trip.endCoordinate
    }

    var speedSamples: [(id: Int, date: Date, speedKmh: Double)] {
        speedChartSeries.samples.enumerated().map { index, sample in
            (id: index, date: sample.date, speedKmh: sample.speedKmh)
        }
    }

    /// Median gap between the samples the chart actually plots — the chart uses this to decide
    /// where a real recording gap is, instead of a fixed threshold that breaks sparse trips.
    var speedSampleMedianIntervalSeconds: TimeInterval {
        speedChartSeries.medianIntervalSeconds
    }

    private var speedChartSeries: SpeedChartSeries.Series {
        if let cached = Self.chartSeriesCache[trip.id], cached.fingerprint == routeFingerprint {
            return cached.series
        }
        // Prefer the prepared display path so opening detail never faults every GPS point
        // just to draw the chart. Empty until `displayPieces` arrive.
        guard let pieces = displayPieces else {
            return SpeedChartSeries.Series()
        }
        let series = SpeedChartSeries.build(samples: pieces.flatMap { $0 })
        Self.chartSeriesCache[trip.id] = ChartSeriesCacheEntry(
            fingerprint: routeFingerprint,
            series: series
        )
        return series
    }

    /// Prefers speeds from the prepared display path so the summary strip never faults points
    /// on first paint. Falls back to the stored vetted maximum while the path is still loading.
    var derivedMaxSpeedMps: Double? {
        if let pieces = displayPieces, !pieces.isEmpty {
            return TripSpeedSummary.maxSpeedMps(samples: pieces.flatMap { $0 })
        }
        return TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps)
    }

    /// Scaled from the plotted data alone. Blending in the stored maximum pinned the axis at
    /// 200 km/h for a trip whose real peak was 84, squashing the whole line into the bottom third.
    var speedChartMaxKmh: Double {
        let peak = speedSamples.map(\.speedKmh).max() ?? 0
        return min(max(peak * 1.15, 80), 200)
    }

    var maxSpeedText: String? {
        guard let maxSpeed = derivedMaxSpeedMps else { return nil }
        return L10n.formatSpeedKmh(maxSpeed * 3.6)
    }

    var averageSpeedKmh: Double? {
        guard let duration = trip.duration, duration > 0, trip.distanceMeters > 0 else { return nil }
        let kmh = trip.distanceMeters * 3.6 / duration
        return kmh > 0 ? kmh : nil
    }

    /// Prefer the prepared display path when it is loaded so the strip always uses the current
    /// formula (implied-speed stops, neighbour-blended mode). Fall back to stored cruise / stop
    /// while the path is still loading.
    private var speedProfile: TripSpeedProfile.Result {
        if let pieces = displayPieces, !pieces.isEmpty {
            return TripSpeedProfile.compute(samples: pieces.flatMap { $0 })
        }
        if trip.stopDurationSeconds != nil || trip.cruiseDurationSeconds != nil {
            let cruise = trip.cruiseSpeedKmh ?? 0
            let storedMostCommon = trip.mostCommonSpeedKmh ?? 0
            return TripSpeedProfile.Result(
                cruiseSpeedKmh: cruise > 0 ? cruise : nil,
                cruiseDurationSeconds: trip.cruiseDurationSeconds ?? 0,
                stopDurationSeconds: trip.stopDurationSeconds ?? 0,
                mostCommonSpeedKmh: storedMostCommon > 0 ? storedMostCommon : nil,
                medianSpeedKmh: nil,
                p90SpeedKmh: nil
            )
        }
        return .empty
    }

    var cruiseSpeedKmh: Double? {
        speedProfile.cruiseSpeedKmh
    }

    var mostCommonSpeedKmh: Double? {
        speedProfile.mostCommonSpeedKmh
    }

    var medianSpeedKmh: Double? {
        speedProfile.medianSpeedKmh
    }

    var p90SpeedKmh: Double? {
        speedProfile.p90SpeedKmh
    }

    var stopDurationSeconds: TimeInterval? {
        guard trip.stopDurationSeconds != nil || displayPieces != nil else { return nil }
        return speedProfile.stopDurationSeconds
    }

    /// Time spent actually moving — pauses and standstills left out.
    /// Falls back to clock time minus stops when cruise was zeroed (short moving windows).
    var movingDurationSeconds: TimeInterval? {
        guard trip.cruiseDurationSeconds != nil || trip.stopDurationSeconds != nil || displayPieces != nil else {
            return nil
        }
        let moving = speedProfile.cruiseDurationSeconds
        if moving > 0 { return moving }
        guard let duration = trip.duration, duration > 0 else { return nil }
        let remainder = max(0, duration - speedProfile.stopDurationSeconds)
        return remainder > 0 ? remainder : nil
    }

    var fuelText: String? {
        let cost = StatsViewModel.fuelCost(for: trip)
        guard cost > 0 else { return nil }
        return FuelCostCalculator.formatCost(cost)
    }

    var summaryItems: [(icon: String, title: String, value: String)] {
        summaryMetrics.map { ($0.icon, $0.title, $0.formatted(progress: 1)) }
    }

    var summaryMetrics: [TripSummaryMetric] {
        var items: [TripSummaryMetric] = [
            TripSummaryMetric(
                id: "duration",
                icon: "clock",
                title: L10n.duration,
                kind: .duration(trip.duration ?? 0)
            )
        ]
        if let moving = movingDurationSeconds {
            items.append(
                TripSummaryMetric(
                    id: "movingDuration",
                    icon: "steeringwheel",
                    title: L10n.movingDuration,
                    kind: .duration(moving),
                    helpTitle: L10n.movingDurationHelpTitle,
                    helpBody: L10n.movingDurationHelpBody
                )
            )
        }
        items.append(
            TripSummaryMetric(
                id: "distance",
                icon: "road.lanes",
                title: L10n.labelDistance,
                kind: .distance(trip.distanceMeters)
            )
        )
        if let maxSpeed = derivedMaxSpeedMps {
            items.append(
                TripSummaryMetric(
                    id: "maxSpeed",
                    icon: "speedometer",
                    title: L10n.maxSpeed,
                    kind: .maxSpeedKmh(maxSpeed * 3.6)
                )
            )
        }
        if let averageSpeed = averageSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "averageSpeed",
                    icon: "gauge.with.dots.needle.33percent",
                    title: L10n.averageSpeed,
                    kind: .averageSpeedKmh(averageSpeed)
                )
            )
        }
        if let cruiseSpeed = cruiseSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "cruiseSpeed",
                    icon: "gauge.with.dots.needle.67percent",
                    title: L10n.cruiseSpeed,
                    kind: .cruiseSpeedKmh(cruiseSpeed),
                    helpTitle: L10n.cruiseSpeedHelpTitle,
                    helpBody: L10n.cruiseSpeedHelpBody
                )
            )
        }
        // Immediately right of cruise.
        if let mostCommon = mostCommonSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "mostCommonSpeed",
                    icon: "chart.bar",
                    title: L10n.mostCommonSpeed,
                    kind: .mostCommonSpeedKmh(mostCommon),
                    helpTitle: L10n.mostCommonSpeedHelpTitle,
                    helpBody: L10n.mostCommonSpeedHelpBody
                )
            )
        }
        if let median = medianSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "medianSpeed",
                    icon: "equal.circle",
                    title: L10n.medianSpeed,
                    kind: .medianSpeedKmh(median),
                    helpTitle: L10n.medianSpeedHelpTitle,
                    helpBody: L10n.medianSpeedHelpBody
                )
            )
        }
        if let p90 = p90SpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "p90Speed",
                    icon: "arrow.up.right.circle",
                    title: L10n.p90Speed,
                    kind: .p90SpeedKmh(p90),
                    helpTitle: L10n.p90SpeedHelpTitle,
                    helpBody: L10n.p90SpeedHelpBody
                )
            )
        }
        if let stopDuration = stopDurationSeconds {
            items.append(
                TripSummaryMetric(
                    id: "stopDuration",
                    icon: "pause.circle",
                    title: L10n.stopDuration,
                    kind: .stopDuration(stopDuration)
                )
            )
        }
        let fuel = StatsViewModel.fuelCost(for: trip)
        let isElectric = (trip.fuelTypeSnapshot ?? trip.vehicle?.fuelType) == .electric
        if fuel > 0 {
            let catalogRate = trip.fuelConsumptionPer100
            items.append(
                TripSummaryMetric(
                    id: "fuel",
                    icon: "fuelpump",
                    title: L10n.avgFuel,
                    kind: .fuel(
                        cost: fuel,
                        detail: fuelDetail(
                            cost: fuel,
                            volume: nil,
                            rate: catalogRate,
                            isElectric: isElectric
                        )
                    ),
                    helpTitle: L10n.avgFuelHelpTitle,
                    helpBody: L10n.avgFuelHelpBody
                )
            )
        }
        let dynamic = trip.dynamicFuelCost ?? 0
        if dynamic > 0 {
            items.append(
                TripSummaryMetric(
                    id: "dynamicFuel",
                    icon: "flame",
                    title: L10n.dynamicFuel,
                    kind: .dynamicFuel(
                        cost: dynamic,
                        detail: fuelDetail(
                            cost: dynamic,
                            volume: trip.dynamicFuelVolume,
                            rate: trip.dynamicFuelRatePer100,
                            isElectric: isElectric
                        )
                    ),
                    helpTitle: L10n.dynamicFuelHelpTitle,
                    helpBody: L10n.dynamicFuelHelpBody
                )
            )
        }
        if let score = trip.fuelEfficiencyScore, (trip.dynamicFuelCost ?? 0) > 0 {
            items.append(
                TripSummaryMetric(
                    id: "fuelEfficiency",
                    icon: "leaf",
                    title: L10n.fuelEfficiency,
                    kind: .efficiency(score: score),
                    helpTitle: L10n.fuelEfficiencyHelpTitle,
                    helpBody: L10n.fuelEfficiencyHelpBody
                )
            )
        }
        if let traffic = trip.fuelTrafficScore, (trip.dynamicFuelCost ?? 0) > 0 {
            let level: FuelTrafficLevel
            if (trip.fuelEstimateConfidence ?? 0) < 0.5 {
                level = .unknown
            } else if traffic < 0.33 {
                level = .low
            } else if traffic <= 0.66 {
                level = .moderate
            } else {
                level = .heavy
            }
            items.append(
                TripSummaryMetric(
                    id: "fuelTraffic",
                    icon: "car.2",
                    title: L10n.fuelTraffic,
                    kind: .traffic(level: level),
                    helpTitle: L10n.fuelTrafficHelpTitle,
                    helpBody: L10n.fuelTrafficHelpBody
                )
            )
        }
        if trip.fuelMeasurementSource == .userMeasured,
           let measured = trip.measuredFuelConsumptionPer100,
           let measuredText = FuelCostCalculator.formatRatePer100(measured, isElectric: isElectric) {
            items.append(
                TripSummaryMetric(
                    id: "measuredFuel",
                    icon: "gauge.with.dots.needle.67percent",
                    title: L10n.measuredFuel,
                    kind: .measuredFuel(detail: measuredText),
                    helpTitle: L10n.measuredFuelHelpTitle,
                    helpBody: L10n.measuredFuelHelpBody
                )
            )
        }
        return items
    }

    var fuelFactorKinds: [FuelFactorKind] {
        Self.factors(for: trip)
    }

    static func factors(for trip: Trip) -> [FuelFactorKind] {
        let base = (trip.fuelConsumptionPer100 ?? 0) * trip.distanceMeters / 100_000
        let threshold = max(0.0001, abs(base) * 0.05)
        var ranked: [(FuelFactorKind, Double)] = []
        if let cold = trip.fuelColdStartVolume, cold >= threshold {
            ranked.append((.coldStart, cold))
        }
        if let idle = trip.fuelIdleVolume, idle >= threshold {
            ranked.append((.idleTraffic, idle))
        }
        if let transient = trip.fuelTransientVolume, transient >= threshold {
            ranked.append((.transientAcceleration, transient))
        }
        if let speed = trip.fuelSpeedDeltaVolume {
            if speed >= threshold {
                let kind: FuelFactorKind = (trip.fuelTrafficScore ?? 0) >= 0.33
                    ? .lowSpeed
                    : .highSpeed
                ranked.append((kind, speed))
            } else if speed <= -threshold {
                ranked.append((.steadyEfficientSpeed, -speed))
            }
        }
        return Array(ranked.sorted { $0.1 > $1.1 }.prefix(4).map(\.0))
    }

    /// Litres or kWh implied by cost ÷ unit price, plus optional stored volume/rate.
    private func fuelDetail(
        cost: Double,
        volume: Double?,
        rate: Double?,
        isElectric: Bool
    ) -> String? {
        var parts: [String] = []
        if let volume, let text = FuelCostCalculator.formatVolumeAmount(volume, isElectric: isElectric) {
            parts.append(text)
        } else if let fallback = fuelVolumeText(cost: cost) {
            parts.append(fallback)
        }
        if let rate, trip.distanceMeters >= 200,
           let text = FuelCostCalculator.formatRatePer100(rate, isElectric: isElectric) {
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func fuelVolumeText(cost: Double) -> String? {
        FuelCostCalculator.formatVolume(
            cost: cost,
            unitPrice: FuelCostCalculator.resolvedUnitPrice(
                tripUnitPrice: trip.fuelUnitPrice,
                vehicle: trip.vehicle
            ),
            isElectric: (trip.fuelTypeSnapshot ?? trip.vehicle?.fuelType) == .electric
        )
    }

    /// Prepared display samples when available; empty while the async path is still loading.
    var routeSamples: [RouteSample] {
        (displayPieces ?? []).flatMap { $0 }
    }

    /// How many points actually reach the renderer. Reveal animation thresholds use this
    /// rather than the raw recorded count, which is now unbounded.
    var displayPointCount: Int {
        if let cached = Self.speedSegmentCache[trip.id], cached.fingerprint == routeFingerprint {
            return cached.displayPointCount
        }
        return (displayPieces ?? []).reduce(0) { $0 + $1.count }
    }

    var speedColoredSegments: [SpeedColoredSegment] {
        guard let pieces = displayPieces else { return [] }
        if let cached = Self.speedSegmentCache[trip.id], cached.fingerprint == routeFingerprint {
            return cached.segments
        }

        let segments = SpeedColoredSegmentBuilder.build(pieces: pieces)
        Self.speedSegmentCache[trip.id] = SpeedSegmentCacheEntry(
            fingerprint: routeFingerprint,
            displayPointCount: pieces.reduce(0) { $0 + $1.count },
            segments: segments
        )
        return segments
    }

    /// Speed-colored segments truncated to `progress` (0...1) for route draw-on.
    /// Uses the prepared segments — never re-runs decimation or recoloring.
    func revealedSpeedColoredSegments(progress: Double) -> [SpeedColoredSegment] {
        SpeedColoredSegmentBuilder.revealed(segments: speedColoredSegments, progress: progress)
    }

    func revealedFallbackCoordinates(progress: Double) -> [CLLocationCoordinate2D] {
        let path = displayCoordinates
        guard path.count >= 2 else { return [] }
        return RoutePathReveal.prefix(path, progress: progress)
    }

    func annotationRevealProgress(forStopAt coordinate: CLLocationCoordinate2D) -> Double {
        let path = displayCoordinates
        guard path.count >= 2 else { return 1 }
        return RoutePathReveal.progress(nearestTo: coordinate, in: path)
    }

    func followRegion(
        progress: Double,
        fit: MapFitContext = .cinematicReveal
    ) -> MKCoordinateRegion? {
        let path = displayCoordinates
        guard let tip = RoutePathReveal.tip(of: path, progress: progress) else { return nil }
        guard let settled = mapRegion(fit: fit) else { return nil }

        // Follow a bit tighter than the final fit early on, then ease out to the settled span.
        let blend = min(1, max(0, (progress - 0.55) / 0.45))
        let followFactor = 0.72 + (0.28 * blend)
        return MKCoordinateRegion(
            center: tip,
            span: MKCoordinateSpan(
                latitudeDelta: settled.span.latitudeDelta * followFactor,
                longitudeDelta: settled.span.longitudeDelta * followFactor
            )
        )
    }

    /// High-altitude opening look — route as a small silhouette below.
    func cinematicOpeningCamera(fit: MapFitContext = .cinematicReveal) -> MapCamera? {
        guard let settled = mapRegion(fit: fit) else { return nil }
        let path = displayCoordinates
        let center = path.first ?? settled.center
        return MapCamera(
            centerCoordinate: center,
            distance: cameraDistance(for: settled.span, multiplier: 4.6),
            heading: initialHeading(of: path),
            pitch: 58
        )
    }

    /// Dive + follow the drawing tip; pitch and altitude ease toward the settle pose.
    func cinematicFollowCamera(
        routeProgress: Double,
        fit: MapFitContext = .cinematicReveal
    ) -> MapCamera? {
        let path = displayCoordinates
        guard let tip = RoutePathReveal.tip(of: path, progress: routeProgress) else { return nil }
        guard let settled = mapRegion(fit: fit) else { return nil }

        let p = min(1, max(0, routeProgress))
        let ease = 1 - pow(1 - p, 1.65)
        let distance = cameraDistance(
            for: settled.span,
            multiplier: 4.6 - (3.35 * ease)
        )
        let pitch = 58 - (48 * ease)
        let lookAhead = RoutePathReveal.tip(of: path, progress: min(1, p + 0.04)) ?? tip
        return MapCamera(
            centerCoordinate: tip,
            distance: distance,
            heading: Self.bearing(from: tip, to: lookAhead),
            pitch: pitch
        )
    }

    private func cameraDistance(for span: MKCoordinateSpan, multiplier: Double) -> CLLocationDistance {
        let metersAcross = max(span.latitudeDelta, span.longitudeDelta) * 111_320
        return max(320, metersAcross * multiplier)
    }

    private func initialHeading(of path: [CLLocationCoordinate2D]) -> CLLocationDirection {
        guard path.count >= 2 else { return 0 }
        return Self.bearing(from: path[0], to: path[min(path.count - 1, max(1, path.count / 8))])
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    func mapRegion(fit: MapFitContext = .detailWithPanel) -> MKCoordinateRegion? {
        let path = displayCoordinates
        if path.count >= 2 {
            return Self.regionFitting(coordinates: path, fit: fit)
        }
        let endpoints = [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        guard !endpoints.isEmpty else { return nil }
        return Self.regionFitting(coordinates: endpoints, fit: fit)
    }

    /// Live layout fit — uses map pixel size + edge padding (nav, panel, legend).
    func mapRegion(
        mapSize: CGSize,
        edgePadding: UIEdgeInsets,
        margin: Double = 1.2
    ) -> MKCoordinateRegion? {
        let path = displayCoordinates
        if path.count >= 2 {
            return Self.regionFitting(
                coordinates: path,
                mapSize: mapSize,
                edgePadding: edgePadding,
                margin: margin
            )
        }
        let endpoints = [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        guard !endpoints.isEmpty else { return nil }
        return Self.regionFitting(
            coordinates: endpoints,
            mapSize: mapSize,
            edgePadding: edgePadding,
            margin: margin
        )
    }

    /// Pixel-accurate fit: route centered in the map view after `edgePadding` (nav + panel + legend).
    static func regionFitting(
        coordinates: [CLLocationCoordinate2D],
        mapSize: CGSize,
        edgePadding: UIEdgeInsets,
        margin: Double = 1.2
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first,
              mapSize.width > 1,
              mapSize.height > 1
        else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        // Build route map-rect ( Mercator ).
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        var routeRect = MKMapRect(
            x: min(nw.x, se.x),
            y: min(nw.y, se.y),
            width: max(abs(nw.x - se.x), 1),
            height: max(abs(nw.y - se.y), 1)
        )
        // ~180 m floor in map points at mid-latitude.
        let minMeters: CLLocationDistance = 180
        let metersPerPoint = MKMetersPerMapPointAtLatitude(midLat)
        let minPoints = minMeters / max(metersPerPoint, 1e-6)
        if routeRect.size.width < minPoints {
            routeRect = routeRect.insetBy(dx: -(minPoints - routeRect.size.width) / 2, dy: 0)
        }
        if routeRect.size.height < minPoints {
            routeRect = routeRect.insetBy(dx: 0, dy: -(minPoints - routeRect.size.height) / 2)
        }

        let usable = TripDetailMapFraming.usableSize(mapSize: mapSize, edgePadding: edgePadding)
        let visibleCenter = TripDetailMapFraming.visibleCenter(mapSize: mapSize, edgePadding: edgePadding)

        // Map points per view point so the route fills the usable rect.
        let scale = max(
            routeRect.size.width / Double(usable.width),
            routeRect.size.height / Double(usable.height)
        ) * margin

        let fullWidth = scale * mapSize.width
        let fullHeight = scale * mapSize.height

        let routeCenter = MKMapPoint(CLLocationCoordinate2D(latitude: midLat, longitude: midLon))

        // Place route center at the visible-rect center (not the full map center).
        let mapCenterX = routeCenter.x + (0.5 - Double(visibleCenter.x / mapSize.width)) * fullWidth
        let mapCenterY = routeCenter.y + (0.5 - Double(visibleCenter.y / mapSize.height)) * fullHeight

        let fitted = MKMapRect(
            x: mapCenterX - fullWidth / 2,
            y: mapCenterY - fullHeight / 2,
            width: fullWidth,
            height: fullHeight
        )
        return MKCoordinateRegion(fitted)
    }

    /// Fractional-inset wrapper (tests + callers without a live layout size).
    static func regionFitting(
        coordinates: [CLLocationCoordinate2D],
        fit: MapFitContext
    ) -> MKCoordinateRegion? {
        let size = CGSize(width: 390, height: 844)
        let padding = UIEdgeInsets(
            top: fit.top * size.height,
            left: fit.horizontal * size.width,
            bottom: fit.bottom * size.height,
            right: fit.horizontal * size.width
        )
        return regionFitting(
            coordinates: coordinates,
            mapSize: size,
            edgePadding: padding
        )
    }

    /// Flat MapCamera distance that frames `region` without pitch.
    static func cameraDistance(for region: MKCoordinateRegion) -> CLLocationDistance {
        let metersAcross = max(region.span.latitudeDelta, region.span.longitudeDelta) * 111_320
        return max(400, metersAcross * 1.55)
    }

    static func speedColor(for speedMps: Double?) -> Color {
        SpeedBand.initial(kmh: (speedMps ?? 0) * 3.6).color
    }
}

/// Visible-map insets for one trip-detail posture. The route is centered in what
/// remains after the card, side tab, or trailing panel.
struct TripDetailMapFraming: Equatable, Sendable {
    enum Posture: Equatable, Sendable {
        /// Phone portrait and the upright Duo sheet.
        case sheet
        /// Landscape phone: bottom card, map under the side tab.
        case phoneLandscape
        /// Open Duo landscape: the map is the trailing pane.
        case duoSplit
        /// iPad landscape: 380 pt panel on the trailing side.
        case padTrailing
        /// iPad portrait: the map pane is already just the map.
        case stacked
        /// In-place full-screen map.
        case expanded
    }

    struct Input: Equatable, Sendable {
        var posture: Posture
        var mapSize: CGSize
        var topChrome: CGFloat
        var bottomCardHeight: CGFloat
        var trailingCover: CGFloat
        var leadingInset: CGFloat
        var homeIndicator: CGFloat
    }

    /// Speed legend and pin labels above a bottom card.
    static let legendAndPins: CGFloat = 56
    /// `regionFitting` will not squeeze the route into a thinner strip than this.
    static let minimumUsable: CGFloat = 48
    static let expandedStylePicker: CGFloat = 52
    static let expandedLegend: CGFloat = 36

    static func edgeInsets(_ input: Input) -> UIEdgeInsets {
        let width = max(input.mapSize.width, 1)
        switch input.posture {
        case .expanded:
            let horizontal = max(width * 0.08, 24)
            let top = max(input.topChrome, 96) + expandedStylePicker
            let bottom = max(input.homeIndicator + 49, 83) + expandedLegend
            return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
        case .duoSplit:
            let horizontal = max(width * 0.06, 16)
            let top = max(input.topChrome, 54)
            let bottom = max(input.homeIndicator, 12)
            return UIEdgeInsets(
                top: top,
                left: horizontal,
                bottom: bottom,
                right: horizontal + max(input.trailingCover, 0)
            )
        case .stacked:
            let horizontal = max(width * 0.06, 16)
            return UIEdgeInsets(top: 16, left: horizontal, bottom: 16, right: horizontal)
        case .padTrailing:
            let horizontal = max(width * 0.06, 16)
            let top = max(input.topChrome, 96)
            let bottom = max(input.bottomCardHeight, 0) + legendAndPins
            let right = horizontal + GlassTokens.floatingPanelWidth + GlassTokens.panelHorizontalInset
            return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: right)
        case .phoneLandscape:
            let horizontal = max(width * 0.06, 16)
            let top = max(input.topChrome, 96)
            let bottom = max(input.bottomCardHeight, 0) + legendAndPins
            return UIEdgeInsets(
                top: top,
                left: horizontal,
                bottom: bottom,
                right: horizontal + max(input.trailingCover, 0)
            )
        case .sheet:
            let horizontal = max(width * 0.06, 16)
            let top = max(input.topChrome, 96)
            let bottom = max(input.bottomCardHeight, 0) + legendAndPins
            return UIEdgeInsets(
                top: top,
                left: horizontal + max(input.leadingInset, 0),
                bottom: bottom,
                right: horizontal + max(input.trailingCover, 0)
            )
        }
    }

    static func usableSize(mapSize: CGSize, edgePadding: UIEdgeInsets) -> CGSize {
        CGSize(
            width: max(mapSize.width - edgePadding.left - edgePadding.right, minimumUsable),
            height: max(mapSize.height - edgePadding.top - edgePadding.bottom, minimumUsable)
        )
    }

    static func visibleCenter(mapSize: CGSize, edgePadding: UIEdgeInsets) -> CGPoint {
        let usable = usableSize(mapSize: mapSize, edgePadding: edgePadding)
        return CGPoint(
            x: edgePadding.left + usable.width / 2,
            y: edgePadding.top + usable.height / 2
        )
    }
}

/// Where the route midpoint lands inside a fitted region, as a fraction of the map view.
enum TripDetailMapProjection {
    static func fraction(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> CGPoint {
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let northWest = MKMapPoint(
            CLLocationCoordinate2D(
                latitude: region.center.latitude + halfLat,
                longitude: region.center.longitude - halfLon
            )
        )
        let southEast = MKMapPoint(
            CLLocationCoordinate2D(
                latitude: region.center.latitude - halfLat,
                longitude: region.center.longitude + halfLon
            )
        )
        let rect = MKMapRect(
            x: min(northWest.x, southEast.x),
            y: min(northWest.y, southEast.y),
            width: max(abs(southEast.x - northWest.x), 1),
            height: max(abs(southEast.y - northWest.y), 1)
        )
        let point = MKMapPoint(coordinate)
        return CGPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }
}

/// Decides when a trip-detail camera fit is owed. A turn never writes the camera;
/// the owed fit waits until the turn is actually over.
struct TripDetailCameraSettle: Equatable, Sendable {
    typealias Frame = TripDetailMapFraming.Input

    struct State: Equatable, Sendable {
        var rotating = false
        var frame: Frame?
        var owed = false
        var fits: [Frame] = []
    }

    enum Action: Equatable, Sendable {
        case none
        case waitForQuiet
        case fit(Frame)
    }

    static func reduce(
        _ state: inout State,
        layout frame: Frame,
        rotating: Bool,
        looksLikeTurn: Bool
    ) -> Action {
        let changed = state.frame != frame
        state.frame = frame
        state.rotating = rotating
        if rotating {
            state.owed = true
            return .none
        }
        if looksLikeTurn {
            state.owed = true
            return .waitForQuiet
        }
        guard changed || state.owed else { return .none }
        state.owed = true
        return .waitForQuiet
    }

    static func reduceTurnFlag(_ state: inout State, rotating: Bool) -> Action {
        state.rotating = rotating
        guard !rotating, state.owed, state.frame != nil else { return .none }
        return .waitForQuiet
    }

    /// The quiet beat ended. A turn that is still going keeps the fit owed.
    static func reduceQuietElapsed(_ state: inout State, stillRotating: Bool) -> Action {
        if stillRotating || state.rotating {
            state.rotating = true
            state.owed = true
            return .none
        }
        guard state.owed, let frame = state.frame else { return .none }
        state.owed = false
        state.fits.append(frame)
        return .fit(frame)
    }

    static func reduceRequest(_ state: inout State, frame: Frame, rotating: Bool) -> Action {
        state.frame = frame
        state.rotating = rotating
        state.owed = true
        return rotating ? .none : .waitForQuiet
    }
}

/// Skips a camera write that would not move the route on screen.
enum TripDetailCameraMotion {
    static let minimumCenterShift: CGFloat = 2
    static let minimumSpanChange = 0.02

    static func shouldWrite(
        current: MKCoordinateRegion,
        proposed: MKCoordinateRegion,
        mapSize: CGSize
    ) -> Bool {
        let latSpan = max(current.span.latitudeDelta, 1e-8)
        let lonSpan = max(current.span.longitudeDelta, 1e-8)
        let pointsPerLat = mapSize.height / latSpan
        let pointsPerLon = mapSize.width / lonSpan
        let dy = abs(proposed.center.latitude - current.center.latitude) * pointsPerLat
        let dx = abs(proposed.center.longitude - current.center.longitude) * pointsPerLon
        if dx > minimumCenterShift || dy > minimumCenterShift { return true }
        let latitudeChange = abs(proposed.span.latitudeDelta - current.span.latitudeDelta) / latSpan
        let longitudeChange = abs(proposed.span.longitudeDelta - current.span.longitudeDelta) / lonSpan
        return latitudeChange > minimumSpanChange || longitudeChange > minimumSpanChange
    }
}
