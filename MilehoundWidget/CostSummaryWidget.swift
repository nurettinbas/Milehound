import SwiftUI
import WidgetKit

struct CostSummaryWidgetEntry: TimelineEntry {
    let date: Date
    let payload: PremiumWidgetPayload

    static func current(at date: Date = Date()) -> CostSummaryWidgetEntry {
        CostSummaryWidgetEntry(date: date, payload: .load())
    }
}

struct CostSummaryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CostSummaryWidgetEntry { .current() }
    func getSnapshot(in context: Context, completion: @escaping (CostSummaryWidgetEntry) -> Void) {
        completion(.current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CostSummaryWidgetEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [.current()], policy: .after(next)))
    }
}

struct CostSummaryWidgetView: View {
    let entry: CostSummaryWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SharedL10n.text("premium.widget.cost.name"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatted(entry.payload.projectedTotal))
                .font(.title2.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(SharedL10n.text("premium.widget.cost.subtitle"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if family == .systemMedium {
                HStack {
                    Label(formatted(entry.payload.projectedFuel), systemImage: "fuelpump")
                    if entry.payload.installmentsDue > 0 {
                        Label(formatted(entry.payload.installmentsDue), systemImage: "calendar")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if let ratio = entry.payload.trendRatio {
                Text(trendLabel(ratio))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ratio >= 0 ? Color.orange : Color.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(MilehoundDeepLink.statsForecast)
        .accessibilityLabel(SharedL10n.text("premium.widget.cost.a11y"))
        .accessibilityValue(formatted(entry.payload.projectedTotal))
    }

    private func formatted(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = entry.payload.currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount.rounded()))"
    }

    private func trendLabel(_ ratio: Double) -> String {
        let percent = Int((abs(ratio) * 100).rounded())
        let key = ratio >= 0 ? "premium.forecast.trend.up" : "premium.forecast.trend.down"
        return String(format: SharedL10n.text(key), percent)
    }
}

struct CostSummaryWidget: Widget {
    let kind = "CostSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CostSummaryWidgetProvider()) { entry in
            CostSummaryWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetAdaptiveBackground()
                }
        }
        .configurationDisplayName(SharedL10n.text("premium.widget.cost.name"))
        .description(SharedL10n.text("premium.widget.cost.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("idle", as: .systemSmall) {
    CostSummaryWidget()
} timeline: {
    CostSummaryWidgetEntry.current()
}

#Preview("idle medium", as: .systemMedium) {
    CostSummaryWidget()
} timeline: {
    CostSummaryWidgetEntry.current()
}
