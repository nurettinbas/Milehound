import SwiftUI

/// Receipt rows in the expense form: Add receipt, or thumbnail + Read amount / Replace / Remove.
struct ExpenseReceiptSection: View {
    let fileName: String?
    let isImporting: Bool
    let onAdd: () -> Void
    let onView: () -> Void
    let onScan: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: UIImage?

    var body: some View {
        Section {
            if let fileName {
                attachedRow(fileName: fileName)
                    .glassRow(position: .first)

                Button {
                    MilehoundHaptics.selection()
                    onAdd()
                } label: {
                    Text(L10n.string("vehicles.care.expense.receipt.replace"))
                        .font(.body.weight(.semibold))
                        .glassPrimaryInk()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPlainHit)
                .disabled(isImporting)
                .glassRow(position: .middle)
                .accessibilityIdentifier("vehicles.care.expense.receipt.replace")

                Button(L10n.string("vehicles.care.expense.receipt.remove"), role: .destructive) {
                    MilehoundHaptics.selection()
                    onRemove()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .destructiveTint()
                .glassRow(position: .last)
                .accessibilityIdentifier("vehicles.care.expense.receipt.remove")
            } else {
                addRow
                    .glassRow(position: .only)
            }
        } header: {
            Text(L10n.string("vehicles.care.expense.receipt"))
        } footer: {
            Text(L10n.string("vehicles.care.expense.receipt.footer"))
        }
    }

    private var addRow: some View {
        Button {
            MilehoundHaptics.selection()
            onAdd()
        } label: {
            HStack(spacing: 8) {
                if isImporting {
                    ProgressView()
                } else {
                    Image(systemName: "doc.text.viewfinder")
                }
                Text(L10n.string("vehicles.care.expense.receipt.add"))
            }
            .font(.body.weight(.semibold))
            .glassPrimaryInk()
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassPlainHit)
        .disabled(isImporting)
        .accessibilityIdentifier("vehicles.care.expense.receipt.add")
    }

    private func attachedRow(fileName: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                MilehoundHaptics.selection()
                onView()
            } label: {
                ReceiptThumbnailTile(image: thumbnail)
                    .overlay {
                        if isImporting {
                            ProgressView()
                        }
                    }
            }
            .buttonStyle(.milehoundCardPress)
            .accessibilityLabel(L10n.string("vehicles.care.expense.receipt.view"))
            .accessibilityIdentifier("vehicles.care.expense.receipt.thumbnail")

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("vehicles.care.expense.receipt.attached"))
                        .font(.subheadline.weight(.semibold))
                        .glassPrimaryInk()
                    Text(L10n.string("vehicles.care.expense.receipt.tap_to_view"))
                        .font(.caption)
                        .glassSecondaryInk()
                }

                Button {
                    MilehoundHaptics.selection()
                    onScan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.viewfinder")
                        Text(L10n.string("vehicles.care.expense.receipt.scan"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.glassPlainHit)
                .milehoundCompactProminentButton()
                .padding(.leading, -6)
                .disabled(isImporting)
                .accessibilityIdentifier("vehicles.care.expense.receipt.scan")
            }

            Spacer(minLength: 0)
        }
        .task(id: fileName) {
            let cached = ExpenseReceiptStore.shared.cachedThumbnail(fileName: fileName)
            if let cached {
                thumbnail = cached
                return
            }
            thumbnail = nil
            let loaded = await ExpenseReceiptStore.shared.thumbnail(fileName: fileName)
            if reduceMotion {
                thumbnail = loaded
            } else {
                withAnimation(MilehoundMotion.photoSettle) {
                    thumbnail = loaded
                }
            }
        }
    }
}
