import SwiftUI

/// Vehicle Care wait (receipt reading, receipt photo loading): a magnifier sweeps over a car and
/// shows it enlarged as a tint outline inside the lens, above a drifting dashed road. Colors come from glass ink and
/// the shell palette tint only. Reduce Motion draws one still frame with the lens centered.
/// Decorative — the caller keeps the status text for VoiceOver.
struct VehicleInspectLoader: View {
    enum Size {
        /// Replaces an inline `ProgressView` next to a status label.
        case inline
        /// Centered in a large placeholder (photo loading).
        case hero
    }

    var size: Size = .inline

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweeping = false
    @State private var drifting = false

    private var metrics: VehicleInspectLoaderTokens.Metrics {
        VehicleInspectLoaderTokens.metrics(for: size)
    }

    var body: some View {
        let metrics = metrics
        let tint = shellPalette.tintColor(for: colorScheme)
        let animates = !reduceMotion

        ZStack {
            road(metrics: metrics, tint: tint, animates: animates)
            VehicleInspectStage(
                progress: animates ? (sweeping ? 1 : 0) : 0.5,
                metrics: metrics,
                carInk: GlassText.secondary(for: colorScheme),
                lensInk: GlassText.primary(for: colorScheme),
                tint: tint
            )
            .animation(
                animates ? MilehoundMotion.inspectSweep.repeatForever(autoreverses: true) : nil,
                value: sweeping
            )
        }
        .frame(width: metrics.width, height: metrics.height)
        .accessibilityHidden(true)
        .onAppear {
            sweeping = true
            drifting = true
        }
    }

    private func road(
        metrics: VehicleInspectLoaderTokens.Metrics,
        tint: Color,
        animates: Bool
    ) -> some View {
        let period = metrics.dashLength + metrics.dashGap
        let count = Int((metrics.width / period).rounded(.up)) + 2
        return HStack(spacing: metrics.dashGap) {
            ForEach(0..<count, id: \.self) { _ in
                Capsule()
                    .frame(width: metrics.dashLength, height: metrics.roadThickness)
            }
        }
        .foregroundStyle(tint.opacity(VehicleInspectLoaderTokens.roadOpacity))
        .fixedSize()
        .offset(x: animates && drifting ? -period : 0)
        .animation(
            animates ? MilehoundMotion.inspectRoadDrift.repeatForever(autoreverses: false) : nil,
            value: drifting
        )
        .frame(width: metrics.width, alignment: .leading)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, metrics.roadInset)
    }
}

enum VehicleInspectLoaderTokens {
    struct Metrics {
        let width: CGFloat
        let height: CGFloat
        let carPointSize: CGFloat
        /// Car center sits this far above the vertical middle so it rides on the road.
        let carLift: CGFloat
        let lensDiameter: CGFloat
        let ringWidth: CGFloat
        let handleLength: CGFloat
        let handleWidth: CGFloat
        /// Lens path sits this far below the car center, on the body between roof and sill.
        let lensDrop: CGFloat
        /// Lens center travels ±this from the car center.
        let sweepTravel: CGFloat
        /// Arc height at the middle of the sweep.
        let sweepLift: CGFloat
        let dashLength: CGFloat
        let dashGap: CGFloat
        let roadThickness: CGFloat
        let roadInset: CGFloat
    }

    static let zoom: CGFloat = 1.25
    static let roadOpacity: Double = 0.35
    /// Lens glass behind the enlarged outline car — near-opaque so the filled car under it does not show.
    static let lensFillOpacity: Double = 0.92

    static let inline = Metrics(
        width: 44, height: 28,
        carPointSize: 17, carLift: 2,
        lensDiameter: 15, ringWidth: 1.75,
        handleLength: 6, handleWidth: 2.25,
        lensDrop: 1, sweepTravel: 11, sweepLift: 2,
        dashLength: 5, dashGap: 3, roadThickness: 1.5, roadInset: 1
    )

    static let hero = Metrics(
        width: 160, height: 96,
        carPointSize: 54, carLift: 6,
        lensDiameter: 46, ringWidth: 3.5,
        handleLength: 16, handleWidth: 5.5,
        lensDrop: 4, sweepTravel: 36, sweepLift: 5,
        dashLength: 14, dashGap: 9, roadThickness: 3, roadInset: 6
    )

    static func metrics(for size: VehicleInspectLoader.Size) -> Metrics {
        switch size {
        case .inline: inline
        case .hero: hero
        }
    }
}

/// One frame of the sweep. `progress` 0…1 moves the lens left to right along a shallow arc;
/// `Animatable` so the arc is followed instead of a straight interpolation.
private struct VehicleInspectStage: View, Animatable {
    var progress: Double
    let metrics: VehicleInspectLoaderTokens.Metrics
    let carInk: Color
    let lensInk: Color
    let tint: Color

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let carCenter = CGPoint(x: metrics.width / 2, y: metrics.height / 2 - metrics.carLift)
        let lens = CGPoint(
            x: carCenter.x + metrics.sweepTravel * CGFloat(progress * 2 - 1),
            y: carCenter.y + metrics.lensDrop - metrics.sweepLift * CGFloat(sin(progress * .pi))
        )
        let radius = metrics.lensDiameter / 2
        let handleReach = radius + metrics.handleLength / 2 - metrics.ringWidth / 2
        let diagonal = CGFloat(0.5.squareRoot())

        ZStack {
            car(symbol: "car.side.fill", ink: carInk, center: carCenter)

            Circle()
                .fill(lensInk.opacity(VehicleInspectLoaderTokens.lensFillOpacity))
                .frame(width: metrics.lensDiameter, height: metrics.lensDiameter)
                .position(lens)

            car(symbol: "car.side", ink: tint, center: carCenter)
                .scaleEffect(
                    VehicleInspectLoaderTokens.zoom,
                    anchor: UnitPoint(x: lens.x / metrics.width, y: lens.y / metrics.height)
                )
                .mask {
                    Circle()
                        .frame(width: metrics.lensDiameter, height: metrics.lensDiameter)
                        .position(lens)
                }

            Capsule()
                .fill(tint)
                .frame(width: metrics.handleLength, height: metrics.handleWidth)
                .rotationEffect(.degrees(45))
                .position(x: lens.x + handleReach * diagonal, y: lens.y + handleReach * diagonal)

            Circle()
                .strokeBorder(tint, lineWidth: metrics.ringWidth)
                .frame(width: metrics.lensDiameter, height: metrics.lensDiameter)
                .position(lens)
        }
        .frame(width: metrics.width, height: metrics.height)
    }

    private func car(symbol: String, ink: Color, center: CGPoint) -> some View {
        Image(systemName: symbol)
            .font(.system(size: metrics.carPointSize, weight: .regular))
            .foregroundStyle(ink)
            .position(center)
            .frame(width: metrics.width, height: metrics.height)
    }
}

#Preview("Inspect loader") {
    VStack(spacing: 32) {
        HStack(spacing: 10) {
            VehicleInspectLoader(size: .inline)
            Text("Reading the receipt…")
                .font(.subheadline.weight(.semibold))
        }
        VehicleInspectLoader(size: .hero)
    }
    .padding(40)
    .background { AtmosphericBackground(style: .full).ignoresSafeArea() }
    .onGlassShell()
}
