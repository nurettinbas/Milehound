import MapKit
import SwiftUI
import UIKit

struct FrequentRoutesMapLegend: View {
    let aggregates: [FrequentRouteAggregate]
    var selected: FrequentRouteAggregate?
    var bottomInset: CGFloat = 34
    @Binding var isDark: Bool
    var onSelect: (FrequentRouteAggregate) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                Picker("style", selection: $isDark) {
                    Text(L10n.string("premium.routes.map.standard")).tag(false)
                    Text(L10n.string("premium.routes.map.dark")).tag(true)
                }
                .glassSegmentedStyle()
                .frame(maxWidth: 180)
            }
            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selected.startDisplay) → \(selected.endDisplay)")
                        .font(.subheadline.weight(.semibold))
                    Text(String(format: L10n.string("premium.routes.map.meta"), selected.count, DateFormatters.formatDistance(selected.totalDistanceMeters)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selected.lastStartedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if aggregates.isEmpty {
                Text(L10n.string("premium.routes.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("premium.routes.map.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if aggregates.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(aggregates) { route in
                            Button {
                                onSelect(route)
                            } label: {
                                Text("\(route.startDisplay) → \(route.endDisplay)")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glassPlainHit)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20, frozen: true, allowsNative: false)
        .padding(.horizontal, 16)
        .padding(.bottom, max(20, bottomInset))
    }
}

struct FrequentRoutesCardGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct FrequentRoutesExpandOverlay: View {
    @Bindable var model: RecapExpandModel
    var onClose: () -> Void
    var onSwipeClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.milehoundLayout) private var layout
    @Environment(\.recapExpandChromeBlur) private var chromeBlur
    @State private var selected: FrequentRouteAggregate?
    @State private var isDark = false

    var body: some View {
        GeometryReader { proxy in
            let window = windowSafeInsets
            let topInset = max(proxy.safeAreaInsets.top, window.top, 54)
            let bottomInset = max(proxy.safeAreaInsets.bottom, window.bottom, 34)
            ZStack {
                FrequentRoutesMapKitView(
                    aggregates: model.routeAggregates,
                    isDark: isDark || colorScheme == .dark,
                    onSelect: { selected = $0 }
                )
                .transaction { $0.animation = nil }
                .accessibilityIdentifier("stats.premium.routes.map")
                FrequentRoutesMapLegend(
                    aggregates: model.routeAggregates,
                    selected: selected,
                    bottomInset: bottomInset,
                    isDark: $isDark,
                    onSelect: { selected = $0 }
                )
                .frame(
                    maxWidth: layout.layoutClass == .phone ? .infinity : GlassTokens.floatingPanelWidth,
                    maxHeight: .infinity,
                    alignment: layout.mapChrome == .bottomSheet ? .bottom : .leading
                )
                .padding(layout.layoutClass == .phone ? 0 : 16)
                .blur(radius: chromeBlur)
                CardExpandBackSwipeStrip(
                    enabled: true,
                    topClearance: topInset + CardExpandBackSwipe.headerClearance,
                    onClose: onSwipeClose
                )
                GlassToolbarCollapseButton(
                    accessibilityIdentifier: "stats.premium.routes.expanded.close",
                    action: onClose
                )
                .blur(radius: chromeBlur)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: layout.pinsOverlayCloseLeading ? .topLeading : .topTrailing
                )
                .padding(.top, topInset)
                .padding(.horizontal, 12)
            }
            .onGlassShell()
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stats.premium.routes.expanded")
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

struct FrequentRoutesPreviewCard: View {
    let aggregates: [FrequentRouteAggregate]
    var isExpanded: Bool
    var showsTitle: Bool = true
    var showsExpandControl: Bool = true
    var onOpen: () -> Void
    @State private var preview: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                if showsTitle {
                    Text(L10n.string("premium.routes.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                        .padding(.trailing, 44)
                }
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                }
                if let top = FrequentRouteOverlayBudget.habitCorridors(aggregates).first
                    ?? FrequentRouteOverlayBudget.topAggregates(aggregates).first {
                    Text("\(top.startDisplay) → \(top.endDisplay)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(String(format: L10n.string("premium.routes.count"), top.count))
                        .font(.caption)
                        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                } else {
                    Text(L10n.string("premium.routes.empty"))
                        .font(.caption)
                        .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsExpandControl {
                expandControl
            }
        }
        .padding(.vertical, 4)
        .task(id: aggregates.map(\.pairKey).joined()) {
            preview = await FrequentRoutesSnapshotCache.shared.snapshot(for: aggregates)
        }
    }

    private var expandControl: some View {
        Button(action: onOpen) {
            GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(L10n.mapFullscreen)
        .accessibilityIdentifier("stats.premium.routes")
        .allowsHitTesting(!isExpanded)
        .offset(x: StatsCardTokens.expandGlyphOffset.width, y: StatsCardTokens.expandGlyphOffset.height)
    }
}
