import CoreLocation
import SwiftUI

struct YearRecapHubCard: View {
    let snapshot: YearRecapSnapshot
    var onPlay: () -> Void
    var onPlayPage: (RecapStoryPage) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesOverlay: Bool {
        snapshot.hasData && !dynamicTypeSize.isAccessibilitySize
    }

    private var pulsePlay: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    private var chapterPages: [RecapStoryPage] {
        RecapStoryPagePolicy.pages(for: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            playSurface
                .glassCard(cornerRadius: StatsCardTokens.radius, contentInset: 0)
            if snapshot.hasData {
                RecapChapterRail(
                    pages: chapterPages,
                    onPlayPage: onPlayPage
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("stats.premium.recap")
        .task(id: routePrewarmID, priority: .utility) {
            await prewarmRouteSnapshot()
        }
    }

    /// Year alone does not change when the empty card is replaced by a real snapshot.
    private var routePrewarmID: String {
        let start = snapshot.topRouteStartLatitude ?? 0
        let end = snapshot.topRouteEndLatitude ?? 0
        return "\(snapshot.year)-\(snapshot.topRouteCount)-\(start)-\(end)"
    }

    private func prewarmRouteSnapshot() async {
        guard
            snapshot.topRouteCount >= 2,
            let startLatitude = snapshot.topRouteStartLatitude,
            let startLongitude = snapshot.topRouteStartLongitude,
            let endLatitude = snapshot.topRouteEndLatitude,
            let endLongitude = snapshot.topRouteEndLongitude
        else { return }
        _ = await FrequentRoutesSnapshotCache.shared.snapshot(
            start: CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude),
            end: CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude),
            count: snapshot.topRouteCount,
            isBusiness: snapshot.businessDistanceMeters > snapshot.otherDistanceMeters
        )
    }

    @ViewBuilder
    private var playSurface: some View {
        if snapshot.hasData {
            Button(action: onPlay) {
                Group {
                    if usesOverlay {
                        overlayPoster
                    } else {
                        stackedContent(allowsIdleMotion: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.milehoundCardPress)
            .glassEntranceGlint(cornerRadius: StatsCardTokens.radius, id: "stats.premium.recap")
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("stats.premium.recap.play")
            .accessibilityLabel(L10n.string("premium.recap.play"))
            .accessibilityValue(DateFormatters.formatDistance(snapshot.distanceMeters))
        } else {
            stackedContent(allowsIdleMotion: false)
        }
    }

    private var overlayPoster: some View {
        ZStack {
            RecapHubTeaserScene(
                height: RecapHubTeaserMetrics.posterHeight,
                allowsIdleMotion: true,
                cornerRadius: StatsCardTokens.radius
            )
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
            VStack(alignment: .leading, spacing: 0) {
                yearChip
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        distanceText
                            .frame(maxWidth: .infinity, alignment: .leading)
                        playChip
                            .padding(.vertical, -6)
                            .layoutPriority(1)
                    }
                    metricsLine
                }
            }
            .statsPosterOverlayPadding()
        }
        .frame(maxWidth: .infinity, minHeight: RecapHubTeaserMetrics.posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: StatsCardTokens.radius, style: .continuous))
    }

    private func stackedContent(allowsIdleMotion: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RecapHubTeaserScene(
                height: snapshot.hasData
                    ? RecapHubTeaserMetrics.stackedHeight
                    : RecapHubTeaserMetrics.emptyHeight,
                allowsIdleMotion: allowsIdleMotion
            )
            yearChip
            if snapshot.hasData {
                distanceText
                metricsLine
                playChip
            } else {
                Text(L10n.string("premium.recap.empty"))
                    .font(.caption)
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
            }
        }
        .padding(StatsCardTokens.contentInset)
    }

    private var yearChip: some View {
        Text(String(format: L10n.string("premium.recap.year_title"), snapshot.year))
            .font(.caption.weight(.semibold))
            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            .statsFrostChip()
    }

    private var distanceText: some View {
        Text(DateFormatters.formatDistance(snapshot.distanceMeters))
            .font(.title.weight(.bold).monospacedDigit())
            .glassAccentForeground()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    private var metricsLine: some View {
        HStack(spacing: 6) {
            Text(String(snapshot.tripCount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(L10n.string("premium.recap.trips"))
            if snapshot.cityCount > 0 {
                Text("·")
                Text("\(snapshot.cityCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(L10n.string("premium.recap.cities"))
            }
        }
        .font(.caption)
        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var playChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: pulsePlay)
            Text(L10n.string("premium.recap.play"))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .milehoundCompactProminentButton()
        .layoutPriority(1)
        .accessibilityHidden(true)
    }
}

private struct RecapChapterRail: View {
    let pages: [RecapStoryPage]
    var onPlayPage: (RecapStoryPage) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RecapChapterRailTokens.spacing) {
                ForEach(pages, id: \.self) { page in
                    RecapChapterCard(
                        page: page,
                        onPlay: { onPlayPage(page) }
                    )
                    .glassCarouselPage()
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.trailing, RecapChapterRailTokens.peek, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("stats.premium.recap.chapters")
    }
}

private struct RecapChapterCard: View {
    let page: RecapStoryPage
    var onPlay: () -> Void

    private var title: String {
        L10n.string(RecapStoryPagePolicy.chapterTitleKey(for: page))
    }

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottom) {
                RecapChapterEmblemScene(page: page)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .statsThemeChip()
                    .padding(.bottom, RecapChapterRailTokens.titleInset)
            }
            .frame(width: RecapChapterRailTokens.cardWidth, height: RecapChapterRailTokens.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: StatsCardTokens.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: StatsCardTokens.radius, style: .continuous))
        }
        .buttonStyle(.milehoundCardPress)
        .accessibilityIdentifier("stats.premium.recap.chapter.\(page.rawValue)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}
