import SwiftUI

enum PairingCardStyle {
    static let cardRadius: CGFloat = GlassTokens.cardRadius
}

struct PairingCardContainer<Content: View>: View {
    var allowsNative: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .glassCard(
                cornerRadius: PairingCardStyle.cardRadius,
                contentInset: 0,
                allowsNative: allowsNative
            )
    }
}
