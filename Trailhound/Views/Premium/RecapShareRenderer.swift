import SwiftUI
import UIKit

struct RecapShareItem {
    let image: UIImage
    let caption: String

    static let empty = RecapShareItem(image: UIImage(), caption: "Trailhound")
}

@MainActor
enum RecapShareRenderer {
    nonisolated static let pixelSize = CGSize(width: 1080, height: 1920)
    nonisolated static let layoutWidth: CGFloat = 390
    nonisolated static var layoutSize: CGSize {
        CGSize(width: layoutWidth, height: layoutWidth * pixelSize.height / pixelSize.width)
    }

    static func caption(for snapshot: YearRecapSnapshot, page: RecapStoryPage) -> String {
        switch page {
        case .intro:
            "\(L10n.string("premium.recap.intro_kicker")) · \(snapshot.year)"
        case .distance:
            DateFormatters.formatDistance(snapshot.distanceMeters)
        case .cities:
            String(format: L10n.string("premium.recap.share.cities"), snapshot.cityCount)
        case .route:
            if let start = snapshot.topRouteStart, let end = snapshot.topRouteEnd {
                "\(start) → \(end)"
            } else {
                L10n.string("premium.recap.route_title")
            }
        case .time:
            if snapshot.longestStreak > 0 {
                String(format: L10n.string("premium.recap.streak"), snapshot.longestStreak)
            } else if snapshot.nightDistanceMeters > 0 {
                String(format: L10n.string("premium.recap.night"), DateFormatters.formatDistance(snapshot.nightDistanceMeters))
            } else if let month = snapshot.busiestMonth {
                String(
                    format: L10n.string("premium.recap.busiest_month"),
                    DateFormatters.formatMonthName(month: month, year: snapshot.year)
                )
            } else {
                String(snapshot.year)
            }
        case .categories:
            if let verdict = snapshot.purposeVerdict {
                RecapPurposePolicy.heroTitle(for: verdict)
            } else {
                L10n.string("premium.recap.purpose_kicker")
            }
        case .cost:
            L10n.string("premium.recap.cost_kicker")
        case .badges:
            L10n.string("premium.recap.badges_title")
        case .closing:
            String(format: L10n.string("premium.recap.closing"), snapshot.year)
        }
    }

    static func item(
        for snapshot: YearRecapSnapshot,
        page: RecapStoryPage,
        palette: ShellPalette,
        scheme: ColorScheme,
        routeImage: UIImage? = nil
    ) -> RecapShareItem {
        RecapShareItem(
            image: image(
                for: snapshot,
                page: page,
                palette: palette,
                scheme: scheme,
                routeImage: routeImage
            ),
            caption: caption(for: snapshot, page: page)
        )
    }

    static func image(
        for snapshot: YearRecapSnapshot,
        page: RecapStoryPage,
        palette: ShellPalette,
        scheme: ColorScheme,
        routeImage: UIImage? = nil
    ) -> UIImage {
        let layout = layoutSize
        let card = RecapShareCardView(
            snapshot: snapshot,
            page: page,
            routeImage: routeImage
        )
        .frame(width: layout.width, height: layout.height)
        .environment(\.shellPalette, palette)
        .environment(\.colorScheme, scheme)
        .environment(\.achievementIdleTime, nil)
        .preferredColorScheme(scheme)
        .trailhoundShareCaptureEnvironment()

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: layout.width, height: layout.height)
        renderer.scale = pixelSize.width / layout.width
        return renderer.uiImage ?? UIImage()
    }
}

private struct RecapShareCardView: View {
    let snapshot: YearRecapSnapshot
    let page: RecapStoryPage
    var routeImage: UIImage?

    var body: some View {
        ZStack(alignment: .top) {
            RecapPageScene(
                page: page,
                isActive: true,
                reduceMotion: true,
                badgeIDs: RecapStoryBadgeIDs.resolved(from: snapshot),
                motion: 0,
                purposeShare: snapshot.purposeVerdict?.share ?? 0,
                estimatedFuelCost: snapshot.estimatedFuelCost,
                paidExpenses: snapshot.paidExpenses,
                pageElapsed: RecapIntroReveal.settledElapsed
            )
            RecapStoryBottomScrim()
            RecapStoryPageForeground(
                snapshot: snapshot,
                page: page,
                displayedDistance: snapshot.distanceMeters,
                routeImage: routeImage,
                motion: 0,
                reduceMotion: true,
                pageElapsed: RecapIntroReveal.settledElapsed
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGlassShell()
            TrailhoundBrandMark(showsWordmark: true, symbolSize: 36)
                .padding(.top, 28)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onGlassShell()
        .clipped()
    }
}
