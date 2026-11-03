import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class SideColumnChromeSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testSideColumnChromeSnapshots() {
        let canvasLimit = CGSize(width: 280, height: 360)
        for fixture in SideColumnChromeSnapshotFixture.all {
            let canvas = fixture.canvas(max: canvasLimit)
            let root = SideColumnChromeSnapshotHarness(fixture: fixture, canvas: canvas)
                .environment(\.colorScheme, fixture.scheme)
                .environment(\.shellPalette, .sky)
                .frame(width: canvas.width, height: canvas.height)
            let controller = UIHostingController(rootView: root)
            controller.overrideUserInterfaceStyle = fixture.scheme == .dark ? .dark : .light
            controller.view.bounds = CGRect(origin: .zero, size: canvas)
            controller.view.backgroundColor = .clear
            assertSnapshot(
                of: controller,
                as: .image(precision: 0.98, perceptualPrecision: 0.98, size: canvas),
                named: fixture.name
            )
        }
    }
}

private struct SideColumnChromeSnapshotFixture {
    var name: String
    var metrics: SideColumnChromeMetrics
    var symbols: [String]
    var scheme: ColorScheme

    func canvas(max limit: CGSize) -> CGSize {
        _ = limit
        return metrics.windowSize
    }

    static var all: [SideColumnChromeSnapshotFixture] {
        let orientations: [(String, CGSize, UIEdgeInsets)] = [
            ("portrait", CGSize(width: 360, height: 640), UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)),
            ("landscapeLeft", CGSize(width: 640, height: 450), UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)),
            ("landscapeRight", CGSize(width: 640, height: 450), UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 59)),
            ("upsideDown", CGSize(width: 360, height: 640), UIEdgeInsets(top: 21, left: 0, bottom: 59, right: 0))
        ]
        let symbolSets: [(String, [String])] = [
            ("bell", ["bell"]),
            ("bellMerge", ["bell", "arrow.triangle.merge"]),
            ("bellPlus", ["bell", "plus"])
        ]
        let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
        var fixtures: [SideColumnChromeSnapshotFixture] = []
        for orientation in orientations {
            for side in ["leading", "trailing"] {
                for symbols in symbolSets {
                    for scheme in schemes {
                        let bar = tabBar(window: orientation.1, side: side, orientation: orientation.0)
                        let sideColumn = bar.height > bar.width * 1.4
                        let metrics = SideColumnChromeMetrics(
                            windowSize: orientation.1,
                            safeInsets: orientation.2,
                            tabBarFrame: bar,
                            layoutDirection: side == "trailing" ? .rightToLeft : .leftToRight,
                            buttonCount: symbols.1.count,
                            isTransitioning: false,
                            statusClusterMaxY: sideColumn ? 54 : (orientation.2.top > 1 ? orientation.2.top : nil)
                        )
                        fixtures.append(
                            SideColumnChromeSnapshotFixture(
                                name: "\(orientation.0)-\(side)-\(symbols.0)-\(scheme.0)",
                                metrics: metrics,
                                symbols: symbols.1,
                                scheme: scheme.1
                            )
                        )
                    }
                }
            }
        }
        return fixtures
    }

    private static func tabBar(window: CGSize, side: String, orientation: String) -> CGRect {
        let width: CGFloat = 64
        if orientation == "portrait" || orientation == "upsideDown" {
            if side == "leading" {
                return CGRect(x: 50, y: window.height - 70, width: 250, height: 50)
            }
        }
        let height: CGFloat = 180
        let x = side == "leading" ? 12 : window.width - width - 12
        return CGRect(x: x, y: 230, width: width, height: height)
    }
}

private struct SideColumnChromeSnapshotHarness: View {
    var fixture: SideColumnChromeSnapshotFixture
    var canvas: CGSize

    var body: some View {
        let metrics = fixture.metrics
        let placement = SideColumnChromeResolver.resolve(metrics)
        let scale = min(canvas.width / metrics.windowSize.width, canvas.height / metrics.windowSize.height)
        ZStack(alignment: .topLeading) {
            (fixture.scheme == .dark ? Color(white: 0.12) : Color(white: 0.93))
            if let bar = metrics.tabBarFrame {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(fixture.scheme == .dark ? 0.16 : 0.55))
                    .frame(width: bar.width * scale, height: bar.height * scale)
                    .offset(x: bar.minX * scale, y: bar.minY * scale)
            }
            let camera = SideColumnChromeResolver.cameraRegion(
                windowSize: metrics.windowSize,
                safeInsets: metrics.safeInsets,
                column: metrics.tabBarFrame ?? .zero
            )
            if camera.width > 1 {
                Circle()
                    .fill(Color.black)
                    .frame(width: camera.width * scale * 0.72, height: camera.height * scale * 0.72)
                    .offset(x: camera.minX * scale, y: camera.minY * scale)
            }
            chrome(placement, scale: scale)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func chrome(_ placement: SideColumnChromePlacement, scale: CGFloat) -> some View {
        switch placement {
        case .toolbar:
            HStack(spacing: 8 * scale) {
                buttons(scale: scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(8 * scale)
        case .pending:
            EmptyView()
        case .sideColumn(let frame, _):
            VStack(spacing: 0) {
                buttons(scale: scale, circled: false)
            }
            .glassCapsuleChrome(frozen: true)
            .frame(width: frame.width * scale, height: frame.height * scale, alignment: .top)
            .offset(x: frame.minX * scale, y: frame.minY * scale)
        }
    }

    private func buttons(scale: CGFloat, circled: Bool = true) -> some View {
        ForEach(Array(fixture.symbols.enumerated()), id: \.offset) { _, symbol in
            let pointSize: CGFloat? = symbol == "arrow.triangle.merge" ? 15 : nil
            Group {
                if circled {
                    GlassNavCircleIcon(systemName: symbol, frozen: true, pointSize: pointSize)
                } else {
                    GlassToolbarSymbol(systemName: symbol, sampling: .system, pointSize: pointSize)
                }
            }
            .frame(
                width: GlassTokens.toolbarControlCircleSide * scale,
                height: GlassTokens.toolbarControlCircleSide * scale
            )
        }
    }
}
