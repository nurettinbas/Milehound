import Charts
import SwiftUI

struct VehicleCareMiniChart: View {
    let months: [VehicleMonthlyCost]
    let days: [VehicleDailyCost]
    let periodStart: Date
    let periodEnd: Date
    let currencyCode: String

    private var useDaily: Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: periodStart)
        let end = calendar.startOfDay(for: periodEnd)
        let spanDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return spanDays <= 31
    }

    var body: some View {
        if useDaily {
            dailyChart
        } else {
            monthlyChart
        }
    }

    /// Only days that actually have recorded expenses.
    private var dailyEntries: [VehicleDailyCost] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: periodStart)
        let end = calendar.startOfDay(for: periodEnd)
        return days
            .filter { $0.total > 0 && $0.dayStart >= start && $0.dayStart <= end }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private var monthlyEntries: [VehicleMonthlyCost] {
        months.filter { $0.total > 0 }
    }

    @ViewBuilder
    private var dailyChart: some View {
        let entries = dailyEntries
        let categories = presentCategories(in: entries)
        let legendCategories = legendCategories(from: categories, in: entries.map(\.amounts))
        if entries.isEmpty {
            emptyState
        } else {
            Chart {
                ForEach(entries) { entry in
                    ForEach(categories, id: \.self) { category in
                        let value = entry.amount(for: category)
                        if value > 0 {
                            BarMark(
                                x: .value("Day", entry.dayStart, unit: .day),
                                y: .value("Amount", value),
                                width: barWidth(forCount: entries.count)
                            )
                            .foregroundStyle(by: .value("Category", category.displayName))
                            .cornerRadius(StatsChartTheme.barCornerRadius)
                        }
                    }
                    PointMark(
                        x: .value("Day", entry.dayStart, unit: .day),
                        y: .value("Amount", entry.total)
                    )
                    .opacity(0)
                    .annotation(position: .top, spacing: 2) {
                        StatsBarValueLabel(
                            text: FuelCostCalculator.formatCost(entry.total, currencyCode: currencyCode),
                            barCount: entries.count
                        )
                    }
                }
            }
            .modifier(CostBarChartStyle(
                dates: entries.map(\.dayStart),
                xPaddingComponent: .day,
                xValues: dailyXAxisValues(entries),
                xLabel: { DateFormatters.chartDay.string(from: $0) },
                currencyCode: currencyCode,
                legendDomain: legendCategories.map(\.displayName),
                legendRange: legendCategories.map(StatsChartTheme.categoryColor(for:)),
                accessibilityKey: "stats.chart.daily_expenses",
                maxValue: entries.map(\.total).max() ?? 0
            ))
        }
    }

    @ViewBuilder
    private var monthlyChart: some View {
        let entries = monthlyEntries
        let categories = presentMonthlyCategories(in: entries)
        let legendCategories = legendCategories(from: categories, in: entries.map(\.amounts))
        if entries.isEmpty {
            emptyState
        } else {
            Chart {
                ForEach(entries) { entry in
                    ForEach(categories, id: \.self) { category in
                        let value = entry.amount(for: category)
                        if value > 0 {
                            BarMark(
                                x: .value("Month", entry.monthStart, unit: .month),
                                y: .value("Amount", value),
                                width: barWidth(forCount: entries.count)
                            )
                            .foregroundStyle(by: .value("Category", category.displayName))
                            .cornerRadius(StatsChartTheme.barCornerRadius)
                        }
                    }
                    PointMark(
                        x: .value("Month", entry.monthStart, unit: .month),
                        y: .value("Amount", entry.total)
                    )
                    .opacity(0)
                    .annotation(position: .top, spacing: 2) {
                        StatsBarValueLabel(
                            text: FuelCostCalculator.formatCost(entry.total, currencyCode: currencyCode),
                            barCount: entries.count
                        )
                    }
                }
            }
            .modifier(CostBarChartStyle(
                dates: entries.map(\.monthStart),
                xPaddingComponent: .month,
                xValues: entries.map(\.monthStart),
                xLabel: { DateFormatters.monthYear.string(from: $0) },
                currencyCode: currencyCode,
                legendDomain: legendCategories.map(\.displayName),
                legendRange: legendCategories.map(StatsChartTheme.categoryColor(for:)),
                accessibilityKey: "stats.cost.chart.monthly",
                maxValue: entries.map(\.total).max() ?? 0
            ))
        }
    }

    private var emptyState: some View {
        Text(L10n.string("vehicles.care.chart.empty"))
            .font(.caption)
            .glassSecondaryInk()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private func presentCategories(in entries: [VehicleDailyCost]) -> [VehicleExpenseCategory] {
        VehicleExpenseCategory.allCases.filter { category in
            entries.contains { $0.amount(for: category) > 0 }
        }
    }

    private func presentMonthlyCategories(in entries: [VehicleMonthlyCost]) -> [VehicleExpenseCategory] {
        VehicleExpenseCategory.allCases.filter { category in
            entries.contains { $0.amount(for: category) > 0 }
        }
    }

    private func legendCategories(
        from present: [VehicleExpenseCategory],
        in amounts: [VehicleExpenseCategoryAmounts]
    ) -> [VehicleExpenseCategory] {
        VehicleExpenseLegendCap.categories(present) { category in
            amounts.reduce(0) { $0 + $1.amount(for: category) }
        }
    }

    private func barWidth(forCount count: Int) -> MarkDimension {
        switch count {
        case 1: return .ratio(0.28)
        case 2: return .ratio(0.36)
        case 3...5: return .ratio(0.45)
        default: return .ratio(0.55)
        }
    }

    private func dailyXAxisValues(_ entries: [VehicleDailyCost]) -> [Date] {
        guard entries.count > 5 else { return entries.map(\.dayStart) }
        let step = max(1, (entries.count - 1) / 3)
        var values: [Date] = []
        for index in stride(from: 0, to: entries.count, by: step) {
            values.append(entries[index].dayStart)
        }
        if let last = entries.last?.dayStart, values.last != last {
            values.append(last)
        }
        return values
    }
}

private struct CostBarChartStyle: ViewModifier {
    let dates: [Date]
    let xPaddingComponent: Calendar.Component
    let xValues: [Date]
    let xLabel: (Date) -> String
    let currencyCode: String
    let legendDomain: [String]
    let legendRange: [Color]
    let accessibilityKey: StaticString
    let maxValue: Double

    private var xDomain: [Date] {
        StatsChartTheme.xScaleDomain(from: dates, padding: xPaddingComponent)
    }

    private var legendItems: [(name: String, color: Color)] {
        Array(zip(legendDomain, legendRange)).map { (name: $0.0, color: $0.1) }
    }

    func body(content: Content) -> some View {
        Group {
            if xDomain.count >= 2 {
                VStack(spacing: StatsChartTheme.legendRowSpacing) {
                    content
                        .chartForegroundStyleScale(domain: legendDomain, range: legendRange)
                        .chartBarValueHeadroom(maxValue: maxValue)
                        .chartXScale(domain: xDomain)
                        .chartStatsDateXAxis(values: xValues, label: xLabel)
                        .chartYAxis {
                            AxisMarks(values: .automatic) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.secondary.opacity(0.2))
                                if let amount = value.as(Double.self) {
                                    AxisValueLabel {
                                        Text(FuelCostCalculator.formatCost(amount, currencyCode: currencyCode))
                                            .font(.caption2)
                                            .foregroundStyle(StatsChartTheme.axisLabelInk)
                                    }
                                }
                            }
                        }
                        .chartStatsYAxisUnit(currencyCode)
                        .chartLegend(.hidden)
                        .frame(maxWidth: .infinity)
                        .frame(height: StatsChartTheme.costBarPlotHeight)

                    costLegend
                        .frame(height: StatsChartTheme.costBarLegendHeight, alignment: .top)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.string(accessibilityKey))
            }
        }
    }

    private var costLegend: some View {
        let columns = StatsChartTheme.legendColumns
        let rows = stride(from: 0, to: legendItems.count, by: columns).map { start in
            Array(legendItems[start..<min(start + columns, legendItems.count)])
        }
        return VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: StatsChartTheme.legendCellSpacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(
                                    width: StatsChartTheme.legendDotSize,
                                    height: StatsChartTheme.legendDotSize
                                )
                            Text(item.name)
                                .font(.caption2)
                                .glassSecondaryInk()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
