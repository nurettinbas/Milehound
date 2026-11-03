import SwiftUI

enum AchievementGalleryTokens {
    static let cardRadius: CGFloat = 16
    static let cardHeight: CGFloat = 212
    static let accessibilityMinHeight: CGFloat = 236
    static let medalSize: CGFloat = 48
    static let expandedMedalSize: CGFloat = 128
    static let compactMedalSize: CGFloat = 44
    static let compactCellWidth: CGFloat = 52
    static let compactCellHeight: CGFloat = 56
    static let compactSpacing: CGFloat = 10
    static let compactLineSpacing: CGFloat = 8
    /// Unlock overlay dwell before the next unseen badge.
    static let unlockDwell: TimeInterval = 3
    static let shareSlotHeight: CGFloat = 44
    static let titleSlotHeight: CGFloat = 28
    static let bodySlotHeight: CGFloat = 32
    static let statusSlotHeight: CGFloat = 14
}

/// Maps the Stats badges card onto the full-screen overlay. Grow/shrink the same
/// rounded rect — never a sheet insert.
enum AchievementGalleryExpandLayout {
    static let collapsedCornerRadius = StatsCardTokens.radius
    static let expandedCornerRadius: CGFloat = 0
    static let minimumSourceLength: CGFloat = 8

    static func localSurface(sourceGlobal: CGRect, overlayGlobal: CGRect, expanded: Bool) -> CGRect {
        let container = CGRect(origin: .zero, size: overlayGlobal.size)
        if expanded { return container }
        guard sourceGlobal.width >= minimumSourceLength, sourceGlobal.height >= minimumSourceLength else {
            return container
        }
        return CGRect(
            x: sourceGlobal.minX - overlayGlobal.minX,
            y: sourceGlobal.minY - overlayGlobal.minY,
            width: sourceGlobal.width,
            height: sourceGlobal.height
        )
    }

    static func cornerRadius(expanded: Bool) -> CGFloat {
        expanded ? expandedCornerRadius : collapsedCornerRadius
    }

    static func hasUsableSource(_ source: CGRect) -> Bool {
        source.width >= minimumSourceLength && source.height >= minimumSourceLength
    }

    /// Hidden Recap tab reports a real-sized frame under the status bar.
    /// That is not the card the expand spring should grow from.
    static func isOnScreenCard(
        _ source: CGRect,
        windowBounds: CGRect,
        topInset: CGFloat
    ) -> Bool {
        guard hasUsableSource(source) else { return false }
        guard windowBounds.width > 1, windowBounds.height > 1 else { return false }
        guard source.minY >= windowBounds.minY + topInset else { return false }
        let visible = source.intersection(windowBounds)
        guard visible.width >= minimumSourceLength else { return false }
        let needed = min(source.height, 88)
        return visible.height >= needed * 0.5
    }
}

/// Leading-edge swipe that runs the same shrink as the expand close button.
enum CardExpandBackSwipe {
    static let edge: CGFloat = 28
    /// Space under the status inset so the swipe strip does not cover the close circle.
    static let headerClearance: CGFloat = 56
    static let distance: CGFloat = 64

    static func shouldDismiss(travel: CGFloat, predicted: CGFloat, vertical: CGFloat) -> Bool {
        guard travel > abs(vertical) else { return false }
        return travel > distance || predicted > distance * 2
    }
}

/// Clear leading strip. Horizontal drags here close the expanded Recap card.
struct CardExpandBackSwipeStrip: View {
    var enabled: Bool
    var topClearance: CGFloat
    var onClose: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HStack(spacing: 0) {
            if layoutDirection == .rightToLeft {
                Spacer(minLength: 0).allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topClearance)
                    .allowsHitTesting(false)
                Color.clear
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(swipe)
            }
            .frame(width: CardExpandBackSwipe.edge)
            if layoutDirection != .rightToLeft {
                Spacer(minLength: 0).allowsHitTesting(false)
            }
        }
        .allowsHitTesting(enabled)
        .accessibilityHidden(true)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard enabled else { return }
                let travel = layoutDirection == .rightToLeft
                    ? -value.translation.width
                    : value.translation.width
                let predicted = layoutDirection == .rightToLeft
                    ? -value.predictedEndTranslation.width
                    : value.predictedEndTranslation.width
                guard CardExpandBackSwipe.shouldDismiss(
                    travel: travel,
                    predicted: predicted,
                    vertical: value.translation.height
                ) else { return }
                onClose()
            }
    }
}

/// Shell-independent family colors for round medals only — cards stay glass.
/// Km medals use metal materials; other families use enamel (family hue) in the same 3D chrome.
enum AchievementTheme {
    /// Black wash over a full-color medal so locked discs stay saturated, not washed out.
    static let lockScrimOpacity: Double = 0.45

    static func familyHue(for family: AchievementFamily) -> Double {
        switch family {
        case .longhaul: 5
        case .streak: 24
        case .business: 44
        case .dawn: 62
        case .firstTrip: 142
        case .fleet: 160
        case .distance: 178
        case .hours: 196
        case .cities: 214
        case .countries: 234
        case .night: 252
        case .routes: 274
        case .weekend: 304
        case .trips: 332
        }
    }

    /// Ladder rungs shift hue so unlocked siblings are not clones. Km uses metals instead.
    static func enamelHue(for id: AchievementID) -> Double {
        let base = familyHue(for: id.family)
        return (base + 8 * Double(id.familyTier) + 360).truncatingRemainder(dividingBy: 360)
    }

    static let minimumFamilyHueDelta: Double = 18

    static func familyAccent(for id: AchievementID, scheme: ColorScheme, unlocked: Bool) -> Color {
        hsl(
            hue: enamelHue(for: id),
            saturation: saturation(for: id, unlocked: unlocked, scheme: scheme),
            lightness: accentLightness(scheme: scheme, unlocked: unlocked)
        )
    }

    static func familyHighlight(for id: AchievementID, scheme: ColorScheme, unlocked: Bool) -> Color {
        hsl(
            hue: enamelHue(for: id),
            saturation: saturation(for: id, unlocked: unlocked, scheme: scheme) * 0.9,
            lightness: min(0.86, accentLightness(scheme: scheme, unlocked: unlocked) + 0.16)
        )
    }

    static func medalPalette(for id: AchievementID, scheme: ColorScheme) -> AchievementMedalPalette {
        if let material = id.medalMaterial {
            return metalPalette(material, scheme: scheme)
        }
        let accent = familyAccent(for: id, scheme: scheme, unlocked: true)
        let highlight = familyHighlight(for: id, scheme: scheme, unlocked: true)
        let hue = enamelHue(for: id)
        let sat = saturation(for: id, unlocked: true, scheme: scheme)
        let light = accentLightness(scheme: scheme, unlocked: true)
        return AchievementMedalPalette(
            faceHighlight: highlight,
            faceAccent: accent,
            rimHighlight: hsl(hue: hue, saturation: sat * 0.55, lightness: min(0.92, light + 0.28)),
            rimAccent: hsl(hue: hue, saturation: min(0.88, sat + 0.08), lightness: max(0.18, light - 0.14)),
            glyph: .white,
            glow: accent,
            specularOpacity: 0.35
        )
    }

    static func medalGlow(for id: AchievementID, scheme: ColorScheme) -> Color {
        medalPalette(for: id, scheme: scheme).glow
    }

    static func medalFill(for id: AchievementID, scheme: ColorScheme) -> LinearGradient {
        let palette = medalPalette(for: id, scheme: scheme)
        var colors = [palette.faceHighlight, palette.faceAccent]
        if let extra = palette.iridescent {
            colors = [palette.faceHighlight, extra, palette.faceAccent]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private static func metalPalette(_ material: AchievementMedalMaterial, scheme: ColorScheme) -> AchievementMedalPalette {
        let dark = scheme == .dark
        switch material {
        case .silver:
            return AchievementMedalPalette(
                faceHighlight: hex(dark ? 0xA8B0B8 : 0xC8D0D8),
                faceAccent: hex(dark ? 0x6A747E : 0x8A949E),
                rimHighlight: hex(dark ? 0xD8DEE4 : 0xF2F5F7),
                rimAccent: hex(dark ? 0x4A5258 : 0x6E767E),
                glyph: .white,
                glow: hex(dark ? 0xA8B0B8 : 0xC8D0D8),
                specularOpacity: 0.55
            )
        case .gold:
            return AchievementMedalPalette(
                faceHighlight: hex(dark ? 0xD4A84A : 0xF3D08A),
                faceAccent: hex(dark ? 0x9A6A12 : 0xC48A1A),
                rimHighlight: hex(dark ? 0xE8C878 : 0xFFE9B0),
                rimAccent: hex(dark ? 0x6A4408 : 0x8A5A10),
                glyph: .white,
                glow: hex(dark ? 0xD4A84A : 0xF3D08A),
                specularOpacity: 0.45
            )
        case .platinum:
            // 10,000 km — saturated teal chrome (not gray metal).
            let highlight = hex(dark ? AchievementPlatinumSwatch.faceHighlightDark : AchievementPlatinumSwatch.faceHighlightLight)
            let accent = hex(dark ? AchievementPlatinumSwatch.faceAccentDark : AchievementPlatinumSwatch.faceAccentLight)
            return AchievementMedalPalette(
                faceHighlight: highlight,
                faceAccent: accent,
                rimHighlight: hex(dark ? 0xB8FFF8 : 0xE8FFFC),
                rimAccent: hex(dark ? 0x087F78 : 0x0A9088),
                glyph: .white,
                glow: highlight,
                specularOpacity: 0.50
            )
        case .diamond:
            // 100,000 km — saturated lavender chrome (not icy blue).
            let highlight = hex(dark ? AchievementDiamondSwatch.faceHighlightDark : AchievementDiamondSwatch.faceHighlightLight)
            let accent = hex(dark ? AchievementDiamondSwatch.faceAccentDark : AchievementDiamondSwatch.faceAccentLight)
            return AchievementMedalPalette(
                faceHighlight: highlight,
                faceAccent: accent,
                rimHighlight: hex(dark ? 0xF3E8FF : 0xFBF5FF),
                rimAccent: hex(dark ? 0x7C3AED : 0x8B5CF6),
                glyph: .white,
                glow: highlight,
                specularOpacity: 0.50
            )
        }
    }

    private static func saturation(for id: AchievementID, unlocked: Bool, scheme: ColorScheme) -> Double {
        let base: Double
        switch id.familyTier {
        case 3: base = 0.82
        case 2: base = 0.78
        case 1: base = 0.68
        default: base = 0.58
        }
        let lockedDrop = unlocked ? 0 : 0.12
        let darkBoost = scheme == .dark ? 0.06 : 0
        return min(0.88, max(0.28, base - lockedDrop + darkBoost))
    }

    private static func accentLightness(scheme: ColorScheme, unlocked: Bool) -> Double {
        if scheme == .dark {
            return unlocked ? 0.58 : 0.50
        }
        return unlocked ? 0.48 : 0.42
    }

    static func hex(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// HSL with h in 0...360, s/l in 0...1.
    static func hsl(hue: Double, saturation: Double, lightness: Double) -> Color {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(1, max(0, saturation))
        let l = min(1, max(0, lightness))
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let r: Double
        let g: Double
        let b: Double
        switch h * 6 {
        case 0..<1: r = c; g = x; b = 0
        case 1..<2: r = x; g = c; b = 0
        case 2..<3: r = 0; g = c; b = x
        case 3..<4: r = 0; g = x; b = c
        case 4..<5: r = x; g = 0; b = c
        default: r = c; g = 0; b = x
        }
        return Color(red: r + m, green: g + m, blue: b + m)
    }
}

/// 10,000 km platinum face — teal, not gray.
enum AchievementPlatinumSwatch {
    static let faceHighlightDark: UInt32 = 0x3EDDD4
    static let faceAccentDark: UInt32 = 0x14B2AA
    static let faceHighlightLight: UInt32 = 0x52E8E0
    static let faceAccentLight: UInt32 = 0x20C4BC
}

/// 100,000 km diamond face — lavender, not ice blue.
enum AchievementDiamondSwatch {
    static let faceHighlightDark: UInt32 = 0xD8B4FE
    static let faceAccentDark: UInt32 = 0xB794F6
    static let faceHighlightLight: UInt32 = 0xE9D5FF
    static let faceAccentLight: UInt32 = 0xC4B5FD
}

struct AchievementMedalPalette {
    let faceHighlight: Color
    let faceAccent: Color
    let rimHighlight: Color
    let rimAccent: Color
    let glyph: Color
    let glow: Color
    let specularOpacity: Double
    var iridescent: Color? = nil
}

/// Bezel, face, specular, and inner shade — one recipe for metal km medals and enamel families.
struct AchievementMedalChrome: View {
    let id: AchievementID
    var size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.achievementIdleTime) private var idleTime

    var body: some View {
        let palette = AchievementTheme.medalPalette(for: id, scheme: colorScheme)
        let inset = max(2, size * 0.08)
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.rimHighlight, palette.rimAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(AchievementTheme.medalFill(for: id, scheme: colorScheme))
                .padding(inset)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(inset)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(palette.specularOpacity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.28
                    )
                )
                .frame(width: size * 0.55, height: size * 0.28)
                .offset(x: -size * 0.08 + specularNudge, y: -size * 0.22)
                .allowsHitTesting(false)
            Circle()
                .strokeBorder(palette.rimHighlight.opacity(0.55), lineWidth: max(1, size * 0.035))
                .padding(inset * 0.45)
        }
        .frame(width: size, height: size)
    }

    private var specularNudge: CGFloat {
        guard let idleTime, !reduceMotion else { return 0 }
        let phase = AchievementMedalIdle.pingPong(at: idleTime, duration: 2.4)
        return (phase - 0.5) * 0.06 * size
    }
}

/// Idle motion for unlocked medals. Flag waves; distance nodes travel the S; night sky bobs and sparkles.
enum AchievementMedalIdle {
    static let flagWaveDuration: TimeInterval = 0.72
    static let flagWaveSwayDegrees: Double = 36
    static let flagWaveFold: CGFloat = 0.24
    static let flagWaveFlapDegrees: Double = 12

    static var pathTravelDuration: TimeInterval { AchievementDistancePathMotion.convoy.duration }
    static let nightBobDuration: TimeInterval = 1.8
    static let nightSparkleDuration: TimeInterval = 0.55
    /// List-safe idle rate. `CADisplayLink` (not `Task.sleep` / `TimelineView`) drives this.
    static let compactClockFPS: Int = 12
    static var compactClockInterval: TimeInterval { 1.0 / TimeInterval(compactClockFPS) }

    /// One-way drift of the moon and stars. Disc stays put.
    static func nightBobAmplitude(for size: CGFloat) -> CGFloat {
        min(4, max(2, size * 0.06))
    }

    static func discTilts(_ family: AchievementFamily) -> Bool {
        switch family {
        case .routes, .weekend, .fleet: true
        default: false
        }
    }

    static func glyphOverflows(_ family: AchievementFamily) -> Bool {
        switch family {
        case .firstTrip, .distance, .night, .dawn, .streak, .hours, .longhaul: true
        default: false
        }
    }

    static func period(for family: AchievementFamily) -> TimeInterval {
        switch family {
        case .streak: 1.6
        case .business: 1.35
        case .cities: 2.4
        case .routes: 2.0
        case .trips: 2.1
        case .hours: 2.7
        case .longhaul: 2.5
        case .dawn: 2.2
        case .weekend: 2.4
        case .fleet: 1.8
        case .countries: 4.0
        case .night: 2.2
        case .firstTrip: 2.8
        case .distance: 2.4
        }
    }

    /// Steering wheel yaw, one side. Ping-pong is left then right — not a full spin.
    static let steeringSwayDegrees: Double = 20

    static func steeringSway(phase: CGFloat) -> Double {
        (Double(phase) - 0.5) * 2 * steeringSwayDegrees
    }

    /// One pour is 180° on X (top becomes bottom). Ping-pong reads as turn over, then back.
    static func hourglassFlipDegrees(phase: CGFloat) -> Double {
        Double(phase) * 180
    }

    /// Hill cruise on the disc (ping-pong). The car stays fully visible — never a rim fade.
    static let longhaulHill: CGFloat = 0.16
    static let longhaulCruise: CGFloat = 0.10
    static let longhaulPitchDegrees: Double = 14

    static func longhaulCruiseX(phase: CGFloat, size: CGFloat) -> CGFloat {
        (phase - 0.5) * size * longhaulCruise
    }

    static func longhaulHillY(phase: CGFloat, size: CGFloat) -> CGFloat {
        CGFloat(-sin(Double(phase) * .pi)) * size * longhaulHill
    }

    /// Side-view nose follows the slope: up on the climb, down on the descent.
    static func longhaulNosePitch(phase: CGFloat) -> Double {
        -cos(Double(phase) * .pi) * longhaulPitchDegrees
    }

    /// 0...1 looping (not ping-pong) for globe.
    static func loop(at time: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0, time.isFinite else { return 0 }
        let t = time.truncatingRemainder(dividingBy: duration)
        return CGFloat((t + duration).truncatingRemainder(dividingBy: duration) / duration)
    }

    /// Eased 0...1...0. Time-driven idle when a parent publishes `achievementIdleTime`.
    static func pingPong(at time: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0, time.isFinite else { return 0 }
        let cycle = time.truncatingRemainder(dividingBy: duration * 2)
        let linear = cycle < duration ? cycle / duration : 2 - cycle / duration
        return CGFloat(0.5 - 0.5 * cos(linear * .pi))
    }
}

private struct AchievementIdleTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    var achievementIdleTime: TimeInterval? {
        get { self[AchievementIdleTimeKey.self] }
        set { self[AchievementIdleTimeKey.self] = newValue }
    }
}

/// Idle `t` via `CADisplayLink` (same host as the recording road). `TimelineView` and
/// `.task` + `Task.sleep` both pause inside a `List`, which froze medals on a stale tick.
private struct AchievementIdleClockModifier: ViewModifier {
    var isEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var tick: TimeInterval?

    func body(content: Content) -> some View {
        content
            .environment(\.achievementIdleTime, publishesClock ? (tick ?? Date.timeIntervalSinceReferenceDate) : nil)
            .overlay(alignment: .topLeading) {
                MilehoundDisplayLinkTicker(
                    isRunning: publishesClock,
                    framesPerSecond: framesPerSecond
                ) { tick = $0 }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: publishesClock) { _, on in
                tick = on ? Date.timeIntervalSinceReferenceDate : nil
            }
    }

    private var publishesClock: Bool {
        isEnabled && scenePhase == .active && !UITestSupport.isEnabled
    }

    private var framesPerSecond: Int {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 8 : AchievementMedalIdle.compactClockFPS
    }
}

extension View {
    func achievementIdleClock(enabled: Bool) -> some View {
        modifier(AchievementIdleClockModifier(isEnabled: enabled))
    }

    /// List / theme transactions must not interpolate clock-driven pose (looks stuck).
    func achievementIdleClockPose(drivenByClock: Bool) -> some View {
        transaction { transaction in
            if drivenByClock {
                transaction.animation = nil
            }
        }
    }
}

/// Race-flag flutter: rotate and fold from the leading edge (the pole).
struct AchievementFlagWaveEffect: ViewModifier {
    var isActive: Bool
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var waving = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(swayDegrees),
                axis: (x: 0.22, y: 1, z: 0.14),
                anchor: .leading,
                perspective: 0.32
            )
            .rotationEffect(.degrees(flapDegrees), anchor: .leading)
            .scaleEffect(x: foldScale, y: 1, anchor: .leading)
            .achievementIdleClockPose(drivenByClock: idleTime != nil)
            .onAppear(perform: start)
            .onChange(of: isActive) { _, _ in
                start()
            }
            .onChange(of: idleTime != nil) { _, _ in
                start()
            }
    }

    private var phase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.flagWaveDuration)
        }
        return waving ? 1 : 0
    }

    private var swayDegrees: Double {
        guard isActive else { return 0 }
        return -AchievementMedalIdle.flagWaveSwayDegrees * 0.7
            + Double(phase) * AchievementMedalIdle.flagWaveSwayDegrees * 1.7
    }

    private var flapDegrees: Double {
        guard isActive else { return 0 }
        return (Double(phase) - 0.5) * 2 * AchievementMedalIdle.flagWaveFlapDegrees
    }

    private var foldScale: CGFloat {
        guard isActive else { return 1 }
        return 1 - AchievementMedalIdle.flagWaveFold + phase * AchievementMedalIdle.flagWaveFold
    }

    private func start() {
        guard isActive, idleTime == nil else {
            waving = false
            return
        }
        waving = false
        withAnimation(
            .easeInOut(duration: AchievementMedalIdle.flagWaveDuration)
            .repeatForever(autoreverses: true)
        ) {
            waving = true
        }
    }
}

/// Unique idle per family. No shared pulse. SwiftUI `withAnimation` unless a parent publishes idle time.
struct AchievementFamilyIdleEffect: ViewModifier {
    var family: AchievementFamily
    var isActive: Bool
    var size: CGFloat
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var ping = false
    @State private var spin: CGFloat = 0

    func body(content: Content) -> some View {
        idleContent(content)
            .achievementIdleClockPose(drivenByClock: idleTime != nil)
            .onAppear(perform: start)
            .onChange(of: isActive) { _, _ in start() }
            .onChange(of: idleTime != nil) { _, _ in start() }
    }

    @ViewBuilder
    private func idleContent(_ content: Content) -> some View {
        let p = pingPhase
        let loop = loopPhase
        switch family {
        case .firstTrip:
            content.modifier(AchievementFlagWaveEffect(isActive: isActive))
        case .distance:
            content
        case .night:
            content.offset(y: isActive ? (p - 0.5) * 2 * AchievementMedalIdle.nightBobAmplitude(for: size) : 0)
        case .business:
            content.offset(y: isActive ? (1 - p) * 3 : 0)
        case .streak:
            content
                .scaleEffect(isActive ? 1 + 0.10 * p : 1)
                .rotationEffect(.degrees(isActive ? (p - 0.5) * 16 : 0))
        case .cities:
            content.offset(y: isActive ? -7 * p : 0)
        case .routes:
            content
        case .trips:
            content.rotationEffect(.degrees(isActive ? AchievementMedalIdle.steeringSway(phase: p) : 0))
        case .hours:
            content.rotation3DEffect(
                .degrees(isActive ? AchievementMedalIdle.hourglassFlipDegrees(phase: p) : 0),
                axis: (x: 1, y: 0.08, z: 0),
                perspective: 0.55
            )
        case .longhaul:
            content
                .offset(
                    x: isActive ? AchievementMedalIdle.longhaulCruiseX(phase: p, size: size) : 0,
                    y: isActive ? AchievementMedalIdle.longhaulHillY(phase: p, size: size) : 0
                )
                .rotationEffect(.degrees(isActive ? AchievementMedalIdle.longhaulNosePitch(phase: p) : 0))
        case .dawn:
            content
                .offset(y: isActive ? (1 - p) * size * 0.18 : 0)
                .opacity(isActive ? 0.55 + 0.45 * Double(p) : 1)
        case .weekend:
            content.rotation3DEffect(
                .degrees(isActive ? (p - 0.5) * 40 : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.4
            )
        case .fleet:
            content.offset(x: isActive ? (p - 0.5) * size * 0.14 : 0)
        case .countries:
            content.rotation3DEffect(
                .degrees(isActive ? Double(loop) * 360 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
        }
    }

    private var pingPhase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.period(for: family))
        }
        return ping ? 1 : 0
    }

    private var loopPhase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.loop(at: idleTime, duration: AchievementMedalIdle.period(for: family))
        }
        return spin
    }

    private func start() {
        guard isActive, idleTime == nil else {
            ping = false
            spin = 0
            return
        }
        ping = false
        spin = 0
        let duration = AchievementMedalIdle.period(for: family)
        switch family {
        case .countries:
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                spin = 1
            }
        default:
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                ping = true
            }
        }
    }
}

/// Two nodes on the distance S. Each km metal uses a different choreography so
/// the ladder reads as rank, not four copies of the same ping-pong.
enum AchievementDistancePathMotion: Equatable, Sendable {
    /// Full-path pair, 100 km silver.
    case convoy
    /// Opposite ends meet at mid, 1,000 km gold.
    case rendezvous
    /// Each node patrols one half, 10,000 km platinum.
    case patrol
    /// Bloom from mid to the ends, 100,000 km diamond.
    case bloom

    static func `for`(_ material: AchievementMedalMaterial) -> Self {
        switch material {
        case .silver: .convoy
        case .gold: .rendezvous
        case .platinum: .patrol
        case .diamond: .bloom
        }
    }

    var duration: TimeInterval {
        switch self {
        case .convoy: 1.45
        case .rendezvous: 1.65
        case .patrol: 1.90
        case .bloom: 2.20
        }
    }

    /// Phase 0...1 (eased ping-pong). Index 0 and 1 are the two path nodes.
    func nodeProgress(phase: CGFloat, index: Int) -> CGFloat {
        let p = min(1, max(0, phase))
        let lead = index == 0
        switch self {
        case .convoy:
            return lead ? p : 0.14 + p * 0.72
        case .rendezvous:
            return lead ? p : 1 - p
        case .patrol:
            return lead ? p * 0.45 : 0.55 + (1 - p) * 0.45
        case .bloom:
            return lead ? 0.5 * (1 - p) : 0.5 + 0.5 * p
        }
    }
}

/// S-curve matching `point.bottomleft.forward.to.point.topright.scurvepath`.
enum AchievementDistancePath {
    static func curve(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: point(at: 0, in: size))
        path.addCurve(to: point(at: 1, in: size), control1: control1(in: size), control2: control2(in: size))
        return path
    }

    static func point(at t: CGFloat, in size: CGSize) -> CGPoint {
        let t = min(1, max(0, t))
        let p0 = start(in: size)
        let p1 = end(in: size)
        let c1 = control1(in: size)
        let c2 = control2(in: size)
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        return CGPoint(
            x: uu * u * p0.x + 3 * uu * t * c1.x + 3 * u * tt * c2.x + tt * t * p1.x,
            y: uu * u * p0.y + 3 * uu * t * c1.y + 3 * u * tt * c2.y + tt * t * p1.y
        )
    }

    static func start(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.minX, y: box.minY + box.height * 0.78)
    }

    static func end(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.maxX, y: box.minY + box.height * 0.22)
    }

    static func control1(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.maxX, y: box.minY + box.height * 0.82)
    }

    static func control2(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.minX, y: box.minY + box.height * 0.18)
    }

    private static func insetBox(in size: CGSize) -> CGRect {
        let inset = min(size.width, size.height) * 0.22
        return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
    }

    /// Logical `side` only — never live `Canvas` size. A List insert that grows
    /// the bitmap would otherwise vibrate the two nodes.
    static func draw(
        in context: GraphicsContext,
        side: CGFloat,
        progress: CGFloat,
        ink: Color,
        motion: AchievementDistancePathMotion
    ) {
        let canvasSize = CGSize(width: side, height: side)
        let line = max(1.5, side * 0.08)
        context.stroke(
            curve(in: canvasSize),
            with: .color(ink),
            style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        )
        let phase = min(1, max(0, progress))
        let radius = max(2.1, side * 0.09)
        let ringWidth = max(1.2, line * 0.85)
        for index in 0..<2 {
            let point = point(
                at: motion.nodeProgress(phase: phase, index: index),
                in: canvasSize
            )
            var ring = Path()
            ring.addEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: ringWidth))
        }
    }
}

/// Start and end nodes travel the S. Clock-driven poses snap (List insert must
/// not interpolate 0 → wall-clock phase — that vibrates 100 / 1,000 km).
/// Unlock overlay waits a beat for a parent clock, then uses `Animatable`.
struct AchievementDistancePathGlyph: View {
    var size: CGFloat
    var isActive: Bool
    var ink: Color = .white
    var motion: AchievementDistancePathMotion = .rendezvous
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var progress: CGFloat = 0
    @State private var allowFallbackAnimation = false

    var body: some View {
        Group {
            if usesClock || !allowFallbackAnimation {
                AchievementDistancePathCanvas(
                    side: size,
                    progress: displayedProgress,
                    ink: ink,
                    motion: motion
                )
            } else {
                Color.clear
                    .modifier(
                        AchievementDistancePathAnimatedDraw(
                            progress: progress,
                            side: size,
                            ink: ink,
                            motion: motion
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .achievementIdleClockPose(drivenByClock: usesClock)
        .task(id: fallbackTaskID) {
            allowFallbackAnimation = false
            progress = 0
            guard isActive, idleTime == nil else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, isActive, idleTime == nil else { return }
            allowFallbackAnimation = true
            withAnimation(
                .easeInOut(duration: motion.duration)
                .repeatForever(autoreverses: true)
            ) {
                progress = 1
            }
        }
    }

    private var usesClock: Bool { idleTime != nil }

    private var fallbackTaskID: String {
        "\(isActive)-\(usesClock)-\(motion.duration)"
    }

    private var displayedProgress: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: motion.duration)
        }
        return progress
    }
}

private struct AchievementDistancePathCanvas: View {
    var side: CGFloat
    var progress: CGFloat
    var ink: Color
    var motion: AchievementDistancePathMotion

    var body: some View {
        Canvas { context, canvasSize in
            guard canvasSize.width > 1, canvasSize.height > 1, side > 1 else { return }
            let scale = min(canvasSize.width, canvasSize.height) / side
            context.scaleBy(x: scale, y: scale)
            AchievementDistancePath.draw(
                in: context,
                side: side,
                progress: progress,
                ink: ink,
                motion: motion
            )
        }
    }
}

private struct AchievementDistancePathAnimatedDraw: ViewModifier, Animatable {
    var progress: CGFloat
    var side: CGFloat
    var ink: Color
    var motion: AchievementDistancePathMotion

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        AchievementDistancePathCanvas(
            side: side,
            progress: progress,
            ink: ink,
            motion: motion
        )
    }
}

/// Crescent and stars drift together; stars sparkle. Disc stays put.
struct AchievementNightSkyGlyph: View {
    var size: CGFloat
    var isActive: Bool
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var bobbing = false
    @State private var sparkle = false

    var body: some View {
        let moonFont: Font = size < 50 ? .body.weight(.semibold) : .title3.weight(.semibold)
        let starFont: Font = size < 50 ? .caption2.weight(.bold) : .caption.weight(.bold)
        ZStack {
            Image(systemName: "moon.fill")
                .font(moonFont)
                .foregroundStyle(.white)
                .offset(x: -size * 0.10)
            star(leading: true, font: starFont)
                .offset(x: size * 0.16, y: -size * 0.20)
            star(leading: false, font: starFont)
                .scaleEffect(0.72)
                .offset(x: size * 0.26, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .offset(y: bobOffset)
        .achievementIdleClockPose(drivenByClock: idleTime != nil)
        .onAppear(perform: start)
        .onChange(of: isActive) { _, _ in
            start()
        }
        .onChange(of: idleTime != nil) { _, _ in
            start()
        }
    }

    private var bobPhase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.nightBobDuration)
        }
        return bobbing ? 1 : 0
    }

    private var bobOffset: CGFloat {
        guard isActive else { return 0 }
        let amplitude = AchievementMedalIdle.nightBobAmplitude(for: size)
        return (bobPhase - 0.5) * 2 * amplitude
    }

    private var sparklePhase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.nightSparkleDuration)
        }
        return sparkle ? 1 : 0
    }

    private func star(leading: Bool, font: Font) -> some View {
        let lit = leading ? sparklePhase : 1 - sparklePhase
        return Image(systemName: "sparkle")
            .font(font)
            .foregroundStyle(.white)
            .scaleEffect(0.78 + 0.44 * lit)
            .opacity(0.42 + 0.58 * lit)
    }

    private func start() {
        guard isActive, idleTime == nil else {
            bobbing = false
            sparkle = false
            return
        }
        bobbing = false
        sparkle = false
        withAnimation(
            .easeInOut(duration: AchievementMedalIdle.nightBobDuration)
            .repeatForever(autoreverses: true)
        ) {
            bobbing = true
        }
        withAnimation(
            .easeInOut(duration: AchievementMedalIdle.nightSparkleDuration)
            .repeatForever(autoreverses: true)
        ) {
            sparkle = true
        }
    }
}

/// Dims the disc under the family glyph. Do not paint this over the icon — the glyph stays opaque.
struct AchievementMedalLockScrim: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.black.opacity(AchievementTheme.lockScrimOpacity))
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Opaque lock badge on the disc rim. Not a translucent film over the family icon.
struct AchievementMedalLockOverlay: View {
    var size: CGFloat

    var body: some View {
        let badge = Self.lockBadgeSize(for: size)
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.88))
            Image(systemName: "lock.fill")
                .font(.system(size: Self.lockGlyphSize(for: size), weight: .bold))
                .foregroundStyle(Color.white)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: badge, height: badge)
        .offset(y: size * 0.30)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func lockBadgeSize(for medalSize: CGFloat) -> CGFloat {
        max(14, medalSize * 0.28)
    }

    static func lockGlyphSize(for medalSize: CGFloat) -> CGFloat {
        max(8, medalSize * 0.16)
    }
}
