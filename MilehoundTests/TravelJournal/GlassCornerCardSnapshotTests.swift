import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class GlassCornerCardSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testCornerCardCompactAndExpanded() {
        let compact = CGSize(width: 390, height: 220)
        let expanded = CGSize(width: 390, height: 320)
        withSnapshotTesting(record: .missing) {
            assertCard(expanded: false, size: compact, scheme: .light, named: "compact-light")
            assertCard(expanded: false, size: compact, scheme: .dark, named: "compact-dark")
            assertCard(expanded: true, size: expanded, scheme: .light, named: "expanded-light")
            assertCard(expanded: true, size: expanded, scheme: .dark, named: "expanded-dark")
            assertCard(
                expanded: false,
                size: compact,
                scheme: .light,
                anchorsTrailing: false,
                direction: .rightToLeft,
                named: "compact-rtl"
            )
            assertCard(
                expanded: true,
                size: expanded,
                scheme: .dark,
                typeSize: .accessibility3,
                named: "expanded-ax3"
            )
        }
    }

    private func assertCard(
        expanded: Bool,
        size: CGSize,
        scheme: ColorScheme,
        anchorsTrailing: Bool = true,
        direction: LayoutDirection = .leftToRight,
        typeSize: DynamicTypeSize = .large,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let card = GlassCornerCard(anchorsTrailing: anchorsTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cover Seed")
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                Text("14 Nov 2023")
                    .font(.caption2)
                    .glassSecondaryInk()
                HStack(spacing: 8) {
                    Text("1 trip")
                    Text("12.4 km")
                }
                .font(.caption2.weight(.semibold))
                .glassPrimaryInk()
                if expanded {
                    Text("Home to Office")
                        .font(.subheadline.weight(.semibold))
                        .glassPrimaryInk()
                    Text("Seaside")
                        .font(.caption)
                        .glassSecondaryInk()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260, height: expanded ? 200 : 108, alignment: .topLeading)

        let root = ZStack(alignment: anchorsTrailing ? .bottomTrailing : .bottomLeading) {
            Color(white: scheme == .dark ? 0.12 : 0.82)
            card
                .padding(12)
        }
        .environment(\.colorScheme, scheme)
        .environment(\.layoutDirection, direction)
        .environment(\.dynamicTypeSize, typeSize)
        .environment(\.shellPalette, .sky)
        .frame(width: size.width, height: size.height)

        let controller = UIHostingController(rootView: root.environment(\.glassForcesSolidPlate, true))
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = scheme == .dark ? .black : .white
        assertSnapshot(
            of: controller,
            as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }
}
