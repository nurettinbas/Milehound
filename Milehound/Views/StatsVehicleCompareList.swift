import SwiftUI

/// Ranked vehicle expense list. Capsule bars only — no Swift Charts.
struct StatsVehicleCompareList: View {
    let rows: [VehicleCompareRow]
    let currencyCode: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                Text(L10n.string("stats.compare.vehicles_title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HelpPopoverButton(
                    accessibilityLabel: L10n.loggedVehicleExpensesHelpTitle,
                    message: L10n.loggedVehicleExpensesHelpBody,
                    side: 18
                )
                Spacer(minLength: 0)
            }

            ForEach(rows) { row in
                vehicleRow(row)
            }
        }
    }

    private func vehicleRow(_ row: VehicleCompareRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VehicleAvatarView(
                    systemImage: row.iconName,
                    photoFileName: row.photoFileName,
                    size: 28,
                    cornerRadius: 7,
                    isElectricAccent: row.isElectric,
                    showsBrandRing: row.isMostExpensive
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if row.isMostExpensive {
                            Text(L10n.string("stats.compare.most_expensive"))
                                .font(.system(size: 9, weight: .bold))
                                .glassAccentForeground()
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(FuelCostCalculator.formatCost(row.amount, currencyCode: currencyCode))
                            .font(.caption.weight(.semibold))
                        Text(costPerKmText(row))
                            .font(.caption2)
                            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    }
                }
                Spacer(minLength: 0)
            }

            shareBar(for: row)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func costPerKmText(_ row: VehicleCompareRow) -> String {
        guard let costPerKm = row.costPerKm else {
            return L10n.string("stats.compare.cost_per_km_empty")
        }
        let formatted = FuelCostCalculator.formatCost(costPerKm, currencyCode: currencyCode)
        return String(format: L10n.string("stats.compare.cost_per_km"), formatted)
    }

    private func shareBar(for row: VehicleCompareRow) -> some View {
        StatsShareBar(
            share: StatsVehicleCompareBuilder.barShare(amount: row.amount, maxAmount: maxAmount),
            fill: StatsChartTheme.sliceColor(
                forStableKey: row.id,
                durationStyle: false,
                domainKeys: vehicleKeys,
                palette: shellPalette,
                scheme: colorScheme
            )
        )
    }

    private var vehicleKeys: [String] { rows.map(\.id) }

    private var maxAmount: Double { rows.map(\.amount).max() ?? 0 }

    private func accessibilityLabel(for row: VehicleCompareRow) -> String {
        var parts = [
            row.displayName,
            FuelCostCalculator.formatCost(row.amount, currencyCode: currencyCode),
            costPerKmText(row)
        ]
        if row.isMostExpensive {
            parts.append(L10n.string("stats.compare.most_expensive"))
        }
        return parts.joined(separator: ", ")
    }
}
