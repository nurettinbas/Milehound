import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

/// Column arrangement for Recap on iPad. Placeholder cards stand in for the live
/// hubs so the snapshot does not read the recap cache or open MapKit.
@MainActor
final class YearRecapLayoutSnapshotTests: XCTestCase {
    func testRecapPadColumns() {
        let sizes: [(String, CGSize)] = [
            ("pad-landscape", CGSize(width: 1180, height: 820)),
            ("pad-portrait", CGSize(width: 820, height: 1180)),
        ]
        let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
        withSnapshotTesting(record: .missing) {
            for size in sizes {
                let layout = MilehoundLayoutResolver.snapshot(
                    horizontal: .regular,
                    vertical: .regular,
                    size: size.1,
                    idiom: .pad
                )
                for scheme in schemes {
                    let root = YearRecapLayoutSnapshotPage()
                        .environment(\.milehoundLayout, layout)
                        .environment(\.colorScheme, scheme.1)
                        .environment(\.dynamicTypeSize, .large)
                        .environment(\.locale, Locale(identifier: "en_US"))
                        .environment(\.shellPalette, .sky)
                        .frame(width: size.1.width, height: size.1.height)
                    let controller = UIHostingController(rootView: root)
                    controller.overrideUserInterfaceStyle = scheme.1 == .dark ? .dark : .light
                    controller.view.bounds = CGRect(origin: .zero, size: size.1)
                    controller.view.backgroundColor = scheme.1 == .dark ? .black : .white
                    assertSnapshot(
                        of: controller,
                        as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size.1),
                        named: "\(size.0)-\(scheme.0)"
                    )
                }
            }
        }
    }
}

private struct YearRecapLayoutSnapshotPage: View {
    @Environment(\.milehoundLayout) private var layout

    var body: some View {
        Group {
            if layout.usesWidePanes {
                MilehoundHingeCardStack {
                    hub("Year in review", identifier: "recap.section.awards")
                    hub("Badges", identifier: "recap.section.badges")
                    routesPlaceholder
                    hub("This month's forecast", identifier: "recap.section.forecast")
                    hub("Recap", identifier: "recap.section.recap")
                }
                .padding(16)
            } else if layout.packsPortraitRecapHalves {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            hub("Year in review", identifier: "recap.section.awards")
                            routesPlaceholder
                        }
                        VStack(spacing: 12) {
                            hub("Badges", identifier: "recap.section.badges")
                            hub("This month's forecast", identifier: "recap.section.forecast")
                        }
                    }
                    hub("Recap", identifier: "recap.section.recap")
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    hub("Year in review", identifier: "recap.section.awards")
                    hub("Badges", identifier: "recap.section.badges")
                    routesPlaceholder
                    hub("This month's forecast", identifier: "recap.section.forecast")
                    hub("Recap", identifier: "recap.section.recap")
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AtmosphericBackground())
    }

    private func hub(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .glassCard(
                cornerRadius: StatsCardTokens.radius,
                contentInset: StatsCardTokens.contentInset,
                frozen: true,
                allowsNative: false
            )
            .accessibilityIdentifier(identifier)
    }

    /// Static plate. The live Recap card draws a MapKit snapshot; this does not.
    private var routesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frequent routes")
                .font(.headline)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary)
                .frame(height: 88)
            Text("No frequent routes yet")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(
            cornerRadius: StatsCardTokens.radius,
            contentInset: StatsCardTokens.contentInset,
            frozen: true,
            allowsNative: false
        )
        .accessibilityIdentifier("recap.section.routes")
    }
}
