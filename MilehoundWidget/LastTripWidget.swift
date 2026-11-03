import AppIntents
import SwiftUI
import WidgetKit

struct LastTripWidgetEntry: TimelineEntry {
    let date: Date
    let payload: PremiumWidgetPayload
    let recording: RecordingControlBridge.RecordingWidgetSnapshot

    static func current(at date: Date = Date()) -> LastTripWidgetEntry {
        LastTripWidgetEntry(
            date: date,
            payload: .load(),
            recording: RecordingControlBridge.recordingWidgetSnapshot()
        )
    }
}

struct LastTripWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastTripWidgetEntry { .current() }
    func getSnapshot(in context: Context, completion: @escaping (LastTripWidgetEntry) -> Void) {
        completion(.current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LastTripWidgetEntry>) -> Void) {
        let entry = LastTripWidgetEntry.current()
        let next = Calendar.current.date(byAdding: .minute, value: entry.recording.showsRecordingControls ? 1 : 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct LastTripWidgetView: View {
    let entry: LastTripWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 10) {
            if entry.payload.showRoutePreview, let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: family == .systemMedium ? 92 : 56, height: family == .systemMedium ? 92 : 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MilehoundBrandColors.brandBottom.opacity(0.16))
                    .frame(width: family == .systemMedium ? 92 : 56, height: family == .systemMedium ? 92 : 56)
                    .overlay {
                        Image(systemName: "map")
                            .foregroundStyle(MilehoundBrandColors.brandBottom)
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(SharedL10n.text("premium.widget.last_trip.name"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if entry.payload.lastTripID != nil {
                    Text(routeLabel)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(DateFormatters.formatDistance(entry.payload.lastTripDistanceMeters))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(SharedL10n.text("premium.widget.last_trip.empty"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if family == .systemMedium, entry.recording.showsRecordingControls {
                recordingControls
            }
        }
        .widgetURL(tripURL)
        .accessibilityLabel(SharedL10n.text("premium.widget.last_trip.a11y"))
    }

    @ViewBuilder
    private var recordingControls: some View {
        HStack(spacing: 8) {
            if entry.recording.isPaused {
                Button(intent: HomeWidgetResumeRecordingIntent()) {
                    Image(systemName: "play.fill")
                }
                .tint(MilehoundBrandColors.resume)
            } else {
                Button(intent: HomeWidgetPauseRecordingIntent()) {
                    Image(systemName: "pause.fill")
                }
                .tint(MilehoundBrandColors.paused)
            }
            Button(intent: HomeWidgetStopRecordingIntent()) {
                Image(systemName: "stop.fill")
            }
            .tint(MilehoundBrandColors.stop)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(SharedL10n.text("live_activity.recording"))
    }

    private var routeLabel: String {
        let start = entry.payload.lastTripStart
        let end = entry.payload.lastTripEnd
        if start.isEmpty && end.isEmpty { return "—" }
        return "\(start) → \(end)"
    }

    private var tripURL: URL {
        if let id = entry.payload.lastTripID {
            return MilehoundDeepLink.trip(id)
        }
        return MilehoundDeepLink.statsRecap
    }

    private var previewImage: UIImage? {
        guard entry.payload.lastTripHasPreview,
              let url = PremiumWidgetPayload.lastTripPreviewURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

struct LastTripWidget: Widget {
    let kind = "LastTripWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastTripWidgetProvider()) { entry in
            LastTripWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetAdaptiveBackground()
                }
        }
        .configurationDisplayName(SharedL10n.text("premium.widget.last_trip.name"))
        .description(SharedL10n.text("premium.widget.last_trip.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("idle", as: .systemSmall) {
    LastTripWidget()
} timeline: {
    LastTripWidgetEntry.current()
}

#Preview("idle medium", as: .systemMedium) {
    LastTripWidget()
} timeline: {
    LastTripWidgetEntry.current()
}
