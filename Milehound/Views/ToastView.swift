import SwiftUI

struct ToastView: View {
    let kind: ToastKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var iconBounceToken = 0
    @State private var settled = false
    @State private var glintID = "toast"

    var body: some View {
        HStack(spacing: 12) {
            ToastEmblemDisc(
                systemImage: kind.systemImage,
                animation: kind.symbolAnimation,
                fill: kind.emblemTone.fill(scheme: colorScheme, palette: shellPalette),
                glow: kind.emblemTone.glow(scheme: colorScheme, palette: shellPalette),
                token: iconBounceToken,
                settled: settled
            )
            Text(kind.message)
                .font(.callout.weight(.semibold))
                .foregroundStyle(GlassText.primary(for: colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(settled ? 1 : 0.72)
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
        .accessibilityLabel(kind.message)
        .onAppear(perform: playEntrance)
        .onChange(of: kind) { _, _ in
            playEntrance()
        }
    }

    private func playEntrance() {
        if reduceMotion || UITestSupport.isEnabled {
            settled = true
            return
        }
        settled = false
        glintID = "toast.\(UUID().uuidString)"
        withAnimation(MilehoundMotion.pinPop) {
            settled = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            iconBounceToken += 1
        }
    }
}

struct ToastEmblemDisc: View {
    let systemImage: String
    let animation: ToastSymbolAnimation
    let fill: LinearGradient
    let glow: Color
    let token: Int
    let settled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            Circle()
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
            ToastAnimatedSymbol(
                name: systemImage,
                animation: animation,
                token: token,
                reduceMotion: reduceMotion
            )
        }
        .frame(width: GlassTokens.toastIconDiscSide, height: GlassTokens.toastIconDiscSide)
        .scaleEffect(settled || reduceMotion ? 1 : 0.68)
        .rotationEffect(.degrees((settled || reduceMotion) ? 0 : -10))
        .shadow(color: glow.opacity(settled ? 0.55 : 0.12), radius: settled ? 10 : 2, y: 2)
        .accessibilityHidden(true)
    }
}

struct ToastAnimatedSymbol: View {
    let name: String
    let animation: ToastSymbolAnimation
    let token: Int
    let reduceMotion: Bool

    var body: some View {
        let base = Image(systemName: name)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
        if reduceMotion {
            base
        } else {
            animated(base)
        }
    }

    @ViewBuilder
    private func animated(_ base: some View) -> some View {
        switch animation {
        case .bounce:
            bounce(base)
        case .pulse:
            pulse(base)
        case .wiggle:
            wiggle(base)
        case .rotate:
            rotate(base)
        }
    }

    @ViewBuilder
    private func bounce(_ base: some View) -> some View {
        if #available(iOS 18.0, *) {
            base.symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: token)
        } else {
            base.symbolEffect(.bounce, options: .nonRepeating, value: token)
        }
    }

    @ViewBuilder
    private func pulse(_ base: some View) -> some View {
        if #available(iOS 18.0, *) {
            base.symbolEffect(.pulse.byLayer, options: .nonRepeating, value: token)
        } else {
            base.symbolEffect(.pulse, options: .nonRepeating, value: token)
        }
    }

    @ViewBuilder
    private func wiggle(_ base: some View) -> some View {
        if #available(iOS 18.0, *) {
            base.symbolEffect(.wiggle, options: .nonRepeating, value: token)
        } else {
            base.symbolEffect(.bounce, options: .nonRepeating, value: token)
        }
    }

    @ViewBuilder
    private func rotate(_ base: some View) -> some View {
        if #available(iOS 18.0, *) {
            base.symbolEffect(.rotate, options: .nonRepeating, value: token)
        } else {
            base.symbolEffect(.pulse, options: .nonRepeating, value: token)
        }
    }
}
