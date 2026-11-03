import SwiftUI

struct RecordToastView: View {
    let payload: PersonalRecordBreak

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    @State private var settled = false
    @State private var valuesVisible = false
    @State private var iconBounceToken = 0
    @State private var glintID = "record.toast"

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ToastEmblemDisc(
                systemImage: discSymbol,
                animation: .bounce,
                fill: tone.fill(scheme: colorScheme, palette: shellPalette),
                glow: tone.glow(scheme: colorScheme, palette: shellPalette),
                token: iconBounceToken,
                settled: settled
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.toastRecordKicker)
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(GlassText.secondary(for: colorScheme))
                    .opacity(settled ? 1 : 0.55)
                valueLines
                    .opacity(valuesVisible ? 1 : 0)
                    .offset(y: valuesVisible || reduceMotion ? 0 : 4)
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, GlassTokens.toastHorizontalPadding)
        .padding(.vertical, GlassTokens.toastVerticalPadding)
        .frame(minHeight: GlassTokens.toastMinHeight)
        .frame(maxWidth: GlassTokens.toastMaxWidth)
        .fixedSize(horizontal: true, vertical: false)
        .glassChrome(cornerRadius: GlassTokens.toastCornerRadius)
        .glassEntranceGlint(
            cornerRadius: GlassTokens.toastCornerRadius,
            id: glintID,
            isEnabled: !reduceMotion && !UITestSupport.isEnabled
        )
        .shadow(
            color: .black.opacity(settled ? 0.18 : 0.05),
            radius: settled ? 18 : 6,
            y: settled ? 8 : 2
        )
        .scaleEffect(settled ? 1 : 0.96, anchor: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(payload.accessibilityMessage)
        .onAppear(perform: playEntrance)
        .onChange(of: payload) { _, _ in
            playEntrance()
        }
    }

    @ViewBuilder
    private var valueLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let longest = payload.longestText {
                Text(L10n.toastRecordLongest(longest))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(1)
            }
            if let fastest = payload.fastestText {
                Text(L10n.toastRecordFastest(fastest))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var discSymbol: String {
        if payload.longestDistanceMeters != nil, payload.fastestCruiseKmh != nil {
            "trophy.fill"
        } else if payload.fastestCruiseKmh != nil {
            "gauge.with.dots.needle.67percent"
        } else {
            "flag.checkered"
        }
    }

    private var tone: ToastEmblemTone {
        payload.longestDistanceMeters != nil ? .gold : .palette
    }

    private func playEntrance() {
        if reduceMotion || UITestSupport.isEnabled {
            settled = true
            valuesVisible = true
            return
        }
        settled = false
        valuesVisible = false
        glintID = "record.toast.\(UUID().uuidString)"
        withAnimation(MilehoundMotion.pinPop) {
            settled = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            iconBounceToken += 1
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(MilehoundMotion.snappy) {
                valuesVisible = true
            }
        }
    }
}
