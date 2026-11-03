import SwiftUI
import UIKit

enum OnboardingHeroKind: Equatable {
    case welcomeDrive
    case locationPin
    case vehicleCare
    case shortcutsLink
}

/// Onboarding hero using the same road/car DNA as the recording card.
struct OnboardingHeroScene: View {
    var kind: OnboardingHeroKind
    var driveInProgress: CGFloat = 1
    /// Pin drop / care icons / Shortcuts link snap (0 → 1).
    var beatProgress: CGFloat = 1
    var isAnimating: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { shellPalette.tintColor(for: colorScheme) }

    private var metrics: MilehoundRoadSceneMetrics { .hero }
    private var shouldAnimateRoad: Bool { isAnimating && !reduceMotion }
    private var animationInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 12 : 1 / 30
    }

    var body: some View {
        Group {
            if shouldAnimateRoad {
                TimelineView(MilehoundIndependentClock.periodic(interval: animationInterval)) { timeline in
                    sceneDriver(
                        liveTime: timeline.date.timeIntervalSinceReferenceDate,
                        shouldAnimate: true
                    )
                }
            } else {
                sceneDriver(liveTime: nil, shouldAnimate: false)
            }
        }
        .frame(height: metrics.sceneHeight)
        .frame(maxWidth: .infinity)
        // No glass card — sit directly on AtmosphericBackground.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sceneDriver(liveTime: TimeInterval?, shouldAnimate: Bool) -> some View {
        OnboardingRoadSceneDriver(
            liveTime: liveTime,
            shouldAnimate: shouldAnimate,
            metrics: metrics,
            driveInProgress: driveInProgress,
            kind: kind,
            beatProgress: beatProgress,
            reduceMotion: reduceMotion,
            accent: accent
        )
    }
}

private struct OnboardingRoadSceneDriver: View {
    let liveTime: TimeInterval?
    let shouldAnimate: Bool
    let metrics: MilehoundRoadSceneMetrics
    let driveInProgress: CGFloat
    let kind: OnboardingHeroKind
    let beatProgress: CGFloat
    let reduceMotion: Bool
    let accent: Color

    @State private var frozenRoadTime: TimeInterval = Date.timeIntervalSinceReferenceDate

    private var sceneTime: TimeInterval {
        if shouldAnimate, let liveTime {
            return liveTime
        }
        return frozenRoadTime
    }

    var body: some View {
        MilehoundRoadDrivingScene(
            time: sceneTime,
            metrics: metrics,
            palette: .atmosphere,
            isPaused: false,
            driveInProgress: driveInProgress,
            showsPauseBadge: false,
            accentColor: accent
        ) { layout in
            OnboardingHeroOverlay(
                kind: kind,
                layout: layout,
                beatProgress: beatProgress,
                reduceMotion: reduceMotion,
                accent: accent
            )
        }
        .frame(height: metrics.sceneHeight)
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
}

private struct OnboardingHeroOverlay: View {
    let kind: OnboardingHeroKind
    let layout: MilehoundRoadSceneLayout
    let beatProgress: CGFloat
    let reduceMotion: Bool
    let accent: Color

    var body: some View {
        switch kind {
        case .welcomeDrive:
            EmptyView()
        case .locationPin:
            locationPinOverlay
        case .vehicleCare:
            vehicleCareOverlay
        case .shortcutsLink:
            shortcutsLinkOverlay
        }
    }

    private var locationPinOverlay: some View {
        let eased = MilehoundRoadSceneMetrics.easeOutCubic(min(1, max(0, beatProgress)))
        let pinX = min(layout.size.width - 28, layout.carCenter.x + layout.carSize * 1.35)
        let settledY = layout.size.height - layout.roadHeight - 10
        let startY = settledY - 36
        let pinY = startY + (settledY - startY) * eased
        let pinOpacity = Double(0.2 + 0.8 * eased)

        return ZStack {
            SoftPulseRing(
                color: .white,
                isActive: eased > 0.85,
                reduceMotion: reduceMotion
            )
            .frame(width: 36, height: 36)
            .position(x: pinX, y: pinY)

            OnboardingOutlinedSymbol(systemName: "mappin.circle.fill", size: 26)
                .scaleEffect(0.86 + 0.14 * eased)
                .opacity(pinOpacity)
                .position(x: pinX, y: pinY)
        }
        .allowsHitTesting(false)
    }

    private var vehicleCareOverlay: some View {
        let clamped = min(1, max(0, beatProgress))
        let calendarEased = MilehoundRoadSceneMetrics.easeOutCubic(clamped)
        let expenseRaw = min(1, max(0, (clamped - 0.15) / 0.85))
        let expenseEased = MilehoundRoadSceneMetrics.easeOutCubic(expenseRaw)
        let pathEased = MilehoundRoadSceneMetrics.easeOutCubic(min(1, max(0, (clamped - 0.08) / 0.92)))

        let calendarPoint = CGPoint(x: layout.size.width * 0.22, y: layout.size.height * 0.30)
        let expensePoint = CGPoint(x: layout.size.width * 0.78, y: layout.size.height * 0.30)
        let calendarStartY = calendarPoint.y - 34
        let expenseStartY = expensePoint.y - 34
        let calendarY = calendarStartY + (calendarPoint.y - calendarStartY) * calendarEased
        let expenseY = expenseStartY + (expensePoint.y - expenseStartY) * expenseEased
        let mid = CGPoint(
            x: (calendarPoint.x + expensePoint.x) * 0.5,
            y: min(calendarPoint.y, expensePoint.y) - 22
        )

        return ZStack {
            outlinedCurve(
                from: CGPoint(x: calendarPoint.x, y: calendarY),
                to: CGPoint(x: expensePoint.x, y: expenseY),
                control: mid,
                trim: pathEased
            )

            OnboardingOutlinedSymbol(systemName: "calendar.badge.clock", size: 26)
                .scaleEffect(0.86 + 0.14 * calendarEased)
                .opacity(Double(0.2 + 0.8 * calendarEased))
                .position(x: calendarPoint.x, y: calendarY)

            SoftPulseRing(
                color: .white,
                isActive: expenseEased > 0.85,
                reduceMotion: reduceMotion
            )
            .frame(width: 38, height: 38)
            .position(x: expensePoint.x, y: expenseY)

            OnboardingOutlinedSymbol(systemName: "creditcard.circle.fill", size: 28)
                .scaleEffect(0.86 + 0.14 * expenseEased)
                .opacity(Double(0.2 + 0.8 * expenseEased))
                .position(x: expensePoint.x, y: expenseY)
        }
        .allowsHitTesting(false)
    }

    private var shortcutsLinkOverlay: some View {
        let eased = MilehoundRoadSceneMetrics.easeOutCubic(min(1, max(0, beatProgress)))
        let boltPoint = CGPoint(x: layout.size.width * 0.78, y: layout.size.height * 0.28)
        let carPoint = CGPoint(
            x: layout.carCenter.x + layout.carSize * 0.2,
            y: layout.carCenter.y - layout.carSize * 0.15
        )
        let mid = CGPoint(
            x: (boltPoint.x + carPoint.x) * 0.5,
            y: min(boltPoint.y, carPoint.y) - 18
        )

        return ZStack {
            outlinedCurve(from: boltPoint, to: carPoint, control: mid, trim: eased)

            OnboardingOutlinedSymbol(systemName: "bolt.horizontal.circle.fill", size: 28)
                .scaleEffect(0.9 + 0.1 * eased)
                .opacity(Double(0.35 + 0.65 * eased))
                .position(boltPoint)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 7, height: 7)
                .shadow(color: accent.opacity(0.6), radius: 3)
                .opacity(Double(eased))
                .position(carPoint)
        }
        .allowsHitTesting(false)
    }

    private func outlinedCurve(from start: CGPoint, to end: CGPoint, control: CGPoint, trim: CGFloat) -> some View {
        let curve = Path { path in
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
        return curve
            .trim(from: 0, to: trim)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
}

private struct OnboardingOutlinedSymbol: View {
    var systemName: String
    var size: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.white)
    }
}

#Preview("Welcome") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .welcomeDrive, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}

#Preview("Location") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .locationPin, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}

#Preview("Vehicle care") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .vehicleCare, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}

#Preview("Shortcuts") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .shortcutsLink, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}
