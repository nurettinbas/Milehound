import SwiftUI
import UIKit

enum RecapSceneMotion {
    /// Sine wave mapped to 0...1. Period ≤ 0 returns 0.
    static func phase(_ period: TimeInterval, at t: TimeInterval) -> CGFloat {
        guard period > 0 else { return 0 }
        let cycle = t.truncatingRemainder(dividingBy: period) / period
        let sine = (sin(cycle * 2 * .pi) + 1) / 2
        return CGFloat(min(1, max(0, sine)))
    }

    /// Sine wave mapped to -1...1.
    static func signedPhase(_ period: TimeInterval, at t: TimeInterval) -> CGFloat {
        phase(period, at: t) * 2 - 1
    }

    /// Linear wrap 0...1 for dash / highlight travel.
    static func saw(_ period: TimeInterval, at t: TimeInterval) -> CGFloat {
        guard period > 0 else { return 0 }
        let cycle = t.truncatingRemainder(dividingBy: period) / period
        if cycle < 0 { return CGFloat(cycle + 1) }
        return CGFloat(min(1, max(0, cycle)))
    }
}

enum RecapHubTeaserMetrics {
    static let posterHeight: CGFloat = 148
    static let stackedHeight: CGFloat = 88
    static let emptyHeight: CGFloat = 72
    static let promoHeight: CGFloat = 320
    static let idleInterval: TimeInterval = 1.0 / 8.0
}

/// Compact chapter-rail art: one glyph per story page, no Canvas scene, no copy on the emblem.
enum RecapChapterEmblem {
    static func systemName(for page: RecapStoryPage) -> String {
        switch page {
        case .intro: "sparkles"
        case .distance: "road.lanes"
        case .cities: "building.2.fill"
        case .route: "map.fill"
        case .time: "moon.stars.fill"
        case .categories: "steeringwheel"
        case .cost: "fuelpump.fill"
        case .badges: "medal.fill"
        case .closing: "flag.checkered"
        }
    }
}

struct RecapChapterEmblemScene: View {
    let page: RecapStoryPage

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let ink = RecapChapterBackdrop.glyphInk(page: page, palette: shellPalette, scheme: colorScheme)
        ZStack {
            Canvas { context, size in
                RecapChapterBackdrop.draw(
                    page: page,
                    context: &context,
                    size: size,
                    palette: shellPalette,
                    scheme: colorScheme
                )
            }
            Image(systemName: RecapChapterEmblem.systemName(for: page))
                .font(.system(size: RecapChapterRailTokens.emblemPointSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ink)
                .shadow(color: ink.opacity(0.35), radius: 12, y: 5)
                .offset(y: -RecapChapterRailTokens.emblemLift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// Frozen chapter-rail backdrops. Same shell atmosphere as the Recap poster (Light wash / Dark wrap).
enum RecapChapterBackdrop {
    static func glyphInk(page: RecapStoryPage, palette: ShellPalette, scheme: ColorScheme) -> Color {
        if scheme == .light {
            return Color.white.opacity(0.95)
        }
        switch page {
        case .time:
            return Color.white.opacity(0.92)
        case .cost:
            return RecapSpendInk.fuel(scheme: scheme, palette: palette)
        default:
            return palette.tintColor(for: scheme)
        }
    }

    static func draw(
        page: RecapStoryPage,
        context: inout GraphicsContext,
        size: CGSize,
        palette: ShellPalette,
        scheme: ColorScheme
    ) {
        let plate = palette.atmosphere(for: scheme)
        let tint = plate.tint.color
        let glow = plate.glow.color
        if page == .time, scheme == .dark {
            let night = nightSkyColors()
            fillSky(context: &context, size: size, top: night.0, bottom: night.1)
        } else {
            fillSky(context: &context, size: size, top: plate.top.color, bottom: plate.bottom.color)
        }
        let cool = StatsSegmentTokens.fill(index: 1, scheme: scheme, palette: palette)
        let fuel = RecapSpendInk.fuel(scheme: scheme, palette: palette)
        let cityTone = plate.tint.rotatedInk(degrees: 24, for: scheme).color
        switch page {
        case .intro:
            drawHorizonRoad(context: &context, size: size, tint: tint, glow: glow)
        case .distance:
            drawDistanceRings(context: &context, size: size, tint: tint, glow: glow)
        case .cities:
            drawSkyline(context: &context, size: size, tint: cityTone)
        case .route:
            drawRouteArc(context: &context, size: size, tint: tint, glow: glow)
        case .time:
            drawNightStars(context: &context, size: size, glow: glow)
        case .categories:
            drawPurposeRibbon(context: &context, size: size, tint: tint, rest: cool)
        case .cost:
            drawFuelPad(context: &context, size: size, fuel: fuel)
        case .badges:
            drawMedalHalo(context: &context, size: size, glow: glow, tint: tint)
        case .closing:
            drawClosingRoad(context: &context, size: size, tint: tint)
        }
    }

    /// Same shell atmosphere as the Recap poster on every chapter. Dark Time keeps night navy.
    private static func fillSky(
        context: inout GraphicsContext,
        size: CGSize,
        top: Color,
        bottom: Color
    ) {
        let rect = CGRect(origin: .zero, size: size)
        let start = CGPoint(x: size.width / 2, y: 0)
        let end = CGPoint(x: size.width / 2, y: size.height)
        context.fill(
            Path(rect),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: start, endPoint: end)
        )
    }

    private static func nightSkyColors() -> (Color, Color) {
        (
            Color(red: 0.06, green: 0.08, blue: 0.18),
            Color(red: 0.04, green: 0.05, blue: 0.1)
        )
    }

    private static func drawHorizonRoad(
        context: inout GraphicsContext,
        size: CGSize,
        tint: Color,
        glow: Color
    ) {
        let horizon = CGPoint(x: size.width / 2, y: size.height * 0.38)
        let bloom = min(size.width, size.height) * 0.42
        let bloomRect = CGRect(
            x: horizon.x - bloom,
            y: horizon.y - bloom * 0.7,
            width: bloom * 2,
            height: bloom * 1.4
        )
        context.fill(
            Path(ellipseIn: bloomRect),
            with: .radialGradient(
                Gradient(colors: [glow.opacity(0.45), .clear]),
                center: horizon,
                startRadius: 4,
                endRadius: bloom
            )
        )
        var left = Path()
        left.move(to: horizon)
        left.addLine(to: CGPoint(x: size.width * 0.12, y: size.height))
        var right = Path()
        right.move(to: horizon)
        right.addLine(to: CGPoint(x: size.width * 0.88, y: size.height))
        context.stroke(left, with: .color(tint.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        context.stroke(right, with: .color(tint.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private static func drawDistanceRings(
        context: inout GraphicsContext,
        size: CGSize,
        tint: Color,
        glow: Color
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let radii: [CGFloat] = [28, 46, 64]
        for (index, radius) in radii.enumerated() {
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let ring = index == 1 ? glow : tint
            let width: CGFloat = index == 1 ? 3 : 1.5
            context.stroke(Path(ellipseIn: rect), with: .color(ring.opacity(0.28)), lineWidth: width)
        }
    }

    private static func drawSkyline(context: inout GraphicsContext, size: CGSize, tint: Color) {
        let base = size.height * 0.72
        let blocks: [(CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.10, 0.18),
            (0.20, 0.14, 0.28),
            (0.36, 0.11, 0.22),
            (0.50, 0.16, 0.34),
            (0.68, 0.12, 0.20),
            (0.82, 0.10, 0.26)
        ]
        var silhouette = Path()
        silhouette.move(to: CGPoint(x: 0, y: size.height))
        silhouette.addLine(to: CGPoint(x: 0, y: base))
        for (xRatio, widthRatio, heightRatio) in blocks {
            let x = size.width * xRatio
            let w = size.width * widthRatio
            let h = size.height * heightRatio
            silhouette.addLine(to: CGPoint(x: x, y: base))
            silhouette.addLine(to: CGPoint(x: x, y: base - h))
            silhouette.addLine(to: CGPoint(x: x + w, y: base - h))
            silhouette.addLine(to: CGPoint(x: x + w, y: base))
        }
        silhouette.addLine(to: CGPoint(x: size.width, y: base))
        silhouette.addLine(to: CGPoint(x: size.width, y: size.height))
        silhouette.closeSubpath()
        context.fill(silhouette, with: .color(tint.opacity(0.22)))
    }

    private static func drawRouteArc(
        context: inout GraphicsContext,
        size: CGSize,
        tint: Color,
        glow: Color
    ) {
        let start = CGPoint(x: size.width * 0.14, y: size.height * 0.62)
        let end = CGPoint(x: size.width * 0.86, y: size.height * 0.46)
        let control = CGPoint(x: size.width * 0.48, y: size.height * 0.18)
        var arc = Path()
        arc.move(to: start)
        arc.addQuadCurve(to: end, control: control)
        context.stroke(arc, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        context.stroke(arc, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(glow))
        context.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(tint))
    }

    private static func drawNightStars(context: inout GraphicsContext, size: CGSize, glow: Color) {
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.16, 0.14, 2.2),
            (0.34, 0.22, 1.6),
            (0.72, 0.12, 2.4),
            (0.84, 0.28, 1.8),
            (0.22, 0.36, 1.4),
            (0.58, 0.18, 2.0)
        ]
        for (x, y, r) in seeds {
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * x - r, y: size.height * y - r, width: r * 2, height: r * 2)),
                with: .color(glow.opacity(0.85))
            )
        }
    }

    private static func drawPurposeRibbon(
        context: inout GraphicsContext,
        size: CGSize,
        tint: Color,
        rest: Color
    ) {
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: 0, y: size.height * 0.58))
        ribbon.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.42))
        ribbon.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
        ribbon.addLine(to: CGPoint(x: size.width, y: size.height))
        ribbon.addLine(to: CGPoint(x: 0, y: size.height))
        ribbon.closeSubpath()
        context.fill(ribbon, with: .color(tint.opacity(0.34)))
        var restBand = Path()
        restBand.move(to: CGPoint(x: size.width * 0.62, y: size.height * 0.42))
        restBand.addLine(to: CGPoint(x: size.width, y: size.height * 0.36))
        restBand.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
        restBand.closeSubpath()
        context.fill(restBand, with: .color(rest.opacity(0.4)))
    }

    private static func drawFuelPad(context: inout GraphicsContext, size: CGSize, fuel: Color) {
        let pad = CGRect(x: size.width * 0.18, y: size.height * 0.68, width: size.width * 0.64, height: 18)
        context.fill(Path(ellipseIn: pad), with: .color(fuel.opacity(0.35)))
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.28, y: size.height * 0.22, width: size.width * 0.44, height: size.width * 0.44)),
            with: .radialGradient(
                Gradient(colors: [fuel.opacity(0.4), .clear]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.4),
                startRadius: 8,
                endRadius: size.width * 0.38
            )
        )
    }

    private static func drawMedalHalo(
        context: inout GraphicsContext,
        size: CGSize,
        glow: Color,
        tint: Color
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.4)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 52, y: center.y - 52, width: 104, height: 104)),
            with: .radialGradient(
                Gradient(colors: [glow.opacity(0.2), tint.opacity(0.08), .clear]),
                center: center,
                startRadius: 8,
                endRadius: 56
            )
        )
    }

    private static func drawClosingRoad(context: inout GraphicsContext, size: CGSize, tint: Color) {
        let horizon = CGPoint(x: size.width / 2, y: size.height * 0.28)
        var left = Path()
        left.move(to: horizon)
        left.addLine(to: CGPoint(x: size.width * 0.18, y: size.height))
        var right = Path()
        right.move(to: horizon)
        right.addLine(to: CGPoint(x: size.width * 0.82, y: size.height))
        context.stroke(left, with: .color(tint.opacity(0.4)), lineWidth: 2)
        context.stroke(right, with: .color(tint.opacity(0.4)), lineWidth: 2)
        for index in 0..<5 {
            let t = 0.35 + CGFloat(index) * 0.12
            let y = horizon.y + (size.height - horizon.y) * t
            let w = 3 + CGFloat(index) * 2.2
            context.fill(
                Path(roundedRect: CGRect(x: horizon.x - w / 2, y: y, width: w, height: 7 + CGFloat(index)), cornerRadius: 1),
                with: .color(.white.opacity(0.35 + 0.08 * Double(index)))
            )
        }
    }
}

struct RecapHubTeaserScene: View {
    var height: CGFloat = RecapHubTeaserMetrics.emptyHeight
    var allowsIdleMotion: Bool = false
    var cornerRadius: CGFloat = StatsCardTokens.nestedRadius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    private var liveMotion: Bool {
        allowsIdleMotion
            && isOnScreen
            && scenePhase == .active
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !UITestSupport.isEnabled
    }

    var body: some View {
        Group {
            if liveMotion {
                TimelineView(MilehoundIndependentClock.periodic(interval: RecapHubTeaserMetrics.idleInterval)) { timeline in
                    canvas(motion: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(motion: 0)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    private func canvas(motion: TimeInterval) -> RecapStoryCanvas {
        RecapStoryCanvas(
            palette: shellPalette,
            scheme: colorScheme,
            kind: .intro,
            badgeIDs: [],
            motion: motion
        )
    }
}

struct RecapPageScene: View {
    let page: RecapStoryPage
    var isActive: Bool
    var reduceMotion: Bool
    var badgeIDs: [AchievementID] = []
    var motion: TimeInterval = 0
    var purposeShare: Double = 0
    var estimatedFuelCost: Double = 0
    var paidExpenses: Double = 0
    var pageElapsed: TimeInterval = RecapIntroReveal.settledElapsed

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        RecapStoryCanvas(
            palette: shellPalette,
            scheme: colorScheme,
            kind: page,
            badgeIDs: badgeIDs,
            motion: reduceMotion ? 0 : motion,
            purposeShare: purposeShare,
            estimatedFuelCost: estimatedFuelCost,
            paidExpenses: paidExpenses,
            pageElapsed: pageElapsed,
            reduceMotion: reduceMotion
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if page == .badges {
                RecapStoryBadgeStage(
                    ids: badgeIDs,
                    motion: motion,
                    reduceMotion: reduceMotion
                )
            }
        }
        .opacity(isActive ? 1 : 0.92)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct RecapStoryBottomScrim: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                .clear,
                Color.black.opacity(colorScheme == .dark ? 0.58 : 0.42)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct RecapStoryPageForeground: View {
    let snapshot: YearRecapSnapshot
    let page: RecapStoryPage
    var displayedDistance: Double
    var routeImage: UIImage?
    var motion: TimeInterval
    var reduceMotion: Bool
    var pageElapsed: TimeInterval = RecapIntroReveal.settledElapsed

    var body: some View {
        Group {
            if page == .cost {
                GeometryReader { geo in
                    VStack(spacing: RecapCostLayout.stackSpacing) {
                        Color.clear.frame(
                            height: RecapCostLayout.groupTop(in: geo.size)
                                + RecapCostLayout.pumpHeight(in: geo.size)
                        )
                        RecapStoryPageCopy(
                            snapshot: snapshot,
                            page: page,
                            displayedDistance: displayedDistance,
                            routeImage: routeImage,
                            pageElapsed: pageElapsed,
                            reduceMotion: reduceMotion
                        )
                        .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    RecapStoryPageCopy(
                        snapshot: snapshot,
                        page: page,
                        displayedDistance: displayedDistance,
                        routeImage: routeImage,
                        pageElapsed: pageElapsed,
                        reduceMotion: reduceMotion
                    )
                    .padding(.horizontal, 28)
                    if page == .badges {
                        let extra = RecapStoryBadgeLayout.overflowCount(RecapStoryBadgeIDs.resolved(from: snapshot).count)
                        if extra > 0 {
                            Text("+\(extra)")
                                .font(.headline.monospacedDigit())
                                .glassSecondaryInk()
                        }
                    }
                }
                .padding(.bottom, isTitleCardPage ? 0 : 10)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: isTitleCardPage ? .center : .bottom
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var isTitleCardPage: Bool {
        page == .intro || page == .categories
    }
}

enum RecapCostLayout {
    static let stackSpacing: CGFloat = 14
    static let copyBlockHeight: CGFloat = 152

    static func pumpHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.30, 210), 268)
    }

    static func groupHeight(in size: CGSize) -> CGFloat {
        pumpHeight(in: size) + stackSpacing + copyBlockHeight
    }

    static func groupTop(in size: CGSize) -> CGFloat {
        (size.height - groupHeight(in: size)) / 2
    }

    static func pumpRect(in size: CGSize, both: Bool, isLeading: Bool) -> CGRect {
        let top = groupTop(in: size)
        let height = pumpHeight(in: size)
        if both {
            let width = size.width * 0.26
            let gap: CGFloat = 22
            let pair = width * 2 + gap
            let start = (size.width - pair) / 2
            let x = isLeading ? start : start + width + gap
            return CGRect(x: x, y: top, width: width, height: height)
        }
        let width = size.width * 0.32
        return CGRect(x: (size.width - width) / 2, y: top, width: width, height: height)
    }
}

enum RecapStoryBadgeIDs {
    static func resolved(from snapshot: YearRecapSnapshot) -> [AchievementID] {
        snapshot.unlockedAchievementIDs
            .compactMap(AchievementID.init(rawValue:))
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

private struct RecapIntroTitleCard: View {
    let year: Int
    var elapsed: TimeInterval
    var reduceMotion: Bool

    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glow = shellPalette.atmosphere(for: colorScheme).glow.color
        let kicker = RecapIntroReveal.kickerOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        let yearOpacity = RecapIntroReveal.yearOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        let yearScale = RecapIntroReveal.yearScale(elapsed: elapsed, reduceMotion: reduceMotion)
        let whisper = RecapIntroReveal.whisperOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        VStack(spacing: 10) {
            Text(L10n.string("premium.recap.intro_kicker"))
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .opacity(kicker)
            Text(verbatim: String(year))
                .font(.system(size: 80, weight: .bold, design: .rounded).monospacedDigit())
                .glassPrimaryInk()
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .shadow(color: glow.opacity(0.55), radius: 24)
                .shadow(color: glow.opacity(0.28), radius: 8)
                .scaleEffect(yearScale)
                .opacity(yearOpacity)
            Text(L10n.string("premium.recap.intro_body"))
                .font(.title3)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .opacity(whisper)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct RecapPurposeTitleCard: View {
    let verdict: RecapPurposeVerdict
    var elapsed: TimeInterval
    var reduceMotion: Bool

    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glow = shellPalette.atmosphere(for: colorScheme).glow.color
        let kicker = RecapIntroReveal.kickerOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        let heroOpacity = RecapIntroReveal.yearOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        let heroScale = RecapIntroReveal.yearScale(elapsed: elapsed, reduceMotion: reduceMotion)
        let whisper = RecapIntroReveal.whisperOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(L10n.string("premium.recap.purpose_kicker"))
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .opacity(kicker)
                Text(verbatim: RecapPurposePolicy.heroTitle(for: verdict))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                    .shadow(color: glow.opacity(0.45), radius: 20)
                    .shadow(color: glow.opacity(0.22), radius: 6)
                    .scaleEffect(heroScale)
                    .opacity(heroOpacity)
                Text(verbatim: RecapPurposePolicy.whisper(for: verdict))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .opacity(whisper)
            }
            if !verdict.slices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(verdict.slices.enumerated()), id: \.offset) { _, slice in
                        RecapPurposeMixRow(
                            slice: slice,
                            isWinner: isWinner(slice)
                        )
                    }
                }
                .frame(maxWidth: 280)
                .opacity(whisper)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func isWinner(_ slice: RecapPurposeSlice) -> Bool {
        guard slice.kind == verdict.kind else { return false }
        guard slice.kind == .custom else { return true }
        return RecapPurposePolicy.normalizedCustomName(slice.customName)
            == RecapPurposePolicy.normalizedCustomName(verdict.customName)
    }
}

private struct RecapPurposeMixRow: View {
    let slice: RecapPurposeSlice
    var isWinner: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(verbatim: RecapPurposePolicy.percentLabel(slice.share))
                .font(
                    isWinner
                        ? .title2.weight(.bold).monospacedDigit()
                        : .headline.weight(.semibold).monospacedDigit()
                )
                .glassPrimaryInk()
                .opacity(isWinner ? 1 : 0.72)
                .frame(minWidth: 56, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: RecapPurposePolicy.displayName(for: slice))
                    .font(isWinner ? .headline.weight(.semibold) : .subheadline.weight(.medium))
                    .glassPrimaryInk()
                    .opacity(isWinner ? 1 : 0.78)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(verbatim: DateFormatters.formatDistance(slice.distanceMeters))
                    .font(.caption.monospacedDigit())
                    .glassSecondaryInk()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RecapCostAmountCards: View {
    let estimatedFuelCost: Double
    let paidExpenses: Double
    var elapsed: TimeInterval
    var reduceMotion: Bool

    private var showsFuel: Bool { estimatedFuelCost > 0 }
    private var showsExpenses: Bool { paidExpenses > 0 }
    private var showsBoth: Bool { showsFuel && showsExpenses }

    var body: some View {
        let fade = RecapIntroReveal.whisperOpacity(elapsed: elapsed, reduceMotion: reduceMotion)
        VStack(spacing: 8) {
            Text(L10n.string("premium.recap.cost_kicker"))
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
                .lineLimit(1)
            HStack(alignment: .top, spacing: 6) {
                if showsFuel {
                    RecapCostAmountCard(
                        amount: estimatedFuelCost,
                        labelKey: "premium.recap.fuel_estimate",
                        stop: RecapSpendInk.fuelStop,
                        compact: showsBoth
                    )
                }
                if showsExpenses {
                    RecapCostAmountCard(
                        amount: paidExpenses,
                        labelKey: "premium.recap.logged_expenses",
                        stop: RecapSpendInk.expensesStop,
                        compact: showsBoth
                    )
                }
            }
            if showsBoth {
                Text(L10n.string("premium.recap.cost_whisper"))
                    .font(.caption.weight(.medium))
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .opacity(fade)
        .accessibilityElement(children: .combine)
    }
}

private struct RecapCostAmountCard: View {
    let amount: Double
    let labelKey: String
    let stop: Int
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                StatsSegmentSwatch(index: stop)
                Text(L10n.string(labelKey))
                    .font(.caption.weight(.semibold))
                    .glassSecondaryInk()
                    .lineLimit(2, reservesSpace: compact)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Fuel tint is the same family as the frozen plate, so a tinted figure vanishes.
            Text(verbatim: FuelCostCalculator.formatCost(amount))
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .glassPrimaryInk()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pair cards share one width. A longer label or amount must not grow only one plate.
        .frame(
            minWidth: compact ? 132 : 160,
            maxWidth: compact ? 132 : 200,
            alignment: .leading
        )
        .glassCard(
            cornerRadius: GlassTokens.cardRadius,
            contentInset: 12,
            frozen: true,
            allowsNative: false
        )
    }
}

struct RecapStoryPageCopy: View {
    let snapshot: YearRecapSnapshot
    let page: RecapStoryPage
    var displayedDistance: Double
    var routeImage: UIImage?
    var pageElapsed: TimeInterval = RecapIntroReveal.settledElapsed
    var reduceMotion: Bool = true

    var body: some View {
        switch page {
        case .intro:
            RecapIntroTitleCard(
                year: snapshot.year,
                elapsed: pageElapsed,
                reduceMotion: reduceMotion
            )
        case .distance:
            VStack(spacing: 8) {
                Text(DateFormatters.formatDistance(displayedDistance))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .glassPrimaryInk()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(String(format: L10n.string("premium.recap.distance_body"), snapshot.tripCount))
                    .font(.title3)
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
                if snapshot.duration > 0 {
                    Text(String(format: L10n.string("premium.recap.duration_line"), DateFormatters.formatDuration(snapshot.duration)))
                        .font(.headline)
                        .glassSecondaryInk()
                }
            }
        case .cities:
            VStack(spacing: 12) {
                Text("\(snapshot.cityCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .glassPrimaryInk()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(L10n.string("premium.recap.cities_body"))
                    .font(.title3)
                    .glassSecondaryInk()
                ForEach(snapshot.topCities, id: \.self) { city in
                    Text(city).font(.headline).glassPrimaryInk()
                }
            }
        case .route:
            VStack(spacing: 10) {
                Text(L10n.string("premium.recap.route_title"))
                    .font(.headline)
                    .glassSecondaryInk()
                if let routeImage {
                    Image(uiImage: routeImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text("\(snapshot.topRouteStart ?? "") → \(snapshot.topRouteEnd ?? "")")
                    .font(.title2.weight(.bold))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(String(format: L10n.string("premium.recap.route_count"), snapshot.topRouteCount))
                    .glassSecondaryInk()
            }
        case .time:
            VStack(spacing: 12) {
                if snapshot.nightDistanceMeters > 0 {
                    Text(String(format: L10n.string("premium.recap.night"), DateFormatters.formatDistance(snapshot.nightDistanceMeters)))
                        .font(.title2.weight(.bold))
                        .glassPrimaryInk()
                        .minimumScaleFactor(0.7)
                }
                if snapshot.longestStreak > 0 {
                    Text(String(format: L10n.string("premium.recap.streak"), snapshot.longestStreak))
                        .font(.title2.weight(.bold))
                        .glassPrimaryInk()
                }
                if let month = snapshot.busiestMonth {
                    Text(String(format: L10n.string("premium.recap.busiest_month"), DateFormatters.formatMonthName(month: month, year: snapshot.year)))
                        .font(.title3)
                        .glassSecondaryInk()
                    if snapshot.busiestMonthDistanceMeters > 0 {
                        Text(DateFormatters.formatDistance(snapshot.busiestMonthDistanceMeters))
                            .font(.headline.monospacedDigit())
                            .glassPrimaryInk()
                    }
                }
            }
            .multilineTextAlignment(.center)
        case .categories:
            if let verdict = snapshot.purposeVerdict {
                RecapPurposeTitleCard(
                    verdict: verdict,
                    elapsed: pageElapsed,
                    reduceMotion: reduceMotion
                )
            }
        case .cost:
            RecapCostAmountCards(
                estimatedFuelCost: snapshot.estimatedFuelCost,
                paidExpenses: snapshot.paidExpenses,
                elapsed: pageElapsed,
                reduceMotion: reduceMotion
            )
        case .badges:
            Text(L10n.string("premium.recap.badges_title"))
                .font(.headline)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
        case .closing:
            VStack(spacing: 10) {
                Text(String(format: L10n.string("premium.recap.closing"), snapshot.year))
                    .font(.largeTitle.weight(.bold))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(L10n.string("premium.recap.closing_body"))
                    .font(.title3)
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
            }
        }
    }
}

enum RecapStoryBadgeLayout {
    static let maxVisible = 6
    static let captionSlot: CGFloat = 34
    static let slotScale: CGFloat = 2.12

    static func visibleCount(_ count: Int) -> Int {
        min(maxVisible, max(0, count))
    }

    static func overflowCount(_ count: Int) -> Int {
        max(0, count - maxVisible)
    }

    static func rowPattern(count: Int) -> [Int] {
        switch visibleCount(count) {
        case 0: []
        case 1: [1]
        case 2: [2]
        case 3: [3]
        case 4: [2, 2]
        case 5: [3, 2]
        default: [3, 3]
        }
    }

    static func medalSize(in size: CGSize, count: Int) -> CGFloat {
        let n = visibleCount(count)
        guard n > 0 else { return 0 }
        let columns = CGFloat(rowPattern(count: n).max() ?? 1)
        let preferred: CGFloat
        switch n {
        case 1: preferred = min(92, size.width * 0.26)
        case 2: preferred = min(78, size.width * 0.22)
        case 4: preferred = min(70, size.width * 0.2)
        default: preferred = min(64, size.width * 0.16)
        }
        let maxFit = (size.width * 0.9) / (columns * slotScale)
        return min(preferred, maxFit)
    }

    static func slotSize(medal: CGFloat) -> CGSize {
        CGSize(width: medal * slotScale, height: medal * slotScale + captionSlot)
    }

    static func slots(in size: CGSize, count: Int) -> [CGRect] {
        let n = visibleCount(count)
        guard n > 0 else { return [] }
        let medal = medalSize(in: size, count: n)
        let slot = slotSize(medal: medal)
        let pattern = rowPattern(count: n)
        let rowGap = medal * 0.1
        let clusterH = CGFloat(pattern.count) * slot.height + CGFloat(max(0, pattern.count - 1)) * rowGap
        let clusterY = min(max(size.height * 0.38 - clusterH / 2, size.height * 0.14), size.height * 0.4)
        var frames: [CGRect] = []
        for (row, items) in pattern.enumerated() {
            let rowW = CGFloat(items) * slot.width
            let originX = (size.width - rowW) / 2
            let y = clusterY + CGFloat(row) * (slot.height + rowGap)
            for column in 0..<items {
                frames.append(
                    CGRect(
                        x: originX + CGFloat(column) * slot.width,
                        y: y,
                        width: slot.width,
                        height: slot.height
                    )
                )
            }
        }
        return frames
    }

    static func medalRect(in slot: CGRect, medal: CGFloat, offsetY: CGFloat) -> CGRect {
        CGRect(
            x: slot.midX - medal / 2,
            y: slot.minY + (slot.height - captionSlot - medal) * 0.42 + offsetY,
            width: medal,
            height: medal
        )
    }

    static func offsetY(index: Int, motion: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return RecapSceneMotion.signedPhase(2.4, at: motion + Double(index) * 0.28) * 5
    }
}

struct RecapStoryBadgeStage: View {
    let ids: [AchievementID]
    var motion: TimeInterval
    var reduceMotion: Bool

    private var visible: [AchievementID] {
        Array(ids.prefix(RecapStoryBadgeLayout.maxVisible))
    }

    var body: some View {
        GeometryReader { geo in
            let slots = RecapStoryBadgeLayout.slots(in: geo.size, count: visible.count)
            let medal = RecapStoryBadgeLayout.medalSize(in: geo.size, count: visible.count)
            ForEach(Array(visible.enumerated()), id: \.element) { index, id in
                RecapStoryBadgeCell(
                    id: id,
                    size: medal,
                    index: index,
                    motion: motion,
                    reduceMotion: reduceMotion
                )
                .frame(width: slots[index].width, height: slots[index].height)
                .position(x: slots[index].midX, y: slots[index].midY)
            }
        }
        .environment(\.achievementIdleTime, reduceMotion ? nil : motion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ids.map { L10n.string($0.titleKey) }.joined(separator: ", "))
    }
}

private struct RecapStoryBadgeCell: View {
    let id: AchievementID
    let size: CGFloat
    let index: Int
    var motion: TimeInterval
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let slot = CGRect(origin: .zero, size: geo.size)
            let offset = RecapStoryBadgeLayout.offsetY(index: index, motion: motion, reduceMotion: reduceMotion)
            let medalRect = RecapStoryBadgeLayout.medalRect(in: slot, medal: size, offsetY: offset)
            AchievementMedalMark(
                item: AchievementDisplay(
                    id: id,
                    currentValue: id.threshold,
                    unlockedAt: Date(),
                    needsCelebration: false
                ),
                size: size,
                playsMotion: !reduceMotion
            )
            .frame(width: size, height: size)
            .position(x: medalRect.midX, y: medalRect.midY)
            Text(L10n.string(id.titleKey))
                .font(.caption.weight(.semibold))
                .glassPrimaryInk()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(width: slot.width - 8)
                .position(
                    x: slot.midX,
                    y: min(slot.maxY - RecapStoryBadgeLayout.captionSlot / 2, medalRect.maxY + 16)
                )
        }
        .accessibilityHidden(true)
    }
}

private struct RecapStoryCanvas: View {
    let palette: ShellPalette
    let scheme: ColorScheme
    let kind: RecapStoryPage
    let badgeIDs: [AchievementID]
    var motion: TimeInterval = 0
    var purposeShare: Double = 0
    var estimatedFuelCost: Double = 0
    var paidExpenses: Double = 0
    var pageElapsed: TimeInterval = RecapIntroReveal.settledElapsed
    var reduceMotion: Bool = true

    var body: some View {
        Canvas { context, size in
            let atmosphere = palette.atmosphere(for: scheme)
            let tint = atmosphere.tint.color
            let glow = atmosphere.glow.color
            let top = atmosphere.top.color
            let bottom = atmosphere.bottom.color
            drawAtmosphere(context: &context, size: size, top: top, bottom: bottom, glow: glow)
            switch kind {
            case .intro:
                drawIntro(context: &context, size: size, tint: tint, glow: glow)
            case .distance:
                drawDistance(context: &context, size: size, tint: tint, glow: glow)
            case .cities:
                drawCities(context: &context, size: size, tint: tint, glow: glow)
            case .route:
                drawRoute(context: &context, size: size, tint: tint, glow: glow)
            case .time:
                drawTime(context: &context, size: size, tint: tint, glow: glow)
            case .categories:
                drawCategories(context: &context, size: size, tint: tint, glow: glow)
            case .cost:
                drawCost(context: &context, size: size, tint: tint, glow: glow)
            case .badges:
                drawBadges(context: &context, size: size, tint: tint, glow: glow)
            case .closing:
                drawClosing(context: &context, size: size, tint: tint, glow: glow)
            }
        }
    }

    private func drawAtmosphere(
        context: inout GraphicsContext,
        size: CGSize,
        top: Color,
        bottom: Color,
        glow: Color
    ) {
            let night = kind == .time
            let topColor = night
                ? (scheme == .dark
                    ? Color(red: 0.06, green: 0.08, blue: 0.18)
                    : Color(red: 0.28, green: 0.34, blue: 0.52))
                : top
            let bottomColor = night
                ? (scheme == .dark
                    ? Color(red: 0.04, green: 0.05, blue: 0.1)
                    : Color(red: 0.16, green: 0.18, blue: 0.3))
                : bottom
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [topColor, bottomColor]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )
        let compact = size.height <= RecapChapterRailTokens.cardHeight + 1
        if !compact && kind != .intro && kind != .categories {
            drawAmbientSparkles(context: &context, size: size, glow: glow)
        }
    }

    private func drawAmbientSparkles(context: inout GraphicsContext, size: CGSize, glow: Color) {
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.10, 0.14, 1.7),
            (0.22, 0.08, 2.3),
            (0.38, 0.16, 1.9),
            (0.54, 0.10, 2.6),
            (0.72, 0.13, 2.1),
            (0.88, 0.09, 1.8),
            (0.16, 0.28, 2.8),
            (0.84, 0.24, 2.4),
            (0.48, 0.22, 3.1),
            (0.64, 0.32, 2.0)
        ]
        let extra: [(CGFloat, CGFloat, CGFloat)] = kind == .badges
            ? [(0.08, 0.42, 2.2), (0.92, 0.38, 2.5), (0.30, 0.48, 1.9), (0.70, 0.52, 2.7)]
            : []
        for (index, seed) in (seeds + extra).enumerated() {
            let twinkle = RecapSceneMotion.phase(1.5 + Double(seed.2) * 0.18, at: motion + Double(index) * 0.41)
            guard twinkle > 0.18 else { continue }
            let drift = RecapSceneMotion.signedPhase(7.5, at: motion + Double(index)) * 6
            let point = CGPoint(x: size.width * seed.0 + drift, y: size.height * seed.1)
            drawSparkle(
                context: &context,
                at: point,
                brightness: twinkle,
                color: index.isMultiple(of: 3) ? glow : .white,
                scale: kind == .badges ? 1.15 : 0.85
            )
        }
    }

    private func drawSparkle(
        context: inout GraphicsContext,
        at point: CGPoint,
        brightness: CGFloat,
        color: Color,
        scale: CGFloat
    ) {
        let r = 1.15 * scale * (0.5 + 0.75 * brightness)
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.55 + 0.4 * Double(brightness)), .clear]),
                center: point,
                startRadius: 0.4,
                endRadius: r * 2.4
            )
        )
        let arm = r * 2.6
        let thin = max(0.55, r * 0.32)
        context.fill(
            Path(roundedRect: CGRect(x: point.x - thin / 2, y: point.y - arm, width: thin, height: arm * 2), cornerRadius: thin / 2),
            with: .color(Color.white.opacity(0.28 + 0.62 * Double(brightness)))
        )
        context.fill(
            Path(roundedRect: CGRect(x: point.x - arm, y: point.y - thin / 2, width: arm * 2, height: thin), cornerRadius: thin / 2),
            with: .color(Color.white.opacity(0.18 + 0.5 * Double(brightness)))
        )
    }

    private func drawIntro(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let compact = size.height <= RecapHubTeaserMetrics.posterHeight + 1
        let dolly = compact ? 0 : RecapSceneMotion.phase(7, at: motion)
        let horizonY = size.height * (0.40 - 0.04 * dolly)
        drawVanishingRoad(context: &context, size: size, horizonY: horizonY, tint: tint)
        let horizon = CGPoint(x: size.width * 0.5, y: horizonY)
        let breathe = RecapSceneMotion.phase(6, at: motion)
        let bloomRadius = (compact ? size.height * 0.55 : min(size.width, size.height) * 0.42)
            + (compact ? 6 : 26) * breathe
        context.fill(
            Path(ellipseIn: CGRect(
                x: horizon.x - bloomRadius,
                y: horizon.y - bloomRadius * 0.78,
                width: bloomRadius * 2,
                height: bloomRadius * 1.6
            )),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.46 + 0.2 * Double(breathe)),
                    glow.opacity(0.4 + 0.18 * Double(breathe)),
                    tint.opacity(0.18),
                    .clear
                ]),
                center: horizon,
                startRadius: compact ? 3 : 8,
                endRadius: bloomRadius
            )
        )
        let core = compact ? 5.0 : 11.0
        context.fill(
            Path(ellipseIn: CGRect(x: horizon.x - core, y: horizon.y - core * 0.55, width: core * 2, height: core * 1.1)),
            with: .color(Color.white.opacity(0.55 + 0.25 * Double(breathe)))
        )
        guard !compact else { return }
        drawIntroMotes(context: &context, size: size, glow: glow)
    }

    private func drawIntroMotes(context: inout GraphicsContext, size: CGSize, glow: Color) {
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.12, 0.18, 2.1),
            (0.28, 0.11, 1.6),
            (0.46, 0.16, 2.4),
            (0.63, 0.09, 1.9),
            (0.81, 0.14, 2.7),
            (0.18, 0.32, 3.0),
            (0.74, 0.28, 2.2),
            (0.88, 0.22, 1.7)
        ]
        for (index, seed) in seeds.enumerated() {
            let twinkle = RecapSceneMotion.phase(2.2 + Double(seed.2) * 0.2, at: motion + Double(index) * 0.37)
            guard twinkle > 0.22 else { continue }
            let drift = RecapSceneMotion.signedPhase(9, at: motion + Double(index)) * 5
            let point = CGPoint(x: size.width * seed.0 + drift, y: size.height * seed.1)
            let r = 1.1 + 1.4 * twinkle
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        (index.isMultiple(of: 2) ? glow : Color.white).opacity(0.22 + 0.45 * Double(twinkle)),
                        .clear
                    ]),
                    center: point,
                    startRadius: 0.3,
                    endRadius: r * 2.2
                )
            )
        }
    }

    private func drawDistance(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.5, tint: tint)
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
        let radius = min(size.width, size.height) * 0.28
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(140),
            endAngle: .degrees(40),
            clockwise: false
        )
        context.stroke(arc, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        var fill = Path()
        let fillSweep = 110 + 28 * RecapSceneMotion.phase(6.5, at: motion)
        fill.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(140),
            endAngle: .degrees(140 + Double(fillSweep)),
            clockwise: false
        )
        context.stroke(fill, with: .color(tint), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        for tick in 0..<9 {
            let angle = Angle.degrees(140 + Double(tick) * 28.75)
            let inner = point(on: center, radius: radius - 22, angle: angle)
            let outer = point(on: center, radius: radius - 8, angle: angle)
            var tickPath = Path()
            tickPath.move(to: inner)
            tickPath.addLine(to: outer)
            context.stroke(tickPath, with: .color(.white.opacity(0.55)), lineWidth: tick % 2 == 0 ? 2.5 : 1.2)
        }
        var needle = Path()
        needle.move(to: center)
        let sway = RecapSceneMotion.signedPhase(5.5, at: motion)
        needle.addLine(to: point(on: center, radius: radius - 18, angle: .degrees(232 + Double(16 * sway))))
        context.stroke(needle, with: .color(glow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)),
            with: .color(.white.opacity(0.9))
        )
    }

    private func drawCities(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let drift = RecapSceneMotion.signedPhase(8, at: motion) * 14
        var skyline = context
        skyline.translateBy(x: drift, y: 0)
        let base = size.height * 0.52
        let widths: [CGFloat] = [0.07, 0.1, 0.06, 0.14, 0.08, 0.11, 0.07, 0.09, 0.06]
        let heights: [CGFloat] = [0.14, 0.28, 0.18, 0.38, 0.22, 0.32, 0.16, 0.24, 0.2]
        var x = size.width * 0.04
        var silhouette = Path()
        silhouette.move(to: CGPoint(x: 0, y: base))
        for index in widths.indices {
            let w = size.width * widths[index]
            let h = size.height * heights[index]
            silhouette.addLine(to: CGPoint(x: x, y: base))
            silhouette.addLine(to: CGPoint(x: x, y: base - h))
            if index == 1 || index == 3 || index == 5 {
                silhouette.addLine(to: CGPoint(x: x + w * 0.45, y: base - h - 16))
                silhouette.addLine(to: CGPoint(x: x + w, y: base - h))
            } else {
                silhouette.addLine(to: CGPoint(x: x + w, y: base - h))
            }
            silhouette.addLine(to: CGPoint(x: x + w, y: base))
            x += w + 6
        }
        silhouette.addLine(to: CGPoint(x: size.width, y: base))
        silhouette.addLine(to: CGPoint(x: size.width, y: size.height))
        silhouette.addLine(to: CGPoint(x: 0, y: size.height))
        silhouette.closeSubpath()
        skyline.fill(silhouette, with: .color(tint.opacity(0.42)))
        skyline.fill(
            Path(CGRect(x: 0, y: base, width: size.width, height: size.height - base)),
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.18), Color.black.opacity(0.2)]),
                startPoint: CGPoint(x: size.width / 2, y: base),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
        for index in 0..<12 {
            let wx = size.width * (0.12 + CGFloat(index % 6) * 0.13)
            let wy = base - size.height * (0.08 + CGFloat(index / 6) * 0.1)
            let twinkle = RecapSceneMotion.phase(3.8, at: motion + Double(index) * 0.37)
            skyline.fill(
                Path(CGRect(x: wx, y: wy, width: 4, height: 7)),
                with: .color(glow.opacity(0.28 + 0.45 * Double(twinkle)))
            )
        }
    }

    private func drawRoute(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.46, tint: tint)
        var arc = Path()
        let start = CGPoint(x: size.width * 0.16, y: size.height * 0.62)
        let end = CGPoint(x: size.width * 0.84, y: size.height * 0.48)
        let control = CGPoint(x: size.width * 0.5, y: size.height * 0.22)
        arc.move(to: start)
        arc.addQuadCurve(to: end, control: control)
        context.stroke(arc, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let travel = RecapSceneMotion.saw(5.5, at: motion)
        let highlight = quadPoint(start: start, end: end, control: control, t: travel)
        context.fill(
            Path(ellipseIn: CGRect(x: highlight.x - 5, y: highlight.y - 5, width: 10, height: 10)),
            with: .color(.white.opacity(0.85))
        )
        let bob = RecapSceneMotion.signedPhase(5.5, at: motion) * 8
        drawPin(context: &context, at: CGPoint(x: start.x, y: start.y + bob), color: glow)
        drawPin(context: &context, at: CGPoint(x: end.x, y: end.y - bob), color: tint)
    }

    private func drawTime(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.5, tint: tint, asphaltOpacity: 0.45)
        let driftX = RecapSceneMotion.signedPhase(8, at: motion) * 12
        let driftY = RecapSceneMotion.signedPhase(6.5, at: motion) * 8
        let moon = CGRect(x: size.width * 0.18 + driftX, y: size.height * 0.14 + driftY, width: 58, height: 58)
        context.fill(Path(ellipseIn: moon), with: .color(.white.opacity(0.9)))
        context.fill(
            Path(ellipseIn: moon.offsetBy(dx: 16, dy: -4)),
            with: .color(Color.black.opacity(scheme == .dark ? 0.45 : 0.18))
        )
        let stars = [0.42, 0.55, 0.68, 0.78, 0.32, 0.88]
        for (index, xRatio) in stars.enumerated() {
            let y = size.height * (0.12 + CGFloat(index % 3) * 0.07)
            let twinkle = RecapSceneMotion.phase(3.6, at: motion + Double(index) * 0.9)
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * xRatio, y: y, width: 3, height: 3)),
                with: .color(.white.opacity(0.35 + 0.5 * Double(twinkle)))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.62, y: size.height * 0.22, width: 10, height: 10)),
            with: .color(glow.opacity(0.55 + 0.25 * Double(RecapSceneMotion.phase(8, at: motion))))
        )
    }

    private func drawCategories(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let horizonY = size.height * 0.40
        drawVanishingRoad(context: &context, size: size, horizonY: horizonY, tint: tint)
        let reveal = RecapIntroReveal.yearOpacity(elapsed: pageElapsed, reduceMotion: reduceMotion)
        let painted = CGFloat(min(1, max(0, purposeShare))) * CGFloat(reveal)
        let horizon = CGPoint(x: size.width * 0.5, y: horizonY)
        let roadHeight = size.height - horizonY
        guard painted > 0.02, roadHeight > 0 else { return }
        let endY = horizonY + roadHeight * painted
        let t = min(1, max(0, (endY - horizonY) / roadHeight))
        let leftX = size.width * 0.5 + (-size.width * 0.08 - size.width * 0.5) * t
        let rightX = size.width * 0.5 + (size.width * 1.08 - size.width * 0.5) * t
        var wash = Path()
        wash.move(to: horizon)
        wash.addLine(to: CGPoint(x: rightX, y: endY))
        wash.addLine(to: CGPoint(x: leftX, y: endY))
        wash.closeSubpath()
        context.fill(
            wash,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.18), tint.opacity(0.55)]),
                startPoint: horizon,
                endPoint: CGPoint(x: size.width * 0.5, y: endY)
            )
        )
        let remainder = 1 - painted
        if remainder > 0.04 {
            let ribbon = StatsChartTheme.forecastSparklineStrokeRGB(scheme: scheme, palette: palette).color
            let inner = 0.08 + 0.18 * (1 - t)
            var stripe = Path()
            stripe.move(to: CGPoint(x: rightX - size.width * inner, y: endY))
            stripe.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 1.02))
            context.stroke(
                stripe,
                with: .color(ribbon.opacity(0.55 + 0.2 * Double(RecapSceneMotion.phase(6, at: motion)))),
                style: StrokeStyle(lineWidth: 3.5 + 6 * (1 - t), lineCap: .round)
            )
        }
        let bloom = 10 + 28 * RecapSceneMotion.phase(6, at: motion)
        context.fill(
            Path(ellipseIn: CGRect(x: horizon.x - bloom, y: horizon.y - bloom * 0.5, width: bloom * 2, height: bloom)),
            with: .radialGradient(
                Gradient(colors: [glow.opacity(0.35), .clear]),
                center: horizon,
                startRadius: 2,
                endRadius: bloom
            )
        )
    }

    private func drawCost(context: inout GraphicsContext, size: CGSize, tint _: Color, glow: Color) {
        let fuelColor = RecapSpendInk.fuel(scheme: scheme, palette: palette)
        let expenseColor = RecapSpendInk.expenses(scheme: scheme, palette: palette)
        let showFuel = estimatedFuelCost > 0
        let showExpenses = paidExpenses > 0
        let both = showFuel && showExpenses
        let pumpHeight = RecapCostLayout.pumpHeight(in: size)
        let groupTop = RecapCostLayout.groupTop(in: size)
        let pad = CGRect(
            x: size.width * 0.18,
            y: groupTop + pumpHeight - 22,
            width: size.width * 0.64,
            height: 28
        )
        context.fill(
            Path(ellipseIn: pad),
            with: .color(Color.black.opacity(scheme == .dark ? 0.28 : 0.12))
        )
        if both {
            drawPump(
                context: &context,
                in: RecapCostLayout.pumpRect(in: size, both: true, isLeading: true),
                color: fuelColor,
                glow: glow,
                hoseToTrailing: false,
                motionOffset: 0
            )
            drawPump(
                context: &context,
                in: RecapCostLayout.pumpRect(in: size, both: true, isLeading: false),
                color: expenseColor,
                glow: glow,
                hoseToTrailing: true,
                motionOffset: 0.85
            )
        } else if showFuel {
            drawPump(
                context: &context,
                in: RecapCostLayout.pumpRect(in: size, both: false, isLeading: true),
                color: fuelColor,
                glow: glow,
                hoseToTrailing: true,
                motionOffset: 0
            )
        } else if showExpenses {
            drawPump(
                context: &context,
                in: RecapCostLayout.pumpRect(in: size, both: false, isLeading: true),
                color: expenseColor,
                glow: glow,
                hoseToTrailing: true,
                motionOffset: 0.4
            )
        }
    }

    private func drawPump(
        context: inout GraphicsContext,
        in rect: CGRect,
        color: Color,
        glow: Color,
        hoseToTrailing: Bool,
        motionOffset: Double
    ) {
        let sway = RecapSceneMotion.signedPhase(4.8, at: motion + motionOffset)
        let pulse = RecapSceneMotion.phase(3.6, at: motion + motionOffset)
        let shadow = CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.maxY - 12,
            width: rect.width * 0.80,
            height: 18
        )
        context.fill(Path(ellipseIn: shadow), with: .color(Color.black.opacity(scheme == .dark ? 0.38 : 0.18)))

        let plinth = CGRect(
            x: rect.minX + rect.width * 0.14,
            y: rect.maxY - rect.height * 0.13,
            width: rect.width * 0.72,
            height: rect.height * 0.11
        )
        context.fill(Path(roundedRect: plinth, cornerRadius: 5), with: .color(color.opacity(0.38)))
        context.fill(
            Path(roundedRect: plinth.insetBy(dx: 6, dy: 3), cornerRadius: 3),
            with: .color(.white.opacity(0.12))
        )

        let body = CGRect(
            x: rect.minX + rect.width * 0.20,
            y: rect.minY + rect.height * 0.06,
            width: rect.width * 0.50,
            height: rect.height * 0.78
        )
        context.fill(
            Path(roundedRect: body, cornerRadius: 11),
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0.98),
                    color.opacity(0.62),
                    Color.black.opacity(scheme == .dark ? 0.35 : 0.18)
                ]),
                startPoint: CGPoint(x: body.minX, y: body.minY),
                endPoint: CGPoint(x: body.maxX, y: body.maxY)
            )
        )
        context.stroke(Path(roundedRect: body, cornerRadius: 11), with: .color(.white.opacity(0.22)), lineWidth: 1)
        let band = CGRect(x: body.minX, y: body.minY + body.height * 0.46, width: body.width, height: 7)
        context.fill(Path(band), with: .color(.white.opacity(0.24)))
        context.fill(
            Path(CGRect(x: body.minX + 6, y: body.minY + body.height * 0.62, width: body.width - 12, height: 4)),
            with: .color(.white.opacity(0.12))
        )

        let display = CGRect(
            x: body.minX + 9,
            y: body.minY + 12,
            width: body.width - 18,
            height: body.height * 0.24
        )
        context.fill(Path(roundedRect: display, cornerRadius: 6), with: .color(Color.black.opacity(0.5)))
        context.fill(
            Path(ellipseIn: display.insetBy(dx: -8, dy: -10)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.45 + 0.3 * Double(pulse)), .clear]),
                center: CGPoint(x: display.midX, y: display.midY),
                startRadius: 2,
                endRadius: 28
            )
        )
        context.fill(
            Path(roundedRect: display.insetBy(dx: 3, dy: 3), cornerRadius: 4),
            with: .color(color.opacity(0.55 + 0.35 * Double(pulse)))
        )
        context.fill(
            Path(roundedRect: CGRect(x: display.minX + 6, y: display.minY + 5, width: display.width * 0.38, height: 5), cornerRadius: 2),
            with: .color(.white.opacity(0.45))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: display.maxX - 14, y: display.midY - 3, width: 6, height: 6)),
            with: .color(glow.opacity(0.7 + 0.25 * Double(pulse)))
        )

        let holsterX = hoseToTrailing ? body.maxX - 5 : body.minX - 9
        let holster = CGRect(x: holsterX, y: body.minY + body.height * 0.38, width: 14, height: 24)
        context.fill(Path(roundedRect: holster, cornerRadius: 3), with: .color(Color.black.opacity(0.35)))
        context.stroke(Path(roundedRect: holster, cornerRadius: 3), with: .color(.white.opacity(0.2)), lineWidth: 1)

        let hoseStart = CGPoint(x: hoseToTrailing ? body.maxX - 2 : body.minX + 2, y: body.minY + body.height * 0.42)
        let outward: CGFloat = hoseToTrailing ? 1 : -1
        let hoseEnd = CGPoint(
            x: hoseStart.x + outward * (rect.width * 0.28),
            y: body.maxY - 18 + 12 * sway
        )
        let hoseControl = CGPoint(
            x: hoseStart.x + outward * (rect.width * 0.34),
            y: body.minY + 18 + 14 * sway
        )
        var hose = Path()
        hose.move(to: hoseStart)
        hose.addQuadCurve(to: hoseEnd, control: hoseControl)
        context.stroke(hose, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        context.stroke(hose, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

        let nozzle = CGRect(x: hoseEnd.x - 7, y: hoseEnd.y - 5, width: 18, height: 12)
        context.fill(Path(roundedRect: nozzle, cornerRadius: 3), with: .color(color.opacity(0.95)))
        context.fill(
            Path(roundedRect: CGRect(x: nozzle.maxX - 6, y: nozzle.minY + 3, width: 8, height: 6), cornerRadius: 2),
            with: .color(.white.opacity(0.35))
        )
        if pulse > 0.35 {
            let dripY = hoseEnd.y + 10 + 6 * pulse
            context.fill(
                Path(ellipseIn: CGRect(x: hoseEnd.x - 2.5, y: dripY, width: 5, height: 7)),
                with: .color(color.opacity(0.55 * Double(pulse)))
            )
        }
    }

    private func drawBadges(context: inout GraphicsContext, size: CGSize, tint _: Color, glow: Color) {
        let ids = Array(badgeIDs.prefix(RecapStoryBadgeLayout.maxVisible))
        guard !ids.isEmpty else { return }
        let slots = RecapStoryBadgeLayout.slots(in: size, count: ids.count)
        let medal = RecapStoryBadgeLayout.medalSize(in: size, count: ids.count)
        for (index, id) in ids.enumerated() {
            let offset = RecapStoryBadgeLayout.offsetY(index: index, motion: motion, reduceMotion: false)
            let rect = RecapStoryBadgeLayout.medalRect(in: slots[index], medal: medal, offsetY: offset)
            let pulse = RecapSceneMotion.phase(2.4, at: motion + Double(index) * 0.28)
            let accent = AchievementTheme.medalGlow(for: id, scheme: scheme)
            let haloPad = medal * 0.58
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: -haloPad, dy: -haloPad)),
                with: .radialGradient(
                    Gradient(colors: [
                        accent.opacity(0.5 + 0.32 * Double(pulse)),
                        accent.opacity(0.16),
                        .clear
                    ]),
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    startRadius: medal * 0.12,
                    endRadius: medal * 1.05
                )
            )
            let sparkleCount = 5
            for sparkle in 0..<sparkleCount {
                let twinkle = RecapSceneMotion.phase(
                    1.35 + Double(sparkle) * 0.18,
                    at: motion + Double(index) * 0.21 + Double(sparkle) * 0.33
                )
                guard twinkle > 0.16 else { continue }
                let spin = RecapSceneMotion.saw(9.5, at: motion + Double(index) * 0.4) * .pi * 2
                let angle = (CGFloat(sparkle) / CGFloat(sparkleCount)) * .pi * 2 + CGFloat(index) * 0.35 + spin * 0.12
                let radius = medal * (0.68 + 0.14 * twinkle)
                let point = CGPoint(
                    x: rect.midX + cos(angle) * radius,
                    y: rect.midY + sin(angle) * radius
                )
                drawSparkle(
                    context: &context,
                    at: point,
                    brightness: twinkle,
                    color: sparkle.isMultiple(of: 2) ? accent : glow,
                    scale: 1.05
                )
            }
        }
    }

    private func drawClosing(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let horizonY = size.height * 0.40
        drawVanishingRoad(context: &context, size: size, horizonY: horizonY, tint: tint)
        drawPlate(context: &context, size: size, tint: tint, glow: glow, yRatio: 0.12)

        let recede = 0.72 + 0.28 * RecapSceneMotion.phase(7, at: motion)
        let bob = RecapSceneMotion.signedPhase(5.5, at: motion) * 8
        let carW = size.width * 0.14 * recede
        let carH = size.height * 0.036 * recede
        let body = CGRect(
            x: size.width * 0.5 - carW / 2,
            y: horizonY + size.height * 0.05 + bob,
            width: carW,
            height: carH
        )
        var cabin = Path()
        cabin.move(to: CGPoint(x: body.minX + carW * 0.18, y: body.minY + carH * 0.35))
        cabin.addLine(to: CGPoint(x: body.minX + carW * 0.28, y: body.minY))
        cabin.addLine(to: CGPoint(x: body.maxX - carW * 0.28, y: body.minY))
        cabin.addLine(to: CGPoint(x: body.maxX - carW * 0.18, y: body.minY + carH * 0.35))
        cabin.closeSubpath()
        context.fill(Path(roundedRect: body, cornerRadius: carH * 0.35), with: .color(.black.opacity(scheme == .dark ? 0.55 : 0.38)))
        context.fill(cabin, with: .color(tint.opacity(0.55)))
        let lampPulse = 0.45 + 0.55 * RecapSceneMotion.phase(5.5, at: motion)
        let lampW = max(4, carW * 0.12)
        let lampH = max(3, carH * 0.28)
        let lampY = body.midY - lampH / 2
        context.fill(
            Path(ellipseIn: CGRect(x: body.minX + carW * 0.12, y: lampY, width: lampW, height: lampH)),
            with: .color(Color.red.opacity(0.35 + 0.45 * lampPulse))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: body.maxX - carW * 0.12 - lampW, y: lampY, width: lampW, height: lampH)),
            with: .color(Color.red.opacity(0.35 + 0.45 * lampPulse))
        )
        var trail = Path()
        let trailY = body.midY
        trail.move(to: CGPoint(x: body.minX + carW * 0.18, y: trailY))
        trail.addLine(to: CGPoint(x: body.minX - size.width * 0.04, y: trailY + size.height * 0.12))
        trail.move(to: CGPoint(x: body.maxX - carW * 0.18, y: trailY))
        trail.addLine(to: CGPoint(x: body.maxX + size.width * 0.04, y: trailY + size.height * 0.12))
        context.stroke(
            trail,
            with: .color(glow.opacity(0.18 + 0.22 * Double(lampPulse))),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    private func drawVanishingRoad(
        context: inout GraphicsContext,
        size: CGSize,
        horizonY: CGFloat,
        tint _: Color,
        asphaltOpacity: Double = 0.28
    ) {
        let horizon = CGPoint(x: size.width * 0.5, y: horizonY)
        var asphalt = Path()
        asphalt.move(to: horizon)
        asphalt.addLine(to: CGPoint(x: size.width * 1.08, y: size.height * 1.02))
        asphalt.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * 1.02))
        asphalt.closeSubpath()
        context.fill(asphalt, with: .color(Color.black.opacity(scheme == .dark ? asphaltOpacity : 0.16)))
        context.stroke(edge(from: horizon, to: CGPoint(x: size.width * 0.08, y: size.height)), with: .color(.white.opacity(0.35)), lineWidth: 2)
        context.stroke(edge(from: horizon, to: CGPoint(x: size.width * 0.92, y: size.height)), with: .color(.white.opacity(0.35)), lineWidth: 2)
        let shift = RecapSceneMotion.saw(4, at: motion)
        for step in 0..<8 {
            let unit = (CGFloat(step) / 8 + shift).truncatingRemainder(dividingBy: 1)
            let y = horizon.y + (size.height - horizon.y) * unit
            let width = 5 + 18 * unit
            let rect = CGRect(x: horizon.x - width / 2, y: y, width: width, height: 5 + 8 * unit)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.12 + 0.45 * Double(unit))))
        }
    }

    private func drawPlate(
        context: inout GraphicsContext,
        size: CGSize,
        tint: Color,
        glow: Color,
        yRatio: CGFloat = 0.2
    ) {
        let plate = CGRect(x: size.width * 0.36, y: size.height * yRatio, width: size.width * 0.28, height: size.width * 0.28)
        context.fill(Path(roundedRect: plate, cornerRadius: plate.width * 0.22), with: .color(tint.opacity(0.9)))
        context.stroke(Path(roundedRect: plate, cornerRadius: plate.width * 0.22), with: .color(.white.opacity(0.28)), lineWidth: 1.5)
        context.fill(
            Path(ellipseIn: CGRect(x: plate.midX - 10, y: plate.midY - 10, width: 20, height: 20)),
            with: .color(glow.opacity(0.85))
        )
    }

    private func drawPin(context: inout GraphicsContext, at point: CGPoint, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 22, width: 18, height: 18)), with: .color(color))
        var stem = Path()
        stem.move(to: CGPoint(x: point.x, y: point.y - 6))
        stem.addLine(to: point)
        context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private func quadPoint(start: CGPoint, end: CGPoint, control: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    private func point(on center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle.radians)),
            y: center.y + radius * CGFloat(sin(angle.radians))
        )
    }

    private func edge(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}
