import Charts
import SwiftUI

struct VehicleCostDonutChart: View {
    let snapshot: VehicleCostSnapshot
    let currencyCode: String

    private struct Slice: Identifiable {
        let id: VehicleCostBucket
        let name: String
        let amount: Double
    }

    private var slices: [Slice] {
        let candidates: [(VehicleCostBucket, Double)] = [
            (.fuel, snapshot.fuelTotal),
            (.service, snapshot.serviceTotal),
            (.insurance, snapshot.insuranceTotal),
            (.casco, snapshot.cascoTotal),
            (.other, snapshot.otherTotal)
        ]
        return candidates.compactMap { bucket, amount in
            guard amount > 0 else { return nil }
            return Slice(id: bucket, name: bucket.displayName, amount: amount)
        }
    }

    private var legendItems: [StatsDonutLegendItem] {
        slices.map { slice in
            StatsDonutLegendItem(
                id: slice.id.rawValue,
                name: slice.name,
                color: StatsChartTheme.bucketColor(for: slice.id),
                value: FuelCostCalculator.formatCost(slice.amount, currencyCode: currencyCode)
            )
        }
    }

    var body: some View {
        if slices.isEmpty {
            Text(L10n.string("vehicles.care.chart.empty"))
                .font(.caption)
                .glassSecondaryInk()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: StatsChartTheme.donutLegendTopPadding) {
                ZStack {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amount),
                            innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                            angularInset: StatsChartTheme.donutAngularInset
                        )
                        .foregroundStyle(StatsChartTheme.bucketColor(for: slice.id))
                    }
                    .chartLegend(.hidden)
                    .statsChartCardLayout()
                    .frame(height: 150)

                    VStack(spacing: 2) {
                        Text(FuelCostCalculator.formatCost(snapshot.total, currencyCode: currencyCode))
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(L10n.string("stats.cost.chart.center_total"))
                            .font(.caption2)
                            .glassSecondaryInk()
                    }
                    .padding(.horizontal, 8)
                }

                StatsDonutLegendGrid(items: legendItems)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
