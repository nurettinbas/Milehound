import SwiftUI

/// Lightweight due row used when a compact card is needed; prefers brand + semantic colors.
struct VehicleCareStatusCard: View {
    let title: String
    let systemImage: String
    let state: VehicleCareDueState
    var action: (() -> Void)?

    private var detail: String {
        VehicleCareDueCalculator.shortSubtitle(for: state)
            ?? L10n.string("vehicles.care.due.none")
    }

    private var detailColor: Color {
        state.isOverdue ? .red : .secondary
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .glassAccentForeground()
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .glassPrimaryInk()
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassPlainHit)
        .disabled(action == nil)
    }
}
