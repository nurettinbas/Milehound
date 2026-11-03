import SwiftUI
import UIKit

struct StatsForecastCard: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var isExpanded: Bool = false
    var showsTitle: Bool = true
    var showsExpandControl: Bool = true
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsTrend = false

    private var usesOverlay: Bool {
        forecast.hasData && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                Group {
                    if usesOverlay {
                        overlayPoster
                    } else {
                        stackedContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.milehoundCardPress)
            .allowsHitTesting(!isExpanded)
            if showsExpandControl {
                Button(action: onOpen) {
                    GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityHidden(true)
                .allowsHitTesting(!isExpanded)
                .padding(.top, StatsCardTokens.expandGlyphPosterInsets.top)
                .padding(.trailing, StatsCardTokens.expandGlyphPosterInsets.trailing)
            }
        }
        .glassEntranceGlint(
            cornerRadius: StatsCardTokens.radius,
            id: "stats.forecast.ready",
            isEnabled: forecast.hasData
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stats.premium.forecast")
        .accessibilityLabel(L10n.string("premium.forecast.title"))
        .accessibilityValue(accessibilityValue)
        .onAppear(perform: revealTrend)
        .onChange(of: forecast.trendRatio) { _, _ in
            revealTrend()
        }
    }

    private var overlayPoster: some View {
        StatsForecastHeroPoster(
            forecast: forecast,
            currencyCode: currencyCode,
            height: StatsCardTokens.posterHeight,
            reservesExpandSlot: showsExpandControl,
            showsTitle: showsTitle,
            showsTrend: showsTrend
        )
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if forecast.hasData, !forecast.monthlyTotals.isEmpty {
                StatsForecastSparklineScene(
                    months: forecast.monthlyTotals,
                    currentMonth: forecast.monthStart,
                    height: StatsCardTokens.posterStackedArtworkHeight,
                    cornerRadius: StatsCardTokens.nestedRadius
                )
            }
            if showsTitle {
                StatsForecastTitleChip()
            }
            StatsForecastHeroCopy(
                forecast: forecast,
                currencyCode: currencyCode,
                showsTrend: showsTrend
            )
            if !forecast.hasData {
                Text(L10n.string("premium.forecast.subtitle"))
                    .font(.caption)
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
            }
        }
        .padding(StatsCardTokens.contentInset)
    }

    private var accessibilityValue: String {
        var parts = [FuelCostCalculator.formatCost(forecast.projectedTotal, currencyCode: currencyCode)]
        if forecast.projectedFuel > 0 {
            parts.append(
                "\(L10n.string("premium.forecast.row.drive")) \(FuelCostCalculator.formatCost(forecast.projectedFuel, currencyCode: currencyCode))"
            )
        }
        if forecast.installmentsDue > 0 {
            parts.append(
                "\(L10n.string("premium.forecast.row.installments")) \(FuelCostCalculator.formatCost(forecast.installmentsDue, currencyCode: currencyCode))"
            )
        }
        if let ratio = forecast.trendRatio {
            parts.append(StatsForecastCopy.trend(ratio))
        }
        parts.append(StatsForecastCopy.confidence(forecast.confidence))
        return parts.joined(separator: ", ")
    }

    private var playsMotion: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    private func revealTrend() {
        guard forecast.trendRatio != nil else {
            showsTrend = false
            return
        }
        guard !showsTrend else { return }
        guard playsMotion else {
            showsTrend = true
            return
        }
        withAnimation(MilehoundMotion.pinPop.delay(0.08)) {
            showsTrend = true
        }
    }
}

enum StatsForecastCopy {
    static func confidence(_ confidence: MonthCostForecastConfidence) -> String {
        switch confidence {
        case .low: L10n.string("premium.forecast.confidence.low")
        case .medium: L10n.string("premium.forecast.confidence.medium")
        case .high: L10n.string("premium.forecast.confidence.high")
        }
    }

    static func trend(_ ratio: Double) -> String {
        let percent = Int((abs(ratio) * 100).rounded())
        let format = ratio >= 0
            ? L10n.string("premium.forecast.trend.up")
            : L10n.string("premium.forecast.trend.down")
        return String(format: format, percent)
    }
}

struct StatsForecastTitleChip: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(L10n.string("premium.forecast.title"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: false)
            .statsFrostChip()
    }
}

struct StatsForecastHeroCopy: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var showsTrend: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FuelCostCalculator.formatCost(forecast.projectedTotal, currencyCode: currencyCode))
                .font(.title.weight(.bold).monospacedDigit())
                .glassAccentForeground()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .numericTextAnimation(value: forecast.projectedTotal)
            if forecast.hasData {
                compositionLines
                metricsLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var compositionLines: some View {
        if forecast.projectedFuel > 0 {
            compositionItem(
                L10n.string("premium.forecast.row.drive"),
                forecast.projectedFuel
            )
        }
        if forecast.installmentsDue > 0 {
            compositionItem(
                L10n.string("premium.forecast.row.installments"),
                forecast.installmentsDue
            )
        }
    }

    private func compositionItem(_ title: String, _ amount: Double) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(FuelCostCalculator.formatCost(amount, currencyCode: currencyCode))
                .font(.caption.weight(.semibold).monospacedDigit())
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
        .multilineTextAlignment(.leading)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metricsLine: some View {
        HStack(spacing: 6) {
            if let ratio = forecast.trendRatio, showsTrend {
                Image(systemName: ratio >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trendInk)
                Text(StatsForecastCopy.trend(ratio))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trendInk)
                    .transition(reduceMotion ? .opacity : MilehoundMotion.softScaleInTransition)
                Text("·")
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
            }
            Text(StatsForecastCopy.confidence(forecast.confidence))
                .font(.caption.weight(.semibold))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trendInk: Color {
        StatsChartTheme.forecastSparklineStroke(scheme: colorScheme, palette: shellPalette)
    }
}

struct StatsForecastSparklineScene: View {
    let months: [VehicleMonthlyCost]
    let currentMonth: Date
    var height: CGFloat?
    var cornerRadius: CGFloat = StatsCardTokens.radius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: height == nil ? .infinity : nil)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let stroke = StatsChartTheme.forecastSparklineStroke(
            scheme: colorScheme,
            palette: shellPalette
        )
        let plot = StatsForecastSparklineLayout.plot(
            months: months,
            in: size,
            currentMonth: currentMonth
        )
        guard !plot.points.isEmpty else { return }

        let area = StatsForecastSparklineLayout.area(through: plot.points, height: size.height)
        let line = StatsForecastSparklineLayout.line(through: plot.points)
        let peakY = plot.points.map(\.y).min() ?? 0
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [
                    stroke.opacity(StatsChartTheme.forecastSparklineAreaTopOpacity),
                    stroke.opacity(StatsChartTheme.forecastSparklineAreaBottomOpacity)
                ]),
                startPoint: CGPoint(x: size.width / 2, y: peakY),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
        context.stroke(
            line,
            with: .color(stroke.opacity(0.22)),
            style: StrokeStyle(
                lineWidth: StatsChartTheme.forecastSparklineGlowWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        context.stroke(
            line,
            with: .color(stroke.opacity(0.45)),
            style: StrokeStyle(
                lineWidth: StatsChartTheme.forecastSparklineMidGlowWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        context.stroke(
            line,
            with: .color(stroke),
            style: StrokeStyle(
                lineWidth: StatsChartTheme.forecastSparklineStrokeWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        context.stroke(
            line,
            with: .color(Color.white.opacity(0.88)),
            style: StrokeStyle(
                lineWidth: StatsChartTheme.forecastSparklineHighlightWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )

        if let index = plot.currentIndex {
            let point = plot.points[index]
            let halo = StatsChartTheme.forecastSparklineHaloRadius
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - halo,
                    y: point.y - halo,
                    width: halo * 2,
                    height: halo * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [stroke.opacity(0.55), .clear]),
                    center: point,
                    startRadius: 2,
                    endRadius: halo
                )
            )
            let orb = StatsChartTheme.forecastSparklineOrbRadius
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - orb,
                    y: point.y - orb,
                    width: orb * 2,
                    height: orb * 2
                )),
                with: .color(Color.white)
            )
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: point.x - orb,
                    y: point.y - orb,
                    width: orb * 2,
                    height: orb * 2
                )),
                with: .color(stroke),
                lineWidth: 1.5
            )
        }
    }
}

struct StatsForecastHeroPoster: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var height: CGFloat
    var reservesExpandSlot: Bool
    var showsTitle: Bool = true
    var showsTrend: Bool
    var cornerRadius: CGFloat = StatsCardTokens.radius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        ZStack(alignment: .topLeading) {
            StatsForecastSparklineScene(
                months: forecast.monthlyTotals,
                currentMonth: forecast.monthStart,
                cornerRadius: cornerRadius
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(
                colors: [
                    shellPalette.atmosphere(for: colorScheme).bottom.color.opacity(0.92),
                    shellPalette.atmosphere(for: colorScheme).bottom.color.opacity(0)
                ],
                startPoint: .bottom,
                endPoint: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                if showsTitle {
                    HStack(spacing: 0) {
                        StatsForecastTitleChip()
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, reservesExpandSlot ? 44 : 0)
                }
                Spacer(minLength: 0)
                StatsForecastHeroCopy(
                    forecast: forecast,
                    currencyCode: currencyCode,
                    showsTrend: showsTrend
                )
            }
            .statsPosterOverlayPadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct StatsForecastCardGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct StatsForecastExpandOverlay: View {
    @Bindable var model: RecapExpandModel
    var onClose: () -> Void
    var onSwipeClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let window = windowSafeInsets
            let topInset = max(proxy.safeAreaInsets.top, window.top, 54)
            let bottomInset = max(proxy.safeAreaInsets.bottom, window.bottom, 34)
            StatsForecastDetailSheet(
                forecast: model.forecast,
                currencyCode: model.currencyCode,
                onClose: onClose,
                topInset: topInset,
                bottomInset: bottomInset
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                AtmosphericBackground()
                    .allowsHitTesting(false)
            }
            .glassCard(cornerRadius: 0, contentInset: 0, frozen: true, allowsNative: false)
            .overlay {
                CardExpandBackSwipeStrip(
                    enabled: true,
                    topClearance: topInset + CardExpandBackSwipe.headerClearance,
                    onClose: onSwipeClose
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stats.premium.forecast.expanded")
        .accessibilityAction(.escape) { onClose() }
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }
}

struct StatsForecastDetailSheet: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var onClose: () -> Void
    var topInset: CGFloat = 54
    var bottomInset: CGFloat = 34

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.milehoundLayout) private var layout

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if layout.pinsOverlayCloseLeading {
                    forecastCloseButton
                }
                Text(L10n.string("premium.forecast.detail.title"))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !layout.pinsOverlayCloseLeading {
                    forecastCloseButton
                }
            }
            .padding(.leading, layout.pinsOverlayCloseLeading ? 12 : 16)
            .padding(.trailing, layout.pinsOverlayCloseLeading ? 16 : 12)
            .padding(.top, topInset)
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatsForecastHeroPoster(
                        forecast: forecast,
                        currencyCode: currencyCode,
                        height: StatsCardTokens.posterExpandedHeight,
                        reservesExpandSlot: false,
                        showsTrend: true,
                        cornerRadius: StatsCardTokens.nestedRadius
                    )
                    if forecast.hasComposition {
                        compositionPanel
                    }
                    breakdownPanel
                }
                .padding(16)
                .padding(.bottom, bottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGlassShell()
    }

    private var forecastCloseButton: some View {
        GlassToolbarCollapseButton(
            accessibilityIdentifier: "stats.premium.forecast.expanded.close",
            action: onClose
        )
    }

    private var compositionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSegmentBar(segments: ForecastCompositionBlock.segments(for: forecast))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(legendRows, id: \.id) { row in
                    HStack(spacing: 8) {
                        StatsSegmentSwatch(index: row.index)
                        Text(ForecastCompositionBlock.title(for: row.id))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .statsNestedPanel()
    }

    private var legendRows: [(id: String, index: Int)] {
        ForecastCompositionBlock.segments(for: forecast).compactMap { segment in
            segment.share > 0 ? (id: segment.id, index: segment.stop) : nil
        }
    }

    private var breakdownPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow(L10n.string("premium.forecast.row.drive"), forecast.projectedFuel)
            detailRow(L10n.string("premium.forecast.row.installments"), forecast.installmentsDue)
            detailRow(L10n.string("premium.forecast.row.other"), forecast.otherExpenses)
            detailRow(L10n.string("premium.forecast.row.logged_fuel"), forecast.loggedFuel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ title: String, _ amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Text(amount > 0 ? FuelCostCalculator.formatCost(amount, currencyCode: currencyCode) : "—")
                .font(.body.weight(.semibold).monospacedDigit())
                .glassAccentForeground()
                .opacity(amount > 0 ? 1 : 0.55)
                .fixedSize(horizontal: true, vertical: false)
        }
        .statsNestedPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            amount > 0 ? FuelCostCalculator.formatCost(amount, currencyCode: currencyCode) : "—"
        )
    }
}

enum ForecastCompositionBlock {
    static func segments(for forecast: MonthCostForecast) -> [StatsSegment] {
        let shares = forecast.compositionShares
        return [
            StatsSegment(id: "drive", share: shares.drive, stop: 0),
            StatsSegment(id: "installments", share: shares.installments, stop: 1),
            StatsSegment(id: "other", share: shares.other, stop: 2)
        ]
    }

    static func title(for segmentID: String) -> String {
        switch segmentID {
        case "drive": L10n.string("premium.forecast.row.drive")
        case "installments": L10n.string("premium.forecast.row.installments")
        case "other": L10n.string("premium.forecast.row.other")
        default: segmentID
        }
    }
}
