import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class NotificationRowSnapshotTests: XCTestCase {
    private static let rowWidth: CGFloat = 370
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testRowSnapshots() {
        for (fixtureName, row) in Self.rows {
            for (schemeName, scheme) in Self.schemes {
                let size = CGSize(width: Self.rowWidth, height: 76)
                assertSnapshot(
                    of: host(rowCard(row), scheme: scheme, size: size),
                    as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size),
                    named: "\(fixtureName)-\(schemeName)"
                )
            }
        }
    }

    func testEveryRowKindHasTheSameHeight() throws {
        let heights = Self.rows.map { _, row in
            UIHostingController(rootView: rowCard(row))
                .sizeThatFits(in: CGSize(width: Self.rowWidth, height: .greatestFiniteMagnitude))
                .height
        }
        let first = try XCTUnwrap(heights.first)
        for height in heights {
            XCTAssertEqual(height, first, accuracy: 0.5)
        }
    }

    func testPreviewCardSnapshots() {
        let panes: [(String, CGSize)] = [
            ("full", CGSize(width: 400, height: 380)),
            ("short", CGSize(width: 400, height: 250))
        ]
        for (paneName, size) in panes {
            for (schemeName, scheme) in Self.schemes {
                let card = Self.previewCard
                    .padding(16)
                    .frame(width: size.width, height: size.height, alignment: .top)
                assertSnapshot(
                    of: host(card, scheme: scheme, size: size),
                    as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size),
                    named: "preview-\(paneName)-\(schemeName)"
                )
            }
        }
    }

    func testPreviewCardNeverOutgrowsShortPane() {
        let pane = CGSize(width: 368, height: 218)
        let fitted = UIHostingController(rootView: Self.previewCard.frame(width: pane.width))
            .sizeThatFits(in: pane)
        XCTAssertLessThanOrEqual(fitted.height, pane.height + 0.5)
    }

    private func rowCard(_ row: NotificationRowContent) -> some View {
        row
            .glassCard(contentInset: 12)
            .frame(width: Self.rowWidth)
            .environment(\.shellPalette, .sky)
    }

    private func host(_ view: some View, scheme: ColorScheme, size: CGSize) -> UIViewController {
        // Solid plate, not native Liquid Glass or Material. Those shaders recorded on a
        // newer simulator do not match the iOS 26.2 runtime CI uses.
        let root = ZStack {
            AtmosphericBackground(style: .full)
            view
        }
        .environment(\.colorScheme, scheme)
        .environment(\.shellPalette, .sky)
        .environment(\.glassForcesSolidPlate, true)
        .frame(width: size.width, height: size.height)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        return controller
    }

    private static var rows: [(String, NotificationRowContent)] {
        [
            ("started", NotificationRowContent(
                title: "Trip started",
                subtitle: "Sirinyer, Buca, İzmir",
                meta: nil,
                relativeTime: "2d ago",
                systemImage: "play.circle.fill",
                tint: .green,
                isRead: true,
                showsChevron: true
            )),
            ("endedShort", NotificationRowContent(
                title: "Trip ended",
                subtitle: "Opti → Home",
                meta: "3,4 km · 22:22",
                relativeTime: "3h ago",
                systemImage: "flag.checkered",
                tint: .blue,
                isRead: false,
                showsChevron: true
            )),
            ("endedLongRoute", NotificationRowContent(
                title: "Trip ended",
                subtitle: "Sirinyer Mahallesi, Buca, İzmir → Karşıyaka Çarşı, Bostanlı, İzmir",
                meta: "12,8 km · 41:05",
                relativeTime: "2d ago",
                systemImage: "flag.checkered",
                tint: .blue,
                isRead: true,
                showsChevron: true
            ))
        ]
    }

    private static var previewCard: NotificationPreviewCard {
        NotificationPreviewCard(
            title: "Trip started",
            when: "6h ago · 26 Oct 2026 · 14:51 – 15:06",
            systemImage: "play.circle.fill",
            tint: .green,
            route: "Home → Opti",
            message: nil,
            metrics: [
                .init(systemImage: "road.lanes", text: "3,4 km"),
                .init(systemImage: "clock", text: "15:42"),
                .init(systemImage: "speedometer", text: "13 km/h")
            ],
            facts: [
                .init(systemImage: "car", text: "Puma"),
                .init(systemImage: "tag", text: "Personal"),
                .init(systemImage: "speedometer", text: "Max 54 km/h"),
                .init(systemImage: "fuelpump", text: "₺18,40")
            ],
            note: "Stopped for coffee on the way.",
            onOpen: {}
        )
    }
}
