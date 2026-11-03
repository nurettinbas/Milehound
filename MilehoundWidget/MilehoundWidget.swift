import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private enum WidgetL10n {
    private static func text(_ key: String) -> String {
        SharedL10n.text(key)
    }

    static var pause: String { text("action.pause") }
    static var resume: String { text("action.resume") }
    static var stop: String { text("action.stop") }
    static var start: String { text("action.start") }
    static var paused: String { text("live_activity.paused") }
    static var recording: String { text("live_activity.recording") }
    static var tripActive: String { text("live_activity.trip_active") }
    static var tripPaused: String { text("live_activity.trip_paused") }
    static var distance: String { text("label.distance") }
    static var duration: String { text("label.duration") }
    static var speed: String { text("live_activity.speed") }
    static var noRecording: String { text("widget.no_recording") }
    static var thisWeek: String { text("section.this_week") }
    static var displayName: String { text("widget.display_name") }
    static var description: String { text("widget.description") }
}

private enum WidgetPalette {
    static let brandTop = MilehoundBrandColors.brandTop
    static let brandBottom = MilehoundBrandColors.brandBottom
    static let recording = MilehoundBrandColors.recording
    static let paused = MilehoundBrandColors.paused
    static let resume = MilehoundBrandColors.resume
    /// Opaque system red — never Appearance / glass tint.
    static let stop = Color(red: 1.0, green: 0.231, blue: 0.188)

    static func tint(for scheme: ColorScheme) -> Color {
        ShellPalette.stored().tintColor(for: scheme)
    }
}

struct WidgetAdaptiveBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if renderingMode == .fullColor {
            let atmosphere = ShellPalette.stored().atmosphere(for: colorScheme)
            LinearGradient(
                colors: [
                    atmosphere.top.color.opacity(0.55),
                    atmosphere.mid.color.opacity(0.40),
                    atmosphere.bottom.color.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct WidgetIntentButton<Intent: AppIntent>: View {
    enum Size {
        case regular
        case small
    }

    let title: String
    let systemImage: String
    let tint: Color
    let size: Size
    let iconOnly: Bool
    let intent: Intent

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var usesLiquidGlassLayout: Bool {
        renderingMode != .fullColor
    }

    init(
        title: String,
        systemImage: String,
        tint: Color,
        size: Size,
        iconOnly: Bool = false,
        intent: Intent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
        self.iconOnly = iconOnly
        self.intent = intent
    }

    var body: some View {
        Group {
            if usesLiquidGlassLayout {
                if iconOnly {
                    Button(intent: intent) {
                        label
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                } else {
                    Button(intent: intent) {
                        label
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
            } else {
                Button(intent: intent) {
                    label
                        .frame(maxWidth: iconOnly ? nil : .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .controlSize(size == .small ? .small : .regular)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var label: some View {
        if iconOnly {
            Image(systemName: systemImage)
                .font(iconOnlyFont.weight(.bold))
                .frame(width: iconOnlyDimension, height: iconOnlyDimension)
        } else {
            Label(title, systemImage: systemImage)
                .font(labelFont)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var labelFont: Font {
        switch size {
        case .regular: .caption.weight(.semibold)
        case .small: .caption2.weight(.semibold)
        }
    }

    private var iconOnlyFont: Font {
        switch size {
        case .regular: .body
        case .small: .caption
        }
    }

    private var iconOnlyDimension: CGFloat {
        switch size {
        case .regular: 28
        case .small: 24
        }
    }
}

/// Opens the main app via deep link so bootstrap + `processPendingRecordingRequests` run in-app.
/// Widget `AppIntent` alone runs in the extension process and cannot start recording reliably.
private struct WidgetStartLink: View {
    enum Size {
        case regular
        case small
    }

    let title: String
    let systemImage: String
    let tint: Color
    let size: Size

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var usesLiquidGlassLayout: Bool {
        renderingMode != .fullColor
    }

    var body: some View {
        Group {
            if usesLiquidGlassLayout {
                Link(destination: MilehoundDeepLink.startRecording) {
                    label
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(tint)
            } else {
                Link(destination: MilehoundDeepLink.startRecording) {
                    label
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .controlSize(size == .small ? .small : .regular)
        .accessibilityLabel(title)
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(size == .regular ? .caption.weight(.semibold) : .caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct MilehoundWidgetEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
    let isPaused: Bool
    let elapsed: TimeInterval
    let distanceMeters: Double
    let weekDistanceMeters: Double
    let monthDistanceMeters: Double
    let recordingStartedAt: Date?

    static func preview(
        isRecording: Bool = true,
        isPaused: Bool = false,
        elapsed: TimeInterval = 3_723,
        distanceMeters: Double = 12_400,
        weekDistanceMeters: Double = 45_200,
        monthDistanceMeters: Double = 182_000,
        recordingStartedAt: Date? = nil
    ) -> MilehoundWidgetEntry {
        MilehoundWidgetEntry(
            date: .now,
            isRecording: isRecording,
            isPaused: isPaused,
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            weekDistanceMeters: weekDistanceMeters,
            monthDistanceMeters: monthDistanceMeters,
            recordingStartedAt: recordingStartedAt ?? (isRecording && !isPaused ? Date().addingTimeInterval(-elapsed) : nil)
        )
    }

    static func from(snapshot: RecordingControlBridge.RecordingWidgetSnapshot, at date: Date = Date()) -> MilehoundWidgetEntry {
        MilehoundWidgetEntry(
            date: date,
            isRecording: snapshot.isRecording,
            isPaused: snapshot.isPaused,
            elapsed: snapshot.elapsed(at: date),
            distanceMeters: snapshot.distanceMeters,
            weekDistanceMeters: snapshot.weekDistanceMeters,
            monthDistanceMeters: snapshot.monthDistanceMeters,
            recordingStartedAt: snapshot.recordingStartedAt
        )
    }
}

struct MilehoundWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MilehoundWidgetEntry {
        .preview(isRecording: true, isPaused: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MilehoundWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.preview(isRecording: true, isPaused: false))
        } else {
            completion(loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MilehoundWidgetEntry>) -> Void) {
        let snapshot = RecordingControlBridge.recordingWidgetSnapshot()
        let now = Date()

        // Match Live Activity / Dynamic Island cadence (3s) so both surfaces tick together.
        if snapshot.isRecording, !snapshot.isPaused, let startedAt = snapshot.recordingStartedAt {
            let tick: TimeInterval = 3
            let horizon = 20
            var entries: [MilehoundWidgetEntry] = []
            entries.reserveCapacity(horizon)
            for step in 0..<horizon {
                let date = now.addingTimeInterval(TimeInterval(step) * tick)
                entries.append(
                    MilehoundWidgetEntry(
                        date: date,
                        isRecording: true,
                        isPaused: false,
                        elapsed: max(0, date.timeIntervalSince(startedAt)),
                        distanceMeters: snapshot.distanceMeters,
                        weekDistanceMeters: snapshot.weekDistanceMeters,
                        monthDistanceMeters: snapshot.monthDistanceMeters,
                        recordingStartedAt: startedAt
                    )
                )
            }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }

        let entry = MilehoundWidgetEntry.from(snapshot: snapshot, at: now)
        let refreshInterval: TimeInterval = snapshot.isRecording ? 15 : 30
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshInterval))))
    }

    private func loadEntry() -> MilehoundWidgetEntry {
        let snapshot = RecordingControlBridge.recordingWidgetSnapshot()
        return MilehoundWidgetEntry.from(snapshot: snapshot)
    }
}

struct MilehoundWidgetView: View {
    let entry: MilehoundWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var usesLiquidGlassLayout: Bool {
        renderingMode != .fullColor
    }

    private var widgetPrimary: Color {
        usesLiquidGlassLayout ? Color.primary : Color.white
    }

    private var widgetSecondary: Color {
        usesLiquidGlassLayout ? Color.secondary : Color.white.opacity(0.88)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            widgetHeader(compact: true)

            if entry.isRecording || entry.isPaused {
                Text(entry.isPaused ? WidgetL10n.paused : WidgetL10n.recording)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        usesLiquidGlassLayout
                            ? .primary
                            : (entry.isPaused ? WidgetPalette.paused : WidgetPalette.recording)
                    )
                    .lineLimit(1)
                Text(DateFormatters.formatDuration(entry.elapsed))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(DateFormatters.formatDistance(entry.distanceMeters))
                    .font(.caption2)
                    .foregroundStyle(widgetSecondary)
                Spacer(minLength: 0)
                recordingControlsSmall
            } else {
                Text(WidgetL10n.thisWeek)
                    .font(.caption2)
                    .foregroundStyle(widgetSecondary)
                Text(DateFormatters.formatDistance(entry.weekDistanceMeters))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WidgetStartLink(
                    title: WidgetL10n.start,
                    systemImage: "play.fill",
                    tint: WidgetPalette.tint(for: colorScheme),
                    size: .small
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(compact: false)

            if entry.isRecording || entry.isPaused {
                statusBadge
                Text("\(DateFormatters.formatDuration(entry.elapsed)) · \(DateFormatters.formatDistance(entry.distanceMeters))")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text(WidgetL10n.thisWeek)
                    .font(.caption)
                    .foregroundStyle(widgetSecondary)
                Text(DateFormatters.formatDistance(entry.weekDistanceMeters))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
            recordingControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            widgetHeader(compact: false)

            if entry.isRecording || entry.isPaused {
                statusBadge
                Text(DateFormatters.formatDuration(entry.elapsed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(DateFormatters.formatDistance(entry.distanceMeters))
                    .font(.title3)
                    .foregroundStyle(widgetSecondary)
            } else {
                Text(WidgetL10n.thisWeek)
                    .font(.caption)
                    .foregroundStyle(widgetSecondary)
                Text(DateFormatters.formatDistance(entry.weekDistanceMeters))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(WidgetL10n.noRecording)
                    .font(.subheadline)
                    .foregroundStyle(widgetSecondary)
            }

            Spacer(minLength: 0)
            recordingControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func widgetHeader(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .font(compact ? .subheadline : .headline)
                .foregroundStyle(WidgetPalette.tint(for: colorScheme))
            Text("Milehound")
                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.bold))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let title = entry.isPaused ? WidgetL10n.paused : WidgetL10n.recording
        if usesLiquidGlassLayout {
            Text(title)
                .font(.caption.weight(.semibold))
        } else {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isPaused ? WidgetPalette.paused : WidgetPalette.recording)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (entry.isPaused ? WidgetPalette.paused : WidgetPalette.recording).opacity(0.14),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        if entry.isRecording || entry.isPaused {
            HStack(spacing: 8) {
                if entry.isPaused {
                    WidgetIntentButton(
                        title: WidgetL10n.resume,
                        systemImage: "play.fill",
                        tint: WidgetPalette.resume,
                        size: .regular,
                        intent: HomeWidgetResumeRecordingIntent()
                    )
                } else {
                    WidgetIntentButton(
                        title: WidgetL10n.pause,
                        systemImage: "pause.fill",
                        tint: WidgetPalette.paused,
                        size: .regular,
                        intent: HomeWidgetPauseRecordingIntent()
                    )
                }

                WidgetIntentButton(
                    title: WidgetL10n.stop,
                    systemImage: "stop.fill",
                    tint: WidgetPalette.stop,
                    size: .regular,
                    intent: HomeWidgetStopRecordingIntent()
                )
            }
        } else {
            WidgetStartLink(
                title: WidgetL10n.start,
                systemImage: "play.fill",
                tint: WidgetPalette.tint(for: colorScheme),
                size: .regular
            )
        }
    }

    @ViewBuilder
    private var recordingControlsSmall: some View {
        HStack(spacing: 6) {
            if entry.isPaused {
                WidgetIntentButton(
                    title: WidgetL10n.resume,
                    systemImage: "play.fill",
                    tint: WidgetPalette.resume,
                    size: .small,
                    intent: HomeWidgetResumeRecordingIntent()
                )
            } else {
                WidgetIntentButton(
                    title: WidgetL10n.pause,
                    systemImage: "pause.fill",
                    tint: WidgetPalette.paused,
                    size: .small,
                    intent: HomeWidgetPauseRecordingIntent()
                )
            }

            WidgetIntentButton(
                title: WidgetL10n.stop,
                systemImage: "stop.fill",
                tint: WidgetPalette.stop,
                size: .small,
                intent: HomeWidgetStopRecordingIntent()
            )
        }
    }
}

struct MilehoundWidget: Widget {
    let kind = "MilehoundWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MilehoundWidgetProvider()) { entry in
            MilehoundWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetAdaptiveBackground()
                }
        }
        .configurationDisplayName(WidgetL10n.displayName)
        .description(WidgetL10n.description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct LiveActivityCarIcon: View {
    var side: CGFloat = 22
    var photoRevision: String? = nil
    /// Island chrome is black — white symbols read cleaner than brand blue.
    var symbolTint: Color = .white

    var body: some View {
        markContent
            .frame(width: side, height: side)
    }

    @ViewBuilder
    private var markContent: some View {
        // Photo wins when App Group carries a usable thumb for this revision; otherwise fixed
        // right-facing `car.side.fill`.
        if let image = LiveActivityVehicleMarkStore.image(revision: photoRevision) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "car.side.fill")
                .font(.system(size: side * 0.58, weight: .semibold))
                .foregroundStyle(symbolTint)
                .scaleEffect(x: -1, y: 1)
        }
    }
}

/// Compact circular control — tinted disc only; no outer plate / glass box.
///
/// Uses `.borderedProminent` rather than a hand-drawn `Circle()` behind `.plain`: WidgetKit only
/// draws its built-in press highlight for system button styles, and without that highlight the
/// round trip through the intent reads as lag even when it is fast.
private struct LiveActivityIslandButton<Intent: AppIntent>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let intent: Intent
    var size: CGFloat = 36

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .tint(tint)
        .frame(width: size, height: size)
        .accessibilityLabel(title)
    }
}

/// Stable pause/play slot — CSS-style bounce-in / bounce-out glyph swap on tap.
///
/// Live Activity state arrives late from ActivityKit; `@State displayPaused` flips on tap so the
/// bounce runs immediately instead of waiting for the next ContentState push.
private struct LiveActivityPlaybackControl: View {
    let isPaused: Bool
    var size: CGFloat = 38

    @State private var displayPaused: Bool

    init(isPaused: Bool, size: CGFloat = 38) {
        self.isPaused = isPaused
        self.size = size
        _displayPaused = State(initialValue: isPaused)
    }

    var body: some View {
        Button(intent: WidgetTogglePauseResumeIntent(wasPaused: displayPaused)) {
            ZStack {
                LiveActivityBounceGlyph(
                    systemName: "pause.fill",
                    isActive: !displayPaused,
                    size: size
                )
                LiveActivityBounceGlyph(
                    systemName: "play.fill",
                    isActive: displayPaused,
                    size: size,
                    offsetX: 0.8
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .tint(displayPaused ? WidgetPalette.resume : WidgetPalette.paused)
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: displayPaused) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(0.82, duration: 0.0004)
            CubicKeyframe(1.10, duration: 0.0006)
            CubicKeyframe(1.0, duration: 0.0005)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                displayPaused.toggle()
            }
        )
        .onChange(of: isPaused) { _, newValue in
            displayPaused = newValue
        }
        .accessibilityLabel(displayPaused ? WidgetL10n.resume : WidgetL10n.pause)
    }
}

private struct LiveActivityBounceGlyph: View {
    let systemName: String
    let isActive: Bool
    let size: CGFloat
    var offsetX: CGFloat = 0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: offsetX)
            .keyframeAnimator(
                initialValue: isActive ? 1.0 : 0.2,
                trigger: isActive
            ) { view, scale in
                view
                    .scaleEffect(scale)
                    .opacity(scale > 0.18 ? 1 : 0)
            } keyframes: { _ in
                if isActive {
                    LinearKeyframe(0.2, duration: 0)
                    CubicKeyframe(1.22, duration: 0.0008)
                    CubicKeyframe(0.94, duration: 0.0005)
                    CubicKeyframe(1.0, duration: 0.0004)
                } else {
                    LinearKeyframe(1.0, duration: 0)
                    CubicKeyframe(1.08, duration: 0.0003)
                    CubicKeyframe(0.2, duration: 0.0009)
                }
            }
    }
}

/// One value font for Duration / Distance / Speed so all three stay the same size.
/// Longest string wins; every column uses that size (no per-column scaling).
private enum LiveActivityMetricTypeScale {
    static let labelSize: CGFloat = 9

    static func valueSize(for values: [String], compact: Bool) -> CGFloat {
        let longest = values.map(\.count).max() ?? 0
        switch longest {
        case ...6: return compact ? 14 : 15
        case ...8: return compact ? 12 : 13
        default: return compact ? 11 : 12
        }
    }
}

private func liveActivityMetricValues(
    _ state: TripRecordingAttributes.ContentState
) -> (duration: String, distance: String, speed: String) {
    let duration = DateFormatters.formatDuration(TimeInterval(state.elapsedSeconds))
    let distance = DateFormatters.formatDistance(state.distanceMeters)
    let speed = state.isPaused ? "—" : "\(state.currentSpeedKmh) km/s"
    return (duration, distance, speed)
}

/// Equal-width Island column: small label on top, value below (same size across columns).
private struct LiveActivityIslandMetricColumn: View {
    let label: String
    let value: String
    var valueFontSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.system(size: LiveActivityMetricTypeScale.labelSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(value)
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Expanded Island row: car + three metrics sharing one value font size.
private struct LiveActivityIslandExpandedMetrics: View {
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        let metrics = liveActivityMetricValues(state)
        let valueFontSize = LiveActivityMetricTypeScale.valueSize(
            for: [metrics.duration, metrics.distance, metrics.speed],
            compact: false
        )
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 2) {
                // Match metric label height so the car lines up with values.
                Text(" ")
                    .font(.system(size: LiveActivityMetricTypeScale.labelSize, weight: .medium))
                    .opacity(0)
                LiveActivityCarIcon(
                    side: 36,
                    photoRevision: state.vehiclePhotoRevision,
                    symbolTint: .white
                )
            }
            .frame(maxWidth: .infinity)

            LiveActivityIslandMetricColumn(
                label: WidgetL10n.duration,
                value: metrics.duration,
                valueFontSize: valueFontSize
            )

            LiveActivityIslandMetricColumn(
                label: WidgetL10n.distance,
                value: metrics.distance,
                valueFontSize: valueFontSize
            )

            LiveActivityIslandMetricColumn(
                label: WidgetL10n.speed,
                value: metrics.speed,
                valueFontSize: valueFontSize
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// Lock Screen / StandBy banner — pause/stop controls stay interactive here.
private struct LiveActivityLockScreenBanner: View {
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiveActivityCarIcon(
                side: 54,
                photoRevision: state.vehiclePhotoRevision,
                symbolTint: WidgetPalette.tint(for: .light)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatters.formatDuration(TimeInterval(state.elapsedSeconds)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isPaused ? WidgetPalette.paused : WidgetPalette.recording)
                        .frame(width: 6, height: 6)
                    Text(state.isPaused ? WidgetL10n.paused : WidgetL10n.recording)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.isPaused ? WidgetPalette.paused : .secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Text(liveActivityBannerMeta(state))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                LiveActivityPlaybackControl(isPaused: state.isPaused, size: 40)
                LiveActivityIslandButton(
                    title: WidgetL10n.stop,
                    systemImage: "stop.fill",
                    tint: WidgetPalette.stop,
                    intent: WidgetStopRecordingIntent(),
                    size: 40
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func liveActivityBannerMeta(_ state: TripRecordingAttributes.ContentState) -> String {
        let distance = DateFormatters.formatDistance(state.distanceMeters)
        if state.isPaused {
            return distance
        }
        return "\(distance) · \(state.currentSpeedKmh) km/s"
    }
}

/// CarPlay Dashboard + watchOS Smart Stack — glanceable, non-interactive (CarPlay strips buttons).
///
/// If the system tags a wide Lock Screen / notification banner as `.small`, show the
/// original lock layout instead of stretching the compact CarPlay tile.
private struct LiveActivitySmallFamilyBanner: View {
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if size.width >= 300 {
                    LiveActivityLockScreenBanner(state: state)
                } else if size.width >= 8, size.height >= 8 {
                    LiveActivityCarPlayDashboardTile(state: state, tileSize: size)
                } else {
                    Color.clear
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .transaction { $0.animation = nil }
    }
}

/// Opt out of WidgetKit’s default Live Activity material. `nil` tint is the
/// extra frost plate; `.clear` leaves only CarPlay’s native glass (Maps / Now Playing).
private struct CarPlayNativeGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .containerBackground(.clear, for: .widget)
            .activityBackgroundTint(.clear)
    }
}

private extension View {
    func carPlayNativeGlassBackground() -> some View {
        modifier(CarPlayNativeGlassBackground())
    }
}

/// CarPlay Dashboard tile. Snapshot is content-only: CarPlay wraps it in the
/// same native Liquid Glass as Now Playing / Maps. Phone-call ghosting is
/// handled by `LiveActivityDashboardOcclusionMonitor`, not an opaque plate.
private struct LiveActivityCarPlayDashboardTile: View {
    let state: TripRecordingAttributes.ContentState
    let tileSize: CGSize

    var body: some View {
        let metrics = liveActivityMetricValues(state)
        let valueFontSize = LiveActivityMetricTypeScale.valueSize(
            for: [metrics.duration, metrics.distance, metrics.speed],
            compact: true
        )
        // Height-only icon so column widths stay stable if CarPlay reports a slightly
        // different width after Phone UI restores the dashboard.
        let iconSide = min(40, max(28, tileSize.height - 12))

        HStack(alignment: .center, spacing: 4) {
            LiveActivityCarIcon(
                side: iconSide,
                photoRevision: state.vehiclePhotoRevision,
                symbolTint: WidgetPalette.tint(for: .light)
            )
            .frame(width: iconSide, height: iconSide)
            .accessibilityHidden(true)

            metricColumn(value: metrics.duration, label: WidgetL10n.duration, valueFontSize: valueFontSize)
            metricColumn(value: metrics.distance, label: WidgetL10n.distance, valueFontSize: valueFontSize)
            metricColumn(value: metrics.speed, label: WidgetL10n.speed, valueFontSize: valueFontSize)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .environment(\.colorScheme, .dark)
        .frame(width: tileSize.width, height: tileSize.height)
        .clipped()
        .background(.clear)
    }

    private func metricColumn(value: String, label: String, valueFontSize: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.system(size: LiveActivityMetricTypeScale.labelSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .contentTransition(.identity)
                .frame(maxWidth: .infinity)
            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .contentTransition(.identity)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Picks Lock Screen (medium) vs CarPlay / Smart Stack (small) layouts.
@available(iOS 18.0, *)
private struct LiveActivityBannerRoot: View {
    @Environment(\.activityFamily) private var activityFamily
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        Group {
            switch activityFamily {
            case .small:
                LiveActivitySmallFamilyBanner(state: state)
                    .carPlayNativeGlassBackground()
            case .medium:
                LiveActivityLockScreenBanner(state: state)
                    .activityBackgroundTint(lockScreenActivityTint)
            @unknown default:
                LiveActivityLockScreenBanner(state: state)
                    .activityBackgroundTint(lockScreenActivityTint)
            }
        }
    }

    private var lockScreenActivityTint: Color {
        (state.isPaused ? WidgetPalette.paused : WidgetPalette.tint(for: .light)).opacity(0.18)
    }
}

/// Live Activity for Lock Screen, Dynamic Island, and CarPlay Dashboard.
///
/// Requires iOS 18 so we can declare `activityFamily.small` (CarPlay dashboard tile).
/// Home Screen / Lock Screen widgets still load on iOS 17 via the other widgets in this bundle.
@available(iOS 18.0, *)
struct MilehoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripRecordingAttributes.self) { context in
            LiveActivityBannerRoot(state: context.state)
        } dynamicIsland: { context in
            liveActivityDynamicIsland(context: context)
        }
        .supplementalActivityFamilies([.small])
    }
}

@MainActor
private func liveActivityDynamicIsland(
    context: ActivityViewContext<TripRecordingAttributes>
) -> DynamicIsland {
    DynamicIsland {
        // One full-width row — avoid `.leading`/`.trailing` (they pin content to edges
        // and leave a dead gap in the middle). Icon + three equal metric columns, centered.
        DynamicIslandExpandedRegion(.center) {
            LiveActivityIslandExpandedMetrics(state: context.state)
        }

        DynamicIslandExpandedRegion(.bottom) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 0.5)
                    .padding(.bottom, 8)

                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                        Circle()
                            .fill(context.state.isPaused ? WidgetPalette.paused : Color.green)
                            .frame(width: 7, height: 7)
                        Text(context.state.isPaused ? WidgetL10n.tripPaused : WidgetL10n.tripActive)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    LiveActivityPlaybackControl(isPaused: context.state.isPaused, size: 36)
                    LiveActivityIslandButton(
                        title: WidgetL10n.stop,
                        systemImage: "stop.fill",
                        tint: WidgetPalette.stop,
                        intent: WidgetStopRecordingIntent(),
                        size: 36
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    } compactLeading: {
        LiveActivityCarIcon(
            side: 18,
            photoRevision: context.state.vehiclePhotoRevision,
            symbolTint: .white
        )
    } compactTrailing: {
        Text(DateFormatters.formatDuration(TimeInterval(context.state.elapsedSeconds)))
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
    } minimal: {
        LiveActivityCarIcon(
            side: 15,
            photoRevision: context.state.vehiclePhotoRevision,
            symbolTint: .white
        )
    }
    .keylineTint(context.state.isPaused ? WidgetPalette.paused : WidgetPalette.tint(for: .light))
}

@main
struct MilehoundWidgetBundle: WidgetBundle {
    var body: some Widget {
        MilehoundWidget()
        MilehoundLockScreenWidget()
        GoalRingWidget()
        LastTripWidget()
        CostSummaryWidget()
        if #available(iOS 18.0, *) {
            MilehoundLiveActivity()
        }
    }
}

#Preview(as: .systemSmall) {
    MilehoundWidget()
} timeline: {
    MilehoundWidgetEntry.preview(isRecording: true, isPaused: false)
    MilehoundWidgetEntry.preview(isRecording: true, isPaused: true)
    MilehoundWidgetEntry.preview(isRecording: false, isPaused: false)
}

#Preview(as: .systemMedium) {
    MilehoundWidget()
} timeline: {
    MilehoundWidgetEntry.preview(isRecording: true, isPaused: false)
    MilehoundWidgetEntry.preview(isRecording: false, isPaused: false)
}

#Preview(as: .systemLarge) {
    MilehoundWidget()
} timeline: {
    MilehoundWidgetEntry.preview(isRecording: true, isPaused: false)
    MilehoundWidgetEntry.preview(isRecording: false, isPaused: false)
}

@available(iOS 18.0, *)
#Preview("Live Activity metrics", as: .content, using: TripRecordingAttributes(startedAt: .now)) {
    MilehoundLiveActivity()
} contentStates: {
    TripRecordingAttributes.ContentState.previewShort
    TripRecordingAttributes.ContentState.previewLong
}

private extension TripRecordingAttributes.ContentState {
    /// CarPlay-style short values: 3:25 / 0.5 km.
    static var previewShort: Self {
        .init(elapsedSeconds: 205, distanceMeters: 500, currentSpeedKmh: 0, isPaused: false)
    }

    /// Long values that used to overlap: 1:08:24 / 138.9 km / 88 km/s.
    static var previewLong: Self {
        .init(elapsedSeconds: 4104, distanceMeters: 138_900, currentSpeedKmh: 88, isPaused: false)
    }
}
