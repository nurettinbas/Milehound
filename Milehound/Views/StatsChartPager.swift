import SwiftUI

enum StatsChartPagerMetrics {
    /// Caption title + spacing + 200pt chart.
    static let dailyContentHeight: CGFloat = 236
    /// Title + donut + legend gap + up to 2 centered legend rows.
    static let donutContentHeight: CGFloat = 268
    /// Cost pager: title + spacing + plot + legend (see StatsChartTheme.costBarChartBodyHeight).
    static let costContentHeight: CGFloat = 36 + StatsChartTheme.costBarChartBodyHeight
    static let indicatorHeight: CGFloat = 20
}

/// Horizontal page slider for stacking similar stats charts in one list row.
/// Swipe only — no chevrons. Page dots remain when there is more than one chart.
struct StatsChartPager<Content: View>: View {
    let pageCount: Int
    let contentHeight: CGFloat
    @Binding var selection: Int
    var reduceMotion: Bool
    @ViewBuilder var content: (Int) -> Content

    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var localSelection = 0

    private var motionReduced: Bool {
        reduceMotion || environmentReduceMotion
    }

    private var showsPageIndicator: Bool {
        pageCount > 1
    }

    private var clampedSelection: Int {
        guard pageCount > 0 else { return 0 }
        return min(max(0, selection), pageCount - 1)
    }

    private var clampedLocalSelection: Int {
        guard pageCount > 0 else { return 0 }
        return min(max(0, localSelection), pageCount - 1)
    }

    private var scrollPosition: Binding<Int?> {
        Binding(
            get: { pageCount > 0 ? clampedLocalSelection : nil },
            set: { newValue in
                guard pageCount > 0, let newValue else { return }
                let next = min(max(0, newValue), pageCount - 1)
                guard next != localSelection else { return }
                localSelection = next
            }
        )
    }

    var body: some View {
        if pageCount <= 0 {
            EmptyView()
        } else {
            pagerBody
        }
    }

    private var pagerBody: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        content(index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .containerRelativeFrame(.horizontal)
                            .glassCarouselPage()
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrollPosition)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight)
            .clipped()
            .onAppear { localSelection = clampedSelection }
            .onChange(of: selection) { _, newValue in
                if localSelection != newValue {
                    localSelection = newValue
                }
            }
            .modifier(StatsChartPagerSettleSync(localSelection: localSelection, selection: $selection))

            if showsPageIndicator {
                pageIndicator
                    .frame(height: StatsChartPagerMetrics.indicatorHeight)
            }
        }
        .onChange(of: pageCount) { _, newCount in
            guard newCount > 0 else {
                selection = 0
                return
            }
            if selection >= newCount {
                selection = newCount - 1
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: StatsChartPlotWidthKey.self, value: geo.size.width)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(
                format: L10n.string("stats.chart.page_a11y"),
                clampedSelection + 1,
                max(pageCount, 1)
            )
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index == clampedLocalSelection
                            ? shellPalette.tintColor(for: colorScheme)
                            : Color.white.opacity(0.28)
                    )
                    .frame(width: index == clampedLocalSelection ? 18 : 8, height: 8)
                    .animation(motionReduced ? nil : MilehoundMotion.snappy, value: clampedLocalSelection)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Syncs the pager's local page to the parent only after the swipe settles (iOS 18+).
private struct StatsChartPagerSettleSync: ViewModifier {
    let localSelection: Int
    @Binding var selection: Int

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, newPhase in
                if newPhase == .idle, selection != localSelection {
                    selection = localSelection
                }
            }
        } else {
            content.onChange(of: localSelection) { _, newValue in
                guard selection != newValue else { return }
                selection = newValue
            }
        }
    }
}

/// Width of the stats chart card, so date labels can scale to one bar on a narrow Duo pane.
struct StatsChartPlotWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 1 { value = next }
    }
}
