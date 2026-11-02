import QuartzCore
import SwiftUI
import UIKit

/// `TimelineView` (animation *or* periodic) does not tick inside a SwiftUI `List`.
/// iOS pauses those clocks, which froze the recording road. This CADisplayLink
/// keeps running in a list cell.
struct TrailhoundDisplayLinkTicker: UIViewRepresentable {
    var isRunning: Bool
    var framesPerSecond: Int
    var onTick: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTick: onTick)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        context.coordinator.install(framesPerSecond: framesPerSecond, running: isRunning)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTick = onTick
        context.coordinator.install(framesPerSecond: framesPerSecond, running: isRunning)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        var onTick: (TimeInterval) -> Void
        private var link: CADisplayLink?

        init(onTick: @escaping (TimeInterval) -> Void) {
            self.onTick = onTick
        }

        func install(framesPerSecond: Int, running: Bool) {
            let fps = max(8, min(60, framesPerSecond))
            if link == nil {
                let created = CADisplayLink(target: self, selector: #selector(step(_:)))
                created.add(to: .main, forMode: .common)
                link = created
            }
            let preferred = Float(fps)
            link?.preferredFrameRateRange = CAFrameRateRange(
                minimum: max(8, preferred / 2),
                maximum: preferred,
                preferred: preferred
            )
            link?.isPaused = !running
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc func step(_ link: CADisplayLink) {
            // A live redraw during the rotation snapshot paints a second copy of the road.
            if TrailhoundInterfaceRotation.pausesRoadAnimation { return }
            let time = Date.timeIntervalSinceReferenceDate
            onTick(time)
        }
    }
}

/// Drops the flattened road bitmap while the interface is rotating so the car
/// redraws in the new bounds instead of stretching the previous frame.
private struct RoadSceneRasterizer: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup(opaque: false, colorMode: .linear)
        } else {
            content
        }
    }
}

/// Still used by recap / onboarding (not inside a `List` row).
enum TrailhoundIndependentClock {
    static let pausedInterval: TimeInterval = 86_400

    static func periodic(interval: TimeInterval, paused: Bool = false) -> PeriodicTimelineSchedule {
        .periodic(from: .now, by: paused ? pausedInterval : interval)
    }
}

struct RecordingCarAnimationView<CarOverlay: View>: View {
    var compact: Bool = false
    /// When true, the road clock ticks. Independent of pause.
    var isAnimating: Bool = true
    /// Freeze dashes / smoke / bounce and show the pause badge — does not tear down the clock.
    var isPaused: Bool = false
    /// 0 = car off-screen left, 1 = settled driving position.
    var driveInProgress: CGFloat = 1
    /// Side-profile SF Symbol fallback; default is the fixed right-facing car.
    var systemImage: String? = nil
    /// Pre-decoded thumb from the app target — never load from disk here (per-frame hot path).
    var vehiclePhoto: UIImage? = nil
    /// `scaleEffect(x:)` for the symbol so it faces right. Default `-1` matches `car.side.fill`.
    var symbolScaleX: CGFloat = -1
    /// Compact notification / list cards skip the sin bounce (avoids pause/resume bounce-in/out).
    var allowsVerticalBounce: Bool = true
    @ViewBuilder var carOverlay: (TrailhoundRoadSceneLayout) -> CarOverlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = Date.timeIntervalSinceReferenceDate

    private var metrics: TrailhoundRoadSceneMetrics { compact ? .compact : .regular }
    /// Keep the same view tree on pause/resume — only freeze the clock when not animating.
    private var shouldRunClock: Bool { isAnimating && !reduceMotion }
    private var ticksRoad: Bool { shouldRunClock && !isPaused }
    private var framesPerSecond: Int {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 12 }
        return compact ? 15 : 30
    }

    /// Remount when the mark asset changes. Pause/resume keeps the same id (no swap jank);
    /// vehicle photo swaps must bust `drawingGroup` caches.
    private var markIdentity: String {
        if let vehiclePhoto {
            return "photo-\(ObjectIdentifier(vehiclePhoto))"
        }
        return "symbol-\(systemImage ?? "car.side.fill")"
    }

    var body: some View {
        RoadSceneDriver(
            liveTime: clock,
            shouldAnimate: ticksRoad,
            isPaused: isPaused,
            metrics: metrics,
            driveInProgress: driveInProgress,
            showsPauseBadge: true,
            systemImage: systemImage,
            vehiclePhoto: vehiclePhoto,
            symbolScaleX: symbolScaleX,
            allowsVerticalBounce: allowsVerticalBounce,
            carOverlay: carOverlay
        )
        .id(markIdentity)
        // Extra top chrome so service badge can sit above the mark without shrinking photos.
        .frame(height: TrailhoundRoadVehicleMarkLayout.sceneFrameHeight(for: metrics))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10))
        // Flatten only the road pixels. Keep the display-link host *outside* this
        // rasterizer — `drawingGroup` does not mount `UIViewRepresentable` children,
        // which is why a ticker in `.background` never fired and the car sat still.
        // While the window turns, a frozen raster stretches with the new bounds.
        .modifier(RoadSceneRasterizer(enabled: !TrailhoundInterfaceRotation.shared.isRotating))
        .overlay(alignment: .topLeading) {
            TrailhoundDisplayLinkTicker(
                isRunning: ticksRoad,
                framesPerSecond: framesPerSecond
            ) { clock = $0 }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }
}

extension RecordingCarAnimationView where CarOverlay == EmptyView {
    init(
        compact: Bool = false,
        isAnimating: Bool = true,
        isPaused: Bool = false,
        driveInProgress: CGFloat = 1,
        systemImage: String? = nil,
        vehiclePhoto: UIImage? = nil,
        symbolScaleX: CGFloat = -1,
        allowsVerticalBounce: Bool = true
    ) {
        self.compact = compact
        self.isAnimating = isAnimating
        self.isPaused = isPaused
        self.driveInProgress = driveInProgress
        self.systemImage = systemImage
        self.vehiclePhoto = vehiclePhoto
        self.symbolScaleX = symbolScaleX
        self.allowsVerticalBounce = allowsVerticalBounce
        self.carOverlay = { _ in EmptyView() }
    }
}

/// Shared sizing for recording + onboarding road scenes.
struct TrailhoundRoadSceneMetrics: Equatable {
    var sceneHeight: CGFloat
    var roadHeight: CGFloat
    var carSize: CGFloat
    var cornerRadius: CGFloat
    var settledXFraction: CGFloat

    static let compact = TrailhoundRoadSceneMetrics(
        sceneHeight: 44,
        roadHeight: 18,
        carSize: 22,
        cornerRadius: 8,
        settledXFraction: 0.58
    )

    static let regular = TrailhoundRoadSceneMetrics(
        sceneHeight: 80,
        roadHeight: 30,
        carSize: 36,
        cornerRadius: 10,
        settledXFraction: 0.58
    )

    static let hero = TrailhoundRoadSceneMetrics(
        sceneHeight: 140,
        roadHeight: 28,
        carSize: 44,
        cornerRadius: 16,
        settledXFraction: 0.5
    )

    static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }
}

struct TrailhoundRoadSceneLayout: Equatable {
    var size: CGSize
    var carCenter: CGPoint
    var carSize: CGFloat
    /// Drawn mark size (cutout/opaque photos can be larger than `carSize`).
    var markSize: CGFloat
    var roadHeight: CGFloat
    var driveEased: CGFloat
    var isPaused: Bool
}

/// How the vehicle mark is drawn on the road — opaque plates use a different sit-on-road layout.
enum TrailhoundRoadVehicleMarkKind: Equatable, Sendable {
    case symbol
    case cutoutPhoto
    case opaquePhoto
}

struct TrailhoundRoadVehicleMarkPlacement: Equatable, Sendable {
    var size: CGFloat
    var centerY: CGFloat
}

/// Pure geometry for road marks. Safe to call from TimelineView ticks (no pixel I/O).
enum TrailhoundRoadVehicleMarkLayout {
    /// Slight sink into the road so opaque plates feel grounded.
    static let opaqueRoadOverlap: CGFloat = 3

    /// Coverage below this (with real alpha) → cutout layout; at/above → opaque plate.
    static let cutoutMaxOpaqueCoverage: Double = 0.92

    /// Matches road-scene vertical bounce amplitude (`sin * 1.2`).
    static let bounceAmplitude: CGFloat = 1.2

    /// Top padding inside the clipped road scene.
    static let sceneTopInset: CGFloat = 2

    /// Space above the road band so the service badge can sit on top of the mark (not under a clip).
    static func overlayChromeHeadroom(for carSize: CGFloat) -> CGFloat {
        let diameter = max(15 as CGFloat, carSize * 0.68)
        return carSize * 0.48 + diameter * 0.5 + sceneTopInset + bounceAmplitude
    }

    /// Full road-view height: road metrics + top chrome (badge lives above the mark).
    static func sceneFrameHeight(for metrics: TrailhoundRoadSceneMetrics) -> CGFloat {
        metrics.sceneHeight + overlayChromeHeadroom(for: metrics.carSize)
    }

    static func photoSize(for kind: TrailhoundRoadVehicleMarkKind, metrics: TrailhoundRoadSceneMetrics) -> CGFloat {
        let carSize = metrics.carSize
        switch kind {
        case .symbol:
            return carSize
        case .cutoutPhoto:
            // Photos read smaller than SF Symbols at the same point size — bump them up.
            return min(carSize * 3.0, metrics.sceneHeight * 1.18)
        case .opaquePhoto:
            // Full plate on the road — do not shrink for badge; chrome headroom is in sceneFrameHeight.
            return min(carSize * 1.65, metrics.sceneHeight * 0.72)
        }
    }

    static func placement(
        kind: TrailhoundRoadVehicleMarkKind,
        metrics: TrailhoundRoadSceneMetrics,
        roadTop: CGFloat,
        bounce: CGFloat
    ) -> TrailhoundRoadVehicleMarkPlacement {
        let carSize = metrics.carSize
        let size = photoSize(for: kind, metrics: metrics)
        switch kind {
        case .symbol, .cutoutPhoto:
            // Historical formula — cutouts rely on bottom alpha padding looking correct.
            let centerY = roadTop - carSize * 0.35 + bounce
            return TrailhoundRoadVehicleMarkPlacement(size: size, centerY: centerY)
        case .opaquePhoto:
            // Sit on the road (above the asphalt), full plate size.
            let centerY = roadTop - size * 0.5 + opaqueRoadOverlap + bounce
            return TrailhoundRoadVehicleMarkPlacement(size: size, centerY: centerY)
        }
    }

    /// Classify without pixel scan when `isCutout` is already known (cached off the animation clock).
    static func kind(hasPhoto: Bool, isCutout: Bool) -> TrailhoundRoadVehicleMarkKind {
        guard hasPhoto else { return .symbol }
        return isCutout ? .cutoutPhoto : .opaquePhoto
    }
}

/// Recording card = white car on dark road over brand glass.
/// Atmosphere = no road slab; brand car + flowing lane dashes on the shell (light/dark).
enum TrailhoundRoadScenePalette: Equatable {
    case recording
    case atmosphere
}

/// Procedural Trailhound road + car. Recording and onboarding share this DNA.
struct TrailhoundRoadDrivingScene<Overlay: View>: View {
    let time: TimeInterval
    var metrics: TrailhoundRoadSceneMetrics = .regular
    var palette: TrailhoundRoadScenePalette = .recording
    var isPaused: Bool = false
    var driveInProgress: CGFloat = 1
    var showsPauseBadge: Bool = false
    /// Side-profile SF Symbol fallback; default is the fixed right-facing car.
    var systemImage: String? = nil
    /// Pre-decoded vehicle thumb (app injects; no I/O on the animation clock).
    var vehiclePhoto: UIImage? = nil
    /// Resolved off the animation clock (cached). Default `.symbol` when no photo.
    var vehicleMarkKind: TrailhoundRoadVehicleMarkKind = .symbol
    /// Symbol horizontal scale so the vehicle faces right (`-1` for left-facing SF side cars).
    var symbolScaleX: CGFloat = -1
    var allowsVerticalBounce: Bool = true
    /// Atmosphere car / dash / smoke accent. Nil keeps the legacy sky brand blue.
    var accentColor: Color? = nil
    @ViewBuilder var overlay: (_ layout: TrailhoundRoadSceneLayout) -> Overlay

    @Environment(\.colorScheme) private var colorScheme

    private var atmosphereAccent: Color {
        accentColor ?? TrailhoundBrandColors.brandBottom
    }

    /// Lane band height used for car/dash layout (atmosphere has no filled road).
    private var laneBandHeight: CGFloat {
        palette == .atmosphere ? max(12, metrics.roadHeight * 0.45) : metrics.roadHeight
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let symbolSize = metrics.carSize
            let roadHeight = laneBandHeight
            let settledX = width * metrics.settledXFraction
            let startX = -symbolSize * 0.8
            let eased = TrailhoundRoadSceneMetrics.easeOutCubic(min(1, max(0, driveInProgress)))
            let carCenterX = startX + (settledX - startX) * eased
            let roadTop = height - roadHeight
            let bounce: CGFloat = {
                guard allowsVerticalBounce, !isPaused else { return 0 }
                return sin(time * 8) * 1.2
            }()
            let markKind = vehiclePhoto == nil ? TrailhoundRoadVehicleMarkKind.symbol : vehicleMarkKind
            let placement = TrailhoundRoadVehicleMarkLayout.placement(
                kind: markKind,
                metrics: metrics,
                roadTop: roadTop,
                bounce: bounce
            )
            let carCenter = CGPoint(x: carCenterX, y: placement.centerY)
            let carOpacity = Double(0.35 + 0.65 * eased)
            // Overlay chrome (service badge, etc.) scales from symbol size — never cutout
            // photoSize (~3×), which would make badges overflow the road scene.
            let layout = TrailhoundRoadSceneLayout(
                size: geo.size,
                carCenter: carCenter,
                carSize: symbolSize,
                markSize: placement.size,
                roadHeight: roadHeight,
                driveEased: eased,
                isPaused: isPaused
            )

            ZStack(alignment: .bottom) {
                if palette == .recording {
                    roadSurface(width: width, roadHeight: roadHeight)
                }
                laneMarkings(
                    width: width,
                    roadHeight: roadHeight,
                    carCenterX: carCenterX,
                    carSize: placement.size
                )
                exhaustSmoke(
                    originX: carCenterX - placement.size * 0.48,
                    originY: placement.centerY + placement.size * 0.08,
                    strength: eased
                )
                carIcon(center: carCenter, markSize: placement.size, opacity: carOpacity)

                if showsPauseBadge, isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: symbolSize * 0.65, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.95))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(x: carCenterX, y: placement.centerY)
                }

                overlay(layout)
            }
        }
    }

    private func roadSurface(width: CGFloat, roadHeight: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(isPaused ? 0.16 : 0.22),
                        Color.black.opacity(isPaused ? 0.28 : 0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: roadHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(isPaused ? 0.2 : 0.35))
                    .frame(height: 2)
            }
    }

    private func laneMarkings(
        width: CGFloat,
        roadHeight: CGFloat,
        carCenterX: CGFloat,
        carSize: CGFloat
    ) -> some View {
        let dashWidth: CGFloat = palette == .atmosphere ? 18 : 22
        let dashSpacing: CGFloat = palette == .atmosphere ? 16 : 18
        let patternLength = dashWidth + dashSpacing
        let scrollSpeed: CGFloat = 90
        // `time` is already frozen by RoadSceneDriver when paused — keep last offset, don't snap to 0.
        let offset = -CGFloat(time.truncatingRemainder(dividingBy: Double(patternLength / scrollSpeed))) * scrollSpeed
        // +2 dashes on the left and +2 on the right vs the base fill count.
        let baseCount = max(0, Int(width / patternLength) + 6)
        let leadingExtra = 2
        let trailingExtra = 2
        let firstIndex = -2 - leadingExtra
        let dashCount = baseCount + trailingExtra
        let dashColor: Color = {
            switch palette {
            case .recording:
                return Color.white.opacity(isPaused ? 0.45 : 0.85)
            case .atmosphere:
                return Color.white.opacity(isPaused ? 0.7 : 1)
            }
        }()
        let dashHeight: CGFloat = palette == .atmosphere ? 2.5 : 3
        // Symmetric gap under the car so left/right dash runs stay balanced.
        let carHalf = carSize * 0.58
        let carLeading = carCenterX - carHalf
        let carTrailing = carCenterX + carHalf

        return ZStack(alignment: .leading) {
            if dashCount > firstIndex {
                ForEach(firstIndex..<dashCount, id: \.self) { index in
                    let x = offset + CGFloat(index) * patternLength
                    let dashLeading = x
                    let dashTrailing = x + dashWidth
                    let underCar = palette == .atmosphere
                        && dashTrailing > carLeading
                        && dashLeading < carTrailing
                    if !underCar {
                        if palette == .atmosphere {
                            Capsule()
                                .fill(dashColor)
                                .frame(width: dashWidth, height: dashHeight)
                                .offset(x: x)
                        } else {
                            Capsule()
                                .fill(dashColor)
                                .frame(width: dashWidth, height: dashHeight)
                                .offset(x: x)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: roadHeight, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .offset(y: palette == .atmosphere ? -roadHeight * 0.15 : -roadHeight * 0.38)
        .mask {
            if palette == .atmosphere {
                // Symmetric soft fade so the stripe run reads centered with the car.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.08),
                        .init(color: .white, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: roadHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Rectangle()
                    .frame(height: roadHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func carIcon(center: CGPoint, markSize: CGFloat, opacity: Double) -> some View {
        let carColor: Color = {
            switch palette {
            case .recording:
                return .white.opacity(isPaused ? 0.75 : opacity)
            case .atmosphere:
                return Color.white.opacity(isPaused ? 0.75 : 1)
            }
        }()
        let shadowColor: Color = palette == .atmosphere
            ? atmosphereAccent.opacity(colorScheme == .dark ? 0.35 : 0.2)
            : Color.black.opacity(0.25)
        let shadowRadius: CGFloat = palette == .atmosphere ? 8 : 3

        return Group {
            if let vehiclePhoto {
                Image(uiImage: vehiclePhoto)
                    .resizable()
                    .scaledToFit()
                    .frame(width: markSize, height: markSize)
                    .opacity(isPaused ? 0.75 : 1)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            } else if palette == .atmosphere {
                Image(systemName: systemImage ?? "car.side.fill")
                    .font(.system(size: metrics.carSize, weight: .semibold))
                    .foregroundStyle(carColor)
                    .symbolRenderingMode(.monochrome)
                    .scaleEffect(x: symbolScaleX, y: 1)
            } else {
                Image(systemName: systemImage ?? "car.side.fill")
                    .font(.system(size: metrics.carSize, weight: .semibold))
                    .foregroundStyle(carColor)
                    .symbolRenderingMode(.monochrome)
                    // Face right — symbols only; never mirror a photo.
                    .scaleEffect(x: symbolScaleX, y: 1)
                    .shadow(color: shadowColor, radius: shadowRadius, y: 2)
            }
        }
        .frame(width: markSize, height: markSize)
        .position(x: center.x, y: center.y)
    }

    private func exhaustSmoke(originX: CGFloat, originY: CGFloat, strength: CGFloat) -> some View {
        Group {
            if !isPaused, strength > 0.2 {
                ZStack {
                    ForEach(0..<7, id: \.self) { index in
                        smokePuff(
                            originX: originX,
                            originY: originY,
                            index: index,
                            cycle: 1.1,
                            stagger: 0.16,
                            strength: strength
                        )
                    }
                }
            }
        }
    }

    private func smokePuff(
        originX: CGFloat,
        originY: CGFloat,
        index: Int,
        cycle: Double,
        stagger: Double,
        strength: CGFloat
    ) -> some View {
        let progress = (time + stagger * Double(index)).truncatingRemainder(dividingBy: cycle) / cycle
        let drift = CGFloat(progress)
        let size = 6 + drift * 14
        let x = originX - drift * 36 - CGFloat(index % 2) * 4
        let y = originY - drift * 22 + sin(progress * .pi) * 6
        let base = palette == .atmosphere ? 0.28 : 0.55
        let opacity = Double(1 - progress) * base * Double(strength)
        let smoke: Color = palette == .atmosphere
            ? atmosphereAccent.opacity(opacity)
            : Color.white.opacity(opacity)

        return Circle()
            .fill(smoke)
            .frame(width: size, height: size)
            .blur(radius: 1.5 + drift * 2)
            .position(x: x, y: y)
    }
}

extension TrailhoundRoadDrivingScene where Overlay == EmptyView {
    init(
        time: TimeInterval,
        metrics: TrailhoundRoadSceneMetrics = .regular,
        palette: TrailhoundRoadScenePalette = .recording,
        isPaused: Bool = false,
        driveInProgress: CGFloat = 1,
        showsPauseBadge: Bool = false,
        systemImage: String? = nil,
        vehiclePhoto: UIImage? = nil,
        vehicleMarkKind: TrailhoundRoadVehicleMarkKind = .symbol,
        symbolScaleX: CGFloat = -1,
        allowsVerticalBounce: Bool = true
    ) {
        self.time = time
        self.metrics = metrics
        self.palette = palette
        self.isPaused = isPaused
        self.driveInProgress = driveInProgress
        self.showsPauseBadge = showsPauseBadge
        self.systemImage = systemImage
        self.vehiclePhoto = vehiclePhoto
        self.vehicleMarkKind = vehicleMarkKind
        self.symbolScaleX = symbolScaleX
        self.allowsVerticalBounce = allowsVerticalBounce
        self.overlay = { _ in EmptyView() }
    }
}

private struct RoadSceneDriver<CarOverlay: View>: View {
    /// Live clock while animating; `nil` uses a frozen frame.
    let liveTime: TimeInterval?
    let shouldAnimate: Bool
    let isPaused: Bool
    let metrics: TrailhoundRoadSceneMetrics
    let driveInProgress: CGFloat
    let showsPauseBadge: Bool
    var systemImage: String? = nil
    var vehiclePhoto: UIImage? = nil
    var symbolScaleX: CGFloat = -1
    var allowsVerticalBounce: Bool = true
    @ViewBuilder var carOverlay: (TrailhoundRoadSceneLayout) -> CarOverlay

    @State private var frozenRoadTime: TimeInterval = Date.timeIntervalSinceReferenceDate
    /// Default cutout so the first frame matches historical large-photo layout until classify finishes.
    @State private var cachedMarkKind: TrailhoundRoadVehicleMarkKind = .cutoutPhoto

    private var sceneTime: TimeInterval {
        if shouldAnimate, let liveTime {
            return liveTime
        }
        return frozenRoadTime
    }

    private var markIdentity: ObjectIdentifier? {
        vehiclePhoto.map { ObjectIdentifier($0) }
    }

    private var resolvedMarkKind: TrailhoundRoadVehicleMarkKind {
        guard vehiclePhoto != nil else { return .symbol }
        // `.symbol` in cache only appears between photo clear and re-classify; keep cutout optimistic.
        return cachedMarkKind == .opaquePhoto ? .opaquePhoto : .cutoutPhoto
    }

    var body: some View {
        TrailhoundRoadDrivingScene(
            time: sceneTime,
            metrics: metrics,
            isPaused: isPaused,
            driveInProgress: driveInProgress,
            showsPauseBadge: showsPauseBadge,
            systemImage: systemImage,
            vehiclePhoto: vehiclePhoto,
            vehicleMarkKind: resolvedMarkKind,
            symbolScaleX: symbolScaleX,
            allowsVerticalBounce: allowsVerticalBounce,
            overlay: carOverlay
        )
        .frame(height: TrailhoundRoadVehicleMarkLayout.sceneFrameHeight(for: metrics))
        .task(id: markIdentity) {
            await classifyVehicleMark()
        }
        .onAppear {
            if let liveTime {
                frozenRoadTime = liveTime
            }
        }
        .onChange(of: shouldAnimate) { _, animating in
            if animating, let liveTime {
                frozenRoadTime = liveTime
            }
        }
        .onChange(of: liveTime) { _, newTime in
            if shouldAnimate, let newTime {
                frozenRoadTime = newTime
            }
        }
    }

    @MainActor
    private func classifyVehicleMark() async {
        guard let vehiclePhoto else {
            cachedMarkKind = .symbol
            return
        }
        // Optimistic cutout preserves historical large-photo layout until the scan finishes.
        cachedMarkKind = .cutoutPhoto
        let photo = vehiclePhoto
        let isCutout = await Task.detached(priority: .utility) {
            VehiclePhotoStore.isRoadCutoutMark(photo)
        }.value
        cachedMarkKind = isCutout ? .cutoutPhoto : .opaquePhoto
    }
}
