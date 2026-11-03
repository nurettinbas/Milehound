import CoreLocation
import SwiftUI

struct RecordingEndCreditsSnapshot: Equatable {
    /// Unique per Stop tap so credits always remount and replay.
    let sessionID: UUID
    let tripID: UUID
    let durationText: String
    let distanceText: String
    let coordinates: [CLLocationCoordinate2D]
    /// Service schedule was urgent for the recording vehicle when Stop was tapped.
    let showsServiceDue: Bool
    /// Red wrench when the service date is past due.
    let serviceIsOverdue: Bool

    static func == (lhs: RecordingEndCreditsSnapshot, rhs: RecordingEndCreditsSnapshot) -> Bool {
        lhs.sessionID == rhs.sessionID
    }
}

/// Compact end-of-trip card that brakes, then the parent slides it into the list.
struct RecordingEndCreditsView: View {
    let snapshot: RecordingEndCreditsSnapshot
    var reduceMotion: Bool
    var onFinished: () -> Void

    @State private var brakeProgress: CGFloat = 0
    @State private var showBrakeLights = false
    @State private var carNoseDive: CGFloat = 0
    @State private var sceneOpacity: Double = 1
    @State private var showStats = false
    @State private var statsOpacity: Double = 0
    @State private var stoppedBadgeOpacity: Double = 0
    @State private var chromeOpacity: Double = 1
    @State private var routeProgress: CGFloat = 0
    @State private var routeSide: CGFloat = 44
    @State private var didFinish = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            BrakeToStopScene(
                brakeProgress: brakeProgress,
                showBrakeLights: showBrakeLights,
                noseDive: carNoseDive,
                showsServiceDue: snapshot.showsServiceDue,
                serviceIsOverdue: snapshot.serviceIsOverdue
            )
            .frame(width: 56, height: 36)
            .opacity(sceneOpacity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.tripEndedTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .opacity(max(stoppedBadgeOpacity, 0.35))

                if showStats {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(snapshot.durationText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(snapshot.distanceText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                    .opacity(statsOpacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(snapshot.durationText), \(snapshot.distanceText)")
                } else {
                    Text("…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .opacity(chromeOpacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            creditsRoute
                .frame(width: routeSide, height: routeSide)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            ZStack {
                RecordingCardStyle.listSurface(isPaused: false)
                    .opacity(1 - Double(brakeProgress) * 0.35)
                RecordingCardStyle.listSurface(isPaused: true)
                    .opacity(Double(brakeProgress) * 0.85)
                RadialGradient(
                    colors: [
                        Color.red.opacity(0.14 * Double(showBrakeLights ? 1 : 0)),
                        Color.clear
                    ],
                    center: .leading,
                    startRadius: 2,
                    endRadius: 90
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.tripEndedTitle). \(snapshot.durationText). \(snapshot.distanceText)")
        .task(id: snapshot.sessionID) {
            await playCredits()
        }
    }

    private var creditsRoute: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.28))

            LiveBreadcrumbCanvas(
                coordinates: snapshot.coordinates,
                progress: routeProgress
            )
            .padding(4)
        }
    }

    @MainActor
    private func playCredits() async {
        if reduceMotion {
            brakeProgress = 1
            showBrakeLights = true
            showStats = true
            statsOpacity = 1
            stoppedBadgeOpacity = 1
            routeProgress = 1
            routeSide = 44
            finishOnce()
            return
        }

        MilehoundHaptics.recordingStopped()

        showBrakeLights = true
        withAnimation(.easeOut(duration: 0.14)) {
            brakeProgress = 1
        }
        withAnimation(.easeInOut(duration: 0.06)) {
            carNoseDive = -2.0
        }
        try? await Task.sleep(for: .milliseconds(40))
        withAnimation(.spring(response: 0.14, dampingFraction: 0.72)) {
            carNoseDive = 0.6
        }
        try? await Task.sleep(for: .milliseconds(35))
        withAnimation(.spring(response: 0.12, dampingFraction: 0.86)) {
            carNoseDive = 0
        }

        showStats = true
        withAnimation(.easeOut(duration: 0.08)) {
            stoppedBadgeOpacity = 1
            chromeOpacity = 0
            statsOpacity = 1
            sceneOpacity = 0.8
        }

        // Draw route in fewer ticks so stop→list doesn't feel stuck on the card.
        let steps = 8
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else {
                finishOnce()
                return
            }
            routeProgress = CGFloat(step) / CGFloat(steps)
        }

        try? await Task.sleep(for: .milliseconds(40))
        // Keep the blue bar fully visible — parent slides it into the list.
        finishOnce()
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

// MARK: - Brake scene

private struct BrakeToStopScene: View {
    var brakeProgress: CGFloat
    var showBrakeLights: Bool
    var noseDive: CGFloat
    var showsServiceDue: Bool = false
    var serviceIsOverdue: Bool = false
    @State private var clock = Date.timeIntervalSinceReferenceDate

    var body: some View {
        let speedFactor = max(0.02, 1 - brakeProgress)
        let roadTime = clock * Double(speedFactor)

        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let roadHeight: CGFloat = 16
            let carSize: CGFloat = 22
            let carX = width * 0.58
            let carY = height - roadHeight - carSize * 0.18 + noseDive

            ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18 + 0.1 * Double(brakeProgress)),
                            Color.black.opacity(0.32 + 0.08 * Double(brakeProgress))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: roadHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 1.5)
                    }

                    laneDashes(width: width, roadHeight: roadHeight, time: roadTime)

                    if brakeProgress < 0.85 {
                        Circle()
                            .fill(Color.white.opacity(0.16 * (1 - brakeProgress)))
                            .frame(width: 8, height: 8)
                            .blur(radius: 2)
                            .position(x: carX - carSize * 0.55, y: carY + 3)
                    }

                    Image(systemName: "car.side.fill")
                        .font(.system(size: carSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(x: -1, y: 1)
                        .rotationEffect(.degrees(Double(noseDive) * 0.35))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .overlay(alignment: .trailing) {
                            HStack(spacing: 2) {
                                Capsule()
                                    .fill(Color.red.opacity(showBrakeLights ? 0.95 : 0))
                                    .frame(width: 4, height: 6)
                                Capsule()
                                    .fill(Color.red.opacity(showBrakeLights ? 0.95 : 0))
                                    .frame(width: 4, height: 6)
                            }
                            .offset(x: 1, y: 1)
                            .shadow(color: .red.opacity(showBrakeLights ? 0.75 : 0), radius: 4)
                        }
                        .overlay(alignment: .topTrailing) {
                            if showsServiceDue {
                                RecordingVehicleServiceBadge(
                                    carSize: carSize,
                                    isOverdue: serviceIsOverdue
                                )
                                .offset(
                                    x: RecordingVehicleServiceBadgeLayout.brakeSceneOffsetX(for: carSize),
                                    y: RecordingVehicleServiceBadgeLayout.brakeSceneOffsetY(for: carSize)
                                )
                            }
                        }
                        .position(x: carX, y: carY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(Color.white.opacity(0.06))
        .overlay(alignment: .topLeading) {
            MilehoundDisplayLinkTicker(isRunning: brakeProgress < 1, framesPerSecond: 30) { clock = $0 }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func laneDashes(width: CGFloat, roadHeight: CGFloat, time: TimeInterval) -> some View {
        let dashWidth: CGFloat = 14
        let dashSpacing: CGFloat = 12
        let pattern = dashWidth + dashSpacing
        let scrollSpeed: CGFloat = 80
        let offset = -CGFloat(time.truncatingRemainder(dividingBy: Double(pattern / scrollSpeed))) * scrollSpeed
        let count = max(0, Int(width / pattern) + 4)

        return ZStack(alignment: .leading) {
            if count > 0 {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: dashWidth, height: 2.5)
                        .offset(x: offset + CGFloat(index) * pattern)
                }
            }
        }
        .frame(height: roadHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: -roadHeight * 0.38)
        .mask(
            Rectangle()
                .frame(height: roadHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }
}
