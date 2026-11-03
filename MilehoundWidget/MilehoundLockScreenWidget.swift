import SwiftUI
import WidgetKit

private enum LockScreenWidgetL10n {
    private static func text(_ key: String) -> String {
        SharedL10n.text(key)
    }

    static var displayName: String { text("widget.lock_screen.display_name") }
    static var description: String { text("widget.lock_screen.description") }

    static func accessibilityIdle(distance: String) -> String {
        String(format: text("widget.lock_screen.accessibility.idle"), distance)
    }
}

private enum LockScreenArcMetrics {
    static let start: CGFloat = 0.14
    static let end: CGFloat = 0.86
    static let rotation: Double = 90
    static let lineWidth: CGFloat = 3.5

    static var span: CGFloat { end - start }

    static func progressEnd(for progress: Double) -> CGFloat {
        start + span * CGFloat(min(1, max(0, progress)))
    }
}

struct MilehoundLockScreenWidgetView: View {
    let entry: MilehoundWidgetEntry

    private var monthlyGoalMeters: Double {
        let goal = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName)?
            .double(forKey: "monthlyDistanceGoalMeters") ?? 0
        return goal > 0 ? goal : 500_000
    }

    var body: some View {
        circularLayout
            .widgetURL((entry.isRecording || entry.isPaused) ? MilehoundDeepLink.startRecording : MilehoundDeepLink.statsGoal)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    private var circularLayout: some View {
        let ringMeters = entry.monthDistanceMeters
        let progress = min(1, max(0, ringMeters / monthlyGoalMeters))

        return ZStack {
            weatherStyleArc(
                from: LockScreenArcMetrics.start,
                to: LockScreenArcMetrics.end,
                color: Color.primary.opacity(0.16),
                lineWidth: LockScreenArcMetrics.lineWidth
            )

            weatherStyleArc(
                from: LockScreenArcMetrics.start,
                to: LockScreenArcMetrics.progressEnd(for: progress),
                color: Color.primary.opacity(0.9),
                lineWidth: LockScreenArcMetrics.lineWidth
            )

            Text(ringDistanceLabel(for: ringMeters))
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .offset(y: 16)

            carCluster
                .offset(y: -5)
        }
    }

    private func weatherStyleArc(
        from: CGFloat,
        to: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(LockScreenArcMetrics.rotation))
    }

    private var carCluster: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 21, weight: .medium))
                .scaleEffect(x: -1, y: 1)
                .foregroundStyle(Color.primary)

            Image(systemName: "play.fill")
                .font(.system(size: 5.5, weight: .black))
                .foregroundStyle(.white)
                .padding(2.5)
                .background(Circle().fill(Color.accentColor))
                .offset(x: 5, y: -3)
                .widgetAccentable()
        }
    }

    private func ringDistanceLabel(for meters: Double) -> String {
        let km = max(0, meters / 1000)
        if km >= 100 {
            return String(format: "%.0fkm", km.rounded())
        }
        return String(format: "%.1fkm", km)
    }

    private var accessibilityLabel: String {
        LockScreenWidgetL10n.accessibilityIdle(
            distance: DateFormatters.formatDistance(entry.monthDistanceMeters)
        )
    }
}

struct MilehoundLockScreenWidget: Widget {
    let kind = "MilehoundLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MilehoundWidgetProvider()) { entry in
            MilehoundLockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    AccessoryWidgetBackground()
                }
        }
        .configurationDisplayName(LockScreenWidgetL10n.displayName)
        .description(LockScreenWidgetL10n.description)
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview(as: .accessoryCircular) {
    MilehoundLockScreenWidget()
} timeline: {
    MilehoundWidgetEntry.preview(monthDistanceMeters: 182_000)
    MilehoundWidgetEntry.preview(monthDistanceMeters: 42_000)
    MilehoundWidgetEntry.preview(monthDistanceMeters: 470_000)
    MilehoundWidgetEntry.preview(monthDistanceMeters: 12_000)
}
