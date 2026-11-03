import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class MilehoundRunningHoundIconSnapshotTests: XCTestCase {
    private static let canvas = CGSize(width: 80, height: 56)
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testStillStartHoundSnapshots() {
        withSnapshotTesting(record: .missing) {
            for (name, scheme) in Self.schemes {
                assertSnapshot(
                    of: host(
                        MilehoundRunningHoundIcon(reduceMotion: true),
                        scheme: scheme
                    ),
                    as: .image(precision: 0.98, perceptualPrecision: 0.98, size: Self.canvas),
                    named: name
                )
            }
        }
    }

    private func host(_ view: some View, scheme: ColorScheme) -> UIViewController {
        let root = ZStack {
            AtmosphericBackground(style: .full)
            view
        }
        .environment(\.colorScheme, scheme)
        .environment(\.shellPalette, .sky)
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        controller.view.bounds = CGRect(origin: .zero, size: Self.canvas)
        controller.view.backgroundColor = .clear
        return controller
    }
}
