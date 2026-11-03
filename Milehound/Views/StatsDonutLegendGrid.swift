import SwiftUI

struct StatsDonutLegendItem: Identifiable {
    let id: String
    let name: String
    let color: Color
    let value: String
}

/// Lightweight centered donut legend: up to 4 cells per row, no GeometryReader / LazyVGrid.
struct StatsDonutLegendGrid: View {
    let items: [StatsDonutLegendItem]

    @Environment(\.colorScheme) private var colorScheme

    private var rows: [[StatsDonutLegendItem]] {
        stride(from: 0, to: items.count, by: StatsChartTheme.legendColumns).map { start in
            let end = min(start + StatsChartTheme.legendColumns, items.count)
            return Array(items[start..<end])
        }
    }

    var body: some View {
        VStack(spacing: StatsChartTheme.legendRowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                legendRow(row)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func legendRow(_ row: [StatsDonutLegendItem]) -> some View {
        let columns = StatsChartTheme.legendColumns
        let spacing = StatsChartTheme.legendCellSpacing

        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: spacing) {
                ForEach(row) { item in
                    legendCell(item)
                        .frame(maxWidth: .infinity)
                }
            }
            .containerRelativeFrame(
                .horizontal,
                count: columns,
                span: row.count,
                spacing: spacing,
                alignment: .center
            )
            Spacer(minLength: 0)
        }
    }

    private func legendCell(_ item: StatsDonutLegendItem) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle()
                    .fill(item.color)
                    .frame(
                        width: StatsChartTheme.legendDotSize,
                        height: StatsChartTheme.legendDotSize
                    )
                    // Optically center the dot on the caption cap-height, not the full line box.
                    .alignmentGuide(.firstTextBaseline) { dims in
                        dims[VerticalAlignment.center] + dims.height * 0.12
                    }
                Text(item.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
            }
            Text(item.value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}
