import StoreKit
import SwiftUI

/// Support the developer panel content. Shown in `GlassMorphPanel` from Settings.
struct TipJarView: View {
    static let panelAccessibilityID = "tipJar.panel"

    @ObservedObject private var store = TipJarStore.shared

    var body: some View {
        VStack(spacing: 22) {
            header
            options
        }
        .padding(.horizontal, GlassTokens.panelHorizontalInset)
        .padding(.top, 12)
        .task { await store.load() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            GlassPaletteDisc(systemImage: "heart.fill")
            Text(L10n.settingsTipJar)
                .font(.body.weight(.semibold))
                .glassPrimaryInk()
                .multilineTextAlignment(.center)
            Text(L10n.settingsTipJarMessage)
                .font(.footnote)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var options: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(minHeight: GlassTokens.optionCircleSide)
        case .unavailable:
            Text(L10n.settingsTipJarUnavailable)
                .font(.footnote)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("tipJar.unavailable")
        case .loaded:
            GlassOptionGrid {
                ForEach(store.products, id: \.id) { product in
                    tipButton(product)
                }
            }
        }
    }

    private func tipButton(_ product: Product) -> some View {
        Button {
            Task { await store.tip(product) }
        } label: {
            GlassOptionCircle(
                systemImage: symbolName(for: product.id),
                caption: product.displayName,
                detail: product.displayPrice,
                isLoading: store.purchasingID == product.id
            )
        }
        .buttonStyle(.glassPlainHit)
        .disabled(store.purchasingID != nil)
        .accessibilityIdentifier("tipJar.product.\(product.id)")
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
    }

    private func symbolName(for productID: String) -> String {
        switch productID {
        case TipJarStore.productIDs[0]:
            return "cup.and.saucer.fill"
        case TipJarStore.productIDs[1]:
            return "fork.knife"
        case TipJarStore.productIDs[2]:
            return "gift.fill"
        default:
            return "heart.fill"
        }
    }
}
