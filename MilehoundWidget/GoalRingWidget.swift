import SwiftUI
import WidgetKit

struct GoalRingWidgetEntry: TimelineEntry {
    let date: Date
    let payload: PremiumWidgetPayload
    let recording: RecordingControlBridge.RecordingWidgetSnapshot

    static func current(at date: Date = Date()) -> GoalRingWidgetEntry {
        GoalRingWidgetEntry(
            date: date,
            payload: .load(),
            recording: RecordingControlBridge.recordingWidgetSnapshot()
        )
    }
}

struct GoalRingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoalRingWidgetEntry {
        .current()
    }

    func getSnapshot(in context: Context, completion: @escaping (GoalRingWidgetEntry) -> Void) {
        completion(.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoalRingWidgetEntry>) -> Void) {
        let entry = GoalRingWidgetEntry.current()
        let next = Calendar.current.date(byAdding: .minute, value: entry.recording.showsRecordingControls ? 1 : 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct GoalRingWidgetView: View {
    let entry: GoalRingWidgetEntry

    var body: some View {
        let progress = entry.payload.goalProgress
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(MilehoundBrandColors.brandBottom.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(MilehoundBrandColors.brandBottom, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                if entry.recording.showsRecordingControls {
                    Circle()
                        .fill(MilehoundBrandColors.recording)
                        .frame(width: 8, height: 8)
                        .offset(x: 28, y: -28)
                }
            }
            .frame(width: 72, height: 72)
            Text(DateFormatters.formatDistance(entry.payload.monthDistanceMeters))
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(SharedL10n.text("premium.widget.goal.caption"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(MilehoundDeepLink.statsGoal)
        .accessibilityLabel(SharedL10n.text("premium.widget.goal.a11y"))
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

struct GoalRingWidget: Widget {
    let kind = "GoalRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoalRingWidgetProvider()) { entry in
            GoalRingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetAdaptiveBackground()
                }
        }
        .configurationDisplayName(SharedL10n.text("premium.widget.goal.name"))
        .description(SharedL10n.text("premium.widget.goal.description"))
        .supportedFamilies([.systemSmall])
    }
}

#Preview("idle", as: .systemSmall) {
    GoalRingWidget()
} timeline: {
    GoalRingWidgetEntry.current()
}
