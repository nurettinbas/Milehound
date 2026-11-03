import SwiftUI

/// Illustration colors for the day/night switch only. Rows and discs stay on the shell palette.
enum GlassDayNightSwitchTokens {
    static let trackWidth: CGFloat = 56
    static let trackHeight: CGFloat = 32
    static let knob: CGFloat = 26
    static let daySkyTop = Color(red: 0.56, green: 0.80, blue: 0.98)
    static let daySkyBottom = Color(red: 0.36, green: 0.64, blue: 0.96)
    static let sun = Color(red: 1.0, green: 0.74, blue: 0.22)
    static let cloud = Color.white
    static let nightTop = Color(red: 0.09, green: 0.11, blue: 0.26)
    static let nightBottom = Color(red: 0.16, green: 0.18, blue: 0.36)
    static let moon = Color(red: 0.96, green: 0.94, blue: 0.88)
}

struct WindowFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

/// Sun on the leading side, moon on the trailing side. The knob is a real `Toggle`.
struct DayNightToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                DayNightSwitchGraphic(isDark: configuration.isOn)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: WindowFramePreferenceKey.self,
                                value: geo.frame(in: .named(MilehoundWindowSpace.name))
                            )
                        }
                    }
            }
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}

struct DayNightSwitchGraphic: View {
    var isDark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var progress: CGFloat

    init(isDark: Bool) {
        self.isDark = isDark
        _progress = State(initialValue: isDark ? 1 : 0)
    }

    var body: some View {
        let direction: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        let travel = GlassDayNightSwitchTokens.trackWidth - GlassDayNightSwitchTokens.knob - 6
        ZStack {
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [GlassDayNightSwitchTokens.daySkyTop, GlassDayNightSwitchTokens.daySkyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .opacity(1 - progress)
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [GlassDayNightSwitchTokens.nightTop, GlassDayNightSwitchTokens.nightBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .opacity(progress)
            stars(direction: direction)
            cloud(direction: direction)
            knob(direction: direction)
                .offset(x: (progress - 0.5) * travel * direction)
        }
        .frame(width: GlassDayNightSwitchTokens.trackWidth, height: GlassDayNightSwitchTokens.trackHeight)
        .clipShape(Capsule(style: .continuous))
        .accessibilityHidden(true)
        .onChange(of: isDark) { _, dark in
            let target: CGFloat = dark ? 1 : 0
            if reduceMotion {
                progress = target
            } else {
                withAnimation(MilehoundMotion.dayNightSwitch) {
                    progress = target
                }
            }
        }
    }

    private func cloud(direction: CGFloat) -> some View {
        HStack(spacing: -3) {
            Circle().frame(width: 8, height: 8)
            Circle().frame(width: 12, height: 12)
            Circle().frame(width: 7, height: 7)
        }
        .foregroundStyle(GlassDayNightSwitchTokens.cloud)
        .offset(x: direction * (12 + progress * 14), y: 3)
        .opacity(1 - progress)
    }

    private func stars(direction: CGFloat) -> some View {
        let points: [(CGFloat, CGFloat, CGFloat)] = [
            (-16, -7, 2.6),
            (-7, 3, 1.7),
            (-18, 6, 1.5),
            (-5, -5, 1.4)
        ]
        return ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                Circle()
                    .fill(Color.white)
                    .frame(width: point.2, height: point.2)
                    .scaleEffect(starAmount(index))
                    .opacity(starAmount(index))
                    .offset(x: direction * point.0, y: point.1)
            }
        }
    }

    private func starAmount(_ index: Int) -> CGFloat {
        let start = 0.42 + CGFloat(index) * 0.08
        return min(1, max(0, (progress - start) / 0.16))
    }

    private func knob(direction: CGFloat) -> some View {
        let cutoutX = direction * (16 - progress * 9)
        let cutoutY = -14 + progress * 8
        return ZStack {
            Circle().fill(GlassDayNightSwitchTokens.sun).opacity(1 - progress)
            Circle().fill(GlassDayNightSwitchTokens.moon).opacity(progress)
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .offset(x: cutoutX, y: cutoutY)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: GlassDayNightSwitchTokens.knob, height: GlassDayNightSwitchTokens.knob)
    }
}

struct ThemeModeSymbolDisc: View {
    var isDark: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        themeSymbol
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(width: GlassTokens.featuredRowDiscSide, height: GlassTokens.featuredRowDiscSide)
            .background {
                Circle()
                    .fill(shellPalette.tintColor(for: colorScheme))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.72), lineWidth: 1) }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var themeSymbol: some View {
        let name = isDark ? "moon.fill" : "sun.max.fill"
        if #available(iOS 18.0, *) {
            Image(systemName: name)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
        } else {
            Image(systemName: name)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

/// Light/Dark hero. The whole row is the switch. Tapping writes `.light` or `.dark` and plays the window fade.
struct ThemeModeHeroRow: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var switchFrame: CGRect = .zero

    private var isDark: Bool {
        switch settings.appearanceMode {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    private var darkBinding: Binding<Bool> {
        Binding(
            get: { isDark },
            set: { dark in
                AppearanceTransitionCoordinator.shared.perform(
                    excluding: switchFrame,
                    reduceMotion: reduceMotion
                ) {
                    settings.appearanceMode = dark ? .dark : .light
                }
            }
        )
    }

    var body: some View {
        Toggle(isOn: darkBinding) {
            HStack(spacing: 12) {
                ThemeModeSymbolDisc(isDark: isDark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDark ? L10n.settingsThemeDarkTitle : L10n.settingsThemeLightTitle)
                        .font(.body.weight(.semibold))
                        .glassPrimaryInk()
                        .contentTransition(.opacity)
                    Text(isDark ? L10n.settingsThemeDarkHint : L10n.settingsThemeLightHint)
                        .font(.footnote)
                        .glassSecondaryInk()
                        .contentTransition(.opacity)
                }
                .animation(reduceMotion ? nil : MilehoundMotion.settingsLabelSwap, value: isDark)
            }
        }
        .toggleStyle(DayNightToggleStyle())
        .sensoryFeedback(.selection, trigger: isDark)
        .accessibilityIdentifier("settings.themeSwitch")
        .onPreferenceChange(WindowFramePreferenceKey.self) { switchFrame = $0 }
    }
}

/// On: follow the iPhone. Off: keep the look that is on screen as an explicit Light or Dark choice.
struct ThemeMatchSystemToggle: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.appearanceMode == .system },
            set: { enabled in
                AppearanceTransitionCoordinator.shared.perform(reduceMotion: reduceMotion) {
                    if enabled {
                        settings.appearanceMode = .system
                    } else {
                        settings.appearanceMode = colorScheme == .dark ? .dark : .light
                    }
                }
            }
        )
    }

    var body: some View {
        Toggle(L10n.settingsThemeMatchSystem, isOn: isOn)
            .glassToggleStyle()
            .accessibilityIdentifier("settings.theme.matchSystem")
    }
}
