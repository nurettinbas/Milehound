import SwiftUI

struct PairingEmptyState: View {
    let onAddVehicle: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.fill")
                .font(.title2)
                .glassAccentForeground()
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 4) {
                Text(L10n.pairingTabEmptyTitle)
                    .font(.headline)
                Text(L10n.pairingTabEmptyMessage)
                    .font(.caption)
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
            }

            Button(action: onAddVehicle) {
                Label(L10n.pairingTabDefineVehicle, systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .milehoundProminentButton()
            .tint(MilehoundBrandColors.brandBottom)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
