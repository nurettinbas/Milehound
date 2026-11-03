import Charts
import SwiftUI

struct VehicleCostCategoryChart: View {
    let breakdown: [VehicleCategoryCost]
    let currencyCode: String

    private var chartData: [VehicleCategoryCost] {
        breakdown.filter { $0.amount > 0 }
    }

    private var xAxisMax: Double {
        let peak = chartData.map(\.amount).max() ?? 0
        guard peak > 0 else { return 1 }
        return peak * 1.15
    }

    private var xDomain: [Double] {
        StatsChartTheme.xScaleDomain(lower: 0, upper: xAxisMax)
    }

    var body: some View {
        if chartData.isEmpty {
            Text(L10n.string("vehicles.care.chart.empty"))
                .font(.caption)
                .glassSecondaryInk()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            Chart(chartData) { item in
                BarMark(
                    x: .value("Amount", item.amount),
                    y: .value("Category", item.displayName)
                )
                .foregroundStyle(color(for: item))
                .cornerRadius(StatsChartTheme.barCornerRadius)
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    if let amount = value.as(Double.self) {
                        AxisValueLabel {
                            Text(FuelCostCalculator.formatCost(amount, currencyCode: currencyCode))
                                .font(.caption2)
                                .foregroundStyle(StatsChartTheme.axisLabelInk)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(StatsChartTheme.axisLabelInk)
                }
            }
            .statsChartCardLayout()
            .frame(height: max(96, CGFloat(chartData.count) * 32 + 28))
            .accessibilityLabel(L10n.string("stats.cost.chart.by_category"))
        }
    }

    private func color(for item: VehicleCategoryCost) -> Color {
        if item.isTripEstimate {
            return StatsChartTheme.tripEstimateColor
        }
        if let category = item.category {
            return StatsChartTheme.categoryColor(for: category)
        }
        return StatsChartTheme.bucketColor(for: .other)
    }
}
