import SwiftUI
import UIKit

/// Glyph inside the showcase disc.
enum GlassShowcaseEmblem: Equatable {
    case symbol(String)
    /// The brand running hound (Trips).
    case hound
}

/// One feature or step under the showcase title.
struct GlassShowcaseHighlight: Hashable, Identifiable {
    let systemImage: String
    let title: String

    var id: String { "\(systemImage)|\(title)" }
}

/// Arrangement picked from the room a page gives the empty state.
/// Tall panes stack; a short and wide pane (phone book, landscape list beside the
/// recording card) puts the emblem beside the text; a short and narrow pane keeps
/// only the emblem, title, and message.
enum GlassShowcaseLayout: Equatable {
    case regular
    case condensed
    case wide
    case minimal

    static let regularMinHeight: CGFloat = 430
    static let condensedMinHeight: CGFloat = 300
    static let wideMinWidth: CGFloat = 440

    /// `nil` room sizes to content and uses the regular stack. Accessibility text
    /// sizes always stack; the pane or list scrolls.
    static func resolve(available: CGSize?, accessibilitySize: Bool) -> GlassShowcaseLayout {
        guard let available, available.height > 1 else { return .regular }
        if accessibilitySize || available.height >= regularMinHeight { return .regular }
        if available.height >= condensedMinHeight { return .condensed }
        return available.width >= wideMinWidth ? .wide : .minimal
    }

    var isHorizontal: Bool { self == .wide || self == .minimal }

    var showsHighlights: Bool { self != .minimal }

    /// Disc diameter. The halo rings draw out to `GlassShowcaseEmblemView.frameScale` × this.
    func emblemSide(available: CGSize?) -> CGFloat {
        switch self {
        case .regular:
            return 100
        case .condensed:
            return 70
        case .wide:
            return min(84, max(52, (available?.height ?? 200) * 0.42))
        case .minimal:
            return min(52, max(40, (available?.height ?? 120) * 0.36))
        }
    }

    var maxContentWidth: CGFloat {
        isHorizontal ? 620 : 420
    }
}

/// Full empty state for a page with no data yet: a Liquid Glass emblem with halo rings,
/// a title, a message, optional highlights (steps or features), and optional actions.
/// Sits on the atmosphere, not on a list-row plate (the emblem and highlights are the glass).
struct GlassShowcaseEmptyState<Actions: View>: View {
    let emblem: GlassShowcaseEmblem
    let title: String
    let message: String
    var highlights: [GlassShowcaseHighlight] = []
    /// Chevrons between highlights read them as an ordered flow.
    var highlightsAreSteps = false
    /// Room the page gives the empty state. The view fills that height and centers in it.
    var available: CGSize?
    var accessibilityIdentifier: String?
    @ViewBuilder var actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: GlassShowcaseLayout {
        .resolve(available: available, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        let layout = layout
        let side = layout.emblemSide(available: available)
        Group {
            if layout.isHorizontal {
                horizontal(layout: layout, side: side)
            } else {
                vertical(layout: layout, side: side)
            }
        }
        .frame(maxWidth: layout.maxContentWidth)
        .frame(maxWidth: .infinity, minHeight: available.map { max(0, $0.height) })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func vertical(layout: GlassShowcaseLayout, side: CGFloat) -> some View {
        VStack(spacing: layout == .regular ? 22 : 14) {
            GlassShowcaseEmblemView(emblem: emblem, side: side)
            textBlock(layout: layout, alignment: .center)
                .frame(maxWidth: 360)
            if layout.showsHighlights, !highlights.isEmpty {
                if layout == .regular {
                    GlassShowcaseHighlightCard(highlights: highlights, areSteps: highlightsAreSteps)
                } else {
                    GlassShowcaseHighlightChips(highlights: highlights, alignment: .center)
                }
            }
            actions()
                .frame(maxWidth: 320)
        }
        .padding(.vertical, layout == .regular ? 24 : 12)
        .padding(.horizontal, 20)
    }

    private func horizontal(layout: GlassShowcaseLayout, side: CGFloat) -> some View {
        HStack(spacing: layout == .wide ? 24 : 16) {
            GlassShowcaseEmblemView(emblem: emblem, side: side)
            VStack(alignment: .leading, spacing: 10) {
                textBlock(layout: layout, alignment: .leading)
                if layout.showsHighlights, !highlights.isEmpty {
                    GlassShowcaseHighlightChips(highlights: highlights, alignment: .leading)
                }
                actions()
                    .frame(maxWidth: 300, alignment: .leading)
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
    }

    private func textBlock(layout: GlassShowcaseLayout, alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 6) {
            Text(title)
                .font(titleFont(layout))
                .glassPrimaryInk()
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(layout == .regular ? .subheadline : .footnote)
                .glassSecondaryInk()
                .lineLimit(layout == .minimal ? 3 : nil)
        }
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func titleFont(_ layout: GlassShowcaseLayout) -> Font {
        switch layout {
        case .regular: .title2.weight(.bold)
        case .condensed, .wide: .title3.weight(.bold)
        case .minimal: .headline
        }
    }
}

extension GlassShowcaseEmptyState where Actions == EmptyView {
    init(
        emblem: GlassShowcaseEmblem,
        title: String,
        message: String,
        highlights: [GlassShowcaseHighlight] = [],
        highlightsAreSteps: Bool = false,
        available: CGSize? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            emblem: emblem,
            title: title,
            message: message,
            highlights: highlights,
            highlightsAreSteps: highlightsAreSteps,
            available: available,
            accessibilityIdentifier: accessibilityIdentifier,
            actions: { EmptyView() }
        )
    }
}

extension View {
    /// List row for a showcase: no row plate (the emblem and highlights carry the glass),
    /// no separator, edge to edge so the showcase centers in the list width.
    func showcaseListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}

/// A page whose whole body is the showcase (Stats, Recap, notification preview).
/// Centers in the pane and scrolls only when large text outgrows it.
struct GlassShowcasePane<Content: View>: View {
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content(geo.size)
                    .frame(width: geo.size.width)
                    .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Glass disc with a soft halo, a still outer ring, and a slow orbit ring.
/// Display-link clock: SwiftUI clocks stop inside a `List`.
struct GlassShowcaseEmblemView: View {
    let emblem: GlassShowcaseEmblem
    let side: CGFloat

    /// Layout box relative to the disc. The halo paints past it.
    static let frameScale: CGFloat = 1.42
    private static let spinPeriod: TimeInterval = 18
    private static let bobPeriod: TimeInterval = 4.2

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.glassForcesSolidPlate) private var forcesSolidPlate

    @State private var clock: TimeInterval = 0

    private var animates: Bool {
        !reduceMotion
            && !forcesSolidPlate
            && scenePhase == .active
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var ink: Color {
        colorScheme == .dark ? shellPalette.tintColor(for: .dark) : .white
    }

    private var inkUIColor: UIColor {
        guard colorScheme == .dark else { return .white }
        let rgb = shellPalette.atmosphere(for: .dark).tint
        return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private var halo: Color {
        colorScheme == .dark
            ? shellPalette.tintColor(for: .dark).opacity(0.38)
            : Color.white.opacity(0.34)
    }

    var body: some View {
        let spin = animates ? (clock.truncatingRemainder(dividingBy: Self.spinPeriod) / Self.spinPeriod) * 360 : 0
        let bob = animates ? sin(clock * 2 * .pi / Self.bobPeriod) * 3 * (side / 100) : 0
        let box = side * Self.frameScale

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [halo, halo.opacity(0)],
                        center: .center,
                        startRadius: side * 0.25,
                        endRadius: side * 0.9
                    )
                )
                .frame(width: side * 1.8, height: side * 1.8)

            Circle()
                .strokeBorder(ink.opacity(0.18), lineWidth: 1)
                .frame(width: box, height: box)

            orbit
                .frame(width: side * 1.18, height: side * 1.18)
                .rotationEffect(.degrees(spin))

            Color.clear
                .frame(width: side, height: side)
                .glassCard(cornerRadius: side / 2, contentInset: 0)

            glyph
        }
        .frame(width: box, height: box)
        .offset(y: bob)
        .overlay(alignment: .topLeading) {
            MilehoundDisplayLinkTicker(isRunning: animates, framesPerSecond: 20) { clock = $0 }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    private var orbit: some View {
        let sweep = 0.72
        let radius = side * 0.59
        let end = Angle.degrees(sweep * 360 - 90).radians
        return ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(
                    AngularGradient(
                        colors: [ink.opacity(0), ink.opacity(0.7)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(sweep * 360)
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(ink)
                .frame(width: 6, height: 6)
                .shadow(color: ink.opacity(0.6), radius: 4)
                .offset(x: radius * cos(end), y: radius * sin(end))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch emblem {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: side * 0.38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ink)
        case .hound:
            MilehoundRunningHoundMark(
                width: side * 0.66,
                height: side * 0.35,
                tint: inkUIColor,
                animate: animates
            )
            .frame(width: side * 0.66, height: side * 0.35)
        }
    }
}

/// Highlights as one glass card of columns (tall layout).
private struct GlassShowcaseHighlightCard: View {
    let highlights: [GlassShowcaseHighlight]
    let areSteps: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(highlights) { item in
                        HStack(spacing: 12) {
                            GlassShowcaseHighlightIcon(systemImage: item.systemImage)
                            title(item)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: areSteps ? 0 : 8) {
                    ForEach(Array(highlights.enumerated()), id: \.element.id) { index, item in
                        if areSteps, index > 0 {
                            Image(systemName: "chevron.forward")
                                .font(.caption2.weight(.bold))
                                .glassTertiaryInk()
                                .padding(.top, 12)
                                .accessibilityHidden(true)
                        }
                        VStack(spacing: 8) {
                            GlassShowcaseHighlightIcon(systemImage: item.systemImage)
                            title(item)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .glassCard(contentInset: 14)
        .accessibilityElement(children: .combine)
    }

    private func title(_ item: GlassShowcaseHighlight) -> some View {
        Text(item.title)
            .font(.caption.weight(.semibold))
            .glassPrimaryInk()
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GlassShowcaseHighlightIcon: View {
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .glassAccentForeground()
            .frame(width: 34, height: 34)
            .background(GlassShowcaseFrost.fill(for: colorScheme, palette: shellPalette), in: Circle())
    }
}

/// Disc and chip fill under highlight glyphs. The Light field tint is the atmosphere's own
/// hue and disappears on it, so Light uses a white frost.
enum GlassShowcaseFrost {
    static let lightOpacity = 0.18

    static func fill(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        scheme == .dark
            ? GlassTokens.fieldFill(for: .dark, palette: palette)
            : Color.white.opacity(lightOpacity)
    }
}

/// Highlights as frost capsules (condensed and wide layouts). Wraps to a column when the row does not fit.
private struct GlassShowcaseHighlightChips: View {
    let highlights: [GlassShowcaseHighlight]
    let alignment: HorizontalAlignment

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(tight: false) }
            HStack(spacing: 4) { chips(tight: true) }
            VStack(alignment: alignment, spacing: 6) { chips(tight: false) }
        }
        .accessibilityElement(children: .combine)
    }

    private func chips(tight: Bool) -> some View {
        ForEach(highlights) { item in
            GlassShowcaseChip(item: item, tight: tight)
        }
    }
}

private struct GlassShowcaseChip: View {
    let item: GlassShowcaseHighlight
    var tight = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        HStack(spacing: tight ? 4 : 5) {
            Image(systemName: item.systemImage)
                .font(.caption2.weight(.bold))
                .glassAccentForeground()
            Text(item.title)
                .font(tight ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .glassPrimaryInk()
                .lineLimit(1)
        }
        .padding(.horizontal, tight ? 8 : 10)
        .padding(.vertical, 6)
        .background(GlassShowcaseFrost.fill(for: colorScheme, palette: shellPalette), in: Capsule())
        .fixedSize()
    }
}
