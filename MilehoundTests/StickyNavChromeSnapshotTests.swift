import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class StickyNavChromeSnapshotTests: XCTestCase {
    private static let canvas = CGSize(width: 390, height: 160)
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testStickyBarSnapshots() {
        withSnapshotTesting(record: .missing) {
            for (name, scheme) in Self.schemes {
                assertSnapshot(
                    of: host(
                        GlassCollapsingCard(title: "Daily trends") {
                            Text("42 km")
                                .font(.title3.weight(.bold))
                                .glassPrimaryInk()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        },
                        scheme: scheme
                    ),
                    as: .image(precision: 0.98, perceptualPrecision: 0.98, size: Self.canvas),
                    named: name
                )
            }
        }
    }

    /// Forecast hub is a full-bleed poster. The title must sit inside the plate.
    func testFullBleedCollapsingTitleClearsTheCorner() {
        let canvas = CGSize(width: 320, height: 160)
        withSnapshotTesting(record: .missing) {
            for (name, scheme) in Self.schemes {
                assertSnapshot(
                    of: host(
                        GlassCollapsingCard(
                            title: "This month’s forecast",
                            contentInset: 0,
                            trailing: {
                                GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                            }
                        ) {
                            Color.clear.frame(height: 72)
                        },
                        scheme: scheme,
                        canvas: canvas
                    ),
                    as: .image(precision: 0.98, perceptualPrecision: 0.98, size: canvas),
                    named: name
                )
            }
        }
    }

    private func host(
        _ view: some View,
        scheme: ColorScheme,
        canvas: CGSize = StickyNavChromeSnapshotTests.canvas
    ) -> UIViewController {
        // Solid plate, not native Liquid Glass or Material. Those shaders recorded on a
        // newer simulator do not match the iOS 26.5 runtime CI uses.
        let root = ZStack {
            AtmosphericBackground(style: .full)
            ShellPalette.sky.tintColor(for: scheme).opacity(scheme == .light ? 0.55 : 0)
            view
                .padding(.horizontal, GlassTokens.panelHorizontalInset)
                .glassCollapsingScroll()
        }
        .environment(\.colorScheme, scheme)
        .environment(\.shellPalette, .sky)
        .environment(\.glassForcesSolidPlate, true)
        .frame(width: canvas.width, height: canvas.height)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        controller.view.bounds = CGRect(origin: .zero, size: canvas)
        controller.view.backgroundColor = .clear
        return controller
    }
}
