import SwiftUI

struct PairingEmptyState: View {
    var available: CGSize?
    let onAddVehicle: () -> Void

    var body: some View {
        GlassShowcaseEmptyState(
            emblem: .symbol("car.side.fill"),
            title: L10n.pairingTabEmptyTitle,
            message: L10n.pairingTabEmptyMessage,
            highlights: [
                GlassShowcaseHighlight(systemImage: "bolt.car", title: L10n.emptyVehicleHighlightAuto),
                GlassShowcaseHighlight(systemImage: "wrench.and.screwdriver.fill", title: L10n.emptyVehicleHighlightCare),
                GlassShowcaseHighlight(systemImage: "creditcard.fill", title: L10n.emptyVehicleHighlightCosts)
            ],
            available: available,
            accessibilityIdentifier: "pairing.empty"
        ) {
            Button(action: onAddVehicle) {
                Label(L10n.pairingTabDefineVehicle, systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .milehoundProminentButton()
            .tint(MilehoundBrandColors.brandBottom)
        }
    }
}
