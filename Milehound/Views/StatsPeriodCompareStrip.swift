import SwiftUI

struct StatsPeriodCompareRow: Identifiable {
    let id: String
    let title: String
    let currentText: String
    let previousText: String
    let trend: StatsTrend?
}

/// Period-over-period row model plus the trend badge.
/// The old spreadsheet strip lives on Stats hero / nested tiles now.
struct StatsPeriodCompareStrip: View {
    let currentLabel: String
    let previousLabel: String
    let rows: [StatsPeriodCompareRow]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(currentLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(previousLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: 64)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            .accessibilityHidden(true)

            ForEach(rows) { row in
                compareRow(row)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func compareRow(_ row: StatsPeriodCompareRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .lineLimit(1)
                Text(row.currentText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.previousText)
                .font(.caption)
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatsTrendBadge(trend: row.trend, metricName: row.title)
                .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func accessibilityLabel(for row: StatsPeriodCompareRow) -> String {
        var parts = [
            row.title,
            "\(currentLabel) \(row.currentText)",
            "\(previousLabel) \(row.previousText)"
        ]
        if let trend = row.trend, let a11y = Optional(trend.accessibilityLabel(metricName: row.title)) {
            parts.append(a11y)
        }
        return parts.joined(separator: ", ")
    }
}

struct StatsTrendBadge: View {
    let trend: StatsTrend?
    var metricName: String = ""

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        if let trend {
            HStack(spacing: 2) {
                if let systemImage = trend.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 8, weight: .bold))
                }
                if let text = trend.displayText {
                    Text(text)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(chipInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                chipFill,
                                chipFill.opacity(0.82)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .dark ? 0.28 : 0.42),
                                lineWidth: 0.75
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.18),
                radius: 2,
                y: 1
            )
            .accessibilityLabel(trend.accessibilityLabel(metricName: metricName))
        }
    }

    private var chipFill: Color {
        guard let trend else { return .clear }
        if trend.isNovel { return novelChipFill }
        return Self.fill(for: trend, colorScheme: colorScheme)
    }

    private var chipInk: Color {
        Color.white
    }

    private var novelChipRGB: ShellRGB {
        colorScheme == .dark
            ? shellPalette.atmosphere(for: .dark).tint
            : GlassContrast.selectedChipFill(palette: shellPalette)
    }

    private var novelChipFill: Color {
        novelChipRGB.color
    }

    static let neutralChipFill = Color.white.opacity(0.22)

    static func fill(for trend: StatsTrend, colorScheme: ColorScheme) -> Color {
        switch trend.isFavorable {
        case true: GlassSemantic.success(for: colorScheme)
        case false: GlassSemantic.destructive(for: colorScheme)
        case nil: neutralChipFill
        }
    }
}
