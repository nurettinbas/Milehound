import SwiftUI

struct YearRecapPromoView: View {
    let snapshot: YearRecapSnapshot
    var onPlay: () -> Void
    var onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pulsePlay: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(style: .full)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        content(posterHeight: RecapHubTeaserMetrics.promoHeight)
                    }
                } else {
                    GeometryReader { geo in
                        let height = min(
                            RecapHubTeaserMetrics.promoHeight,
                            max(200, geo.size.height - 240)
                        )
                        content(posterHeight: height)
                    }
                }
            }
        }
        .accessibilityIdentifier("stats.premium.recap.promo")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MilehoundBrandMark(showsWordmark: true, symbolSize: 32, axis: .horizontal)
            Spacer(minLength: 8)
            Button(action: onClose) {
                GlassNavCircleIcon(systemName: "xmark")
            }
            .buttonStyle(.glassPlainHit)
            .accessibilityIdentifier("stats.premium.recap.promo.close")
            .accessibilityLabel(L10n.string("premium.recap.close_a11y"))
        }
    }

    private func content(posterHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            RecapHubTeaserScene(
                height: posterHeight,
                allowsIdleMotion: !dynamicTypeSize.isAccessibilitySize,
                cornerRadius: StatsCardTokens.radius
            )
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("premium.recap.promo.title"))
                    .font(.title.weight(.bold))
                    .glassPrimaryInk()
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: L10n.string("premium.recap.promo.body"), snapshot.year))
                    .font(.body)
                    .glassSecondaryInk()
                    .fixedSize(horizontal: false, vertical: true)
            }
            playButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .symbolEffect(.pulse, options: .repeating, isActive: pulsePlay)
                Text(L10n.string("premium.recap.play"))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .milehoundProminentButton()
        .accessibilityIdentifier("stats.premium.recap.promo.play")
        .accessibilityLabel(L10n.string("premium.recap.play"))
    }
}
