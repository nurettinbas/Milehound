import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class GlassShowcaseEmptyStateSnapshotTests: XCTestCase {
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    /// One fixture per pane class: phone list, closed cover beside the recording card,
    /// phone book pane, iPad pane, and a medium-height list.
    func testShowcaseAcrossPanes() {
        for (fixtureName, size, showcase) in Self.fixtures {
            for (schemeName, scheme) in Self.schemes {
                assertSnapshot(
                    of: host(showcase(size), scheme: scheme, size: size),
                    as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size),
                    named: "\(fixtureName)-\(schemeName)"
                )
            }
        }
    }

    func testAccessibilityTextStacksAndScrolls() {
        let size = CGSize(width: 390, height: 760)
        let view = Self.firstRun(size)
            .environment(\.dynamicTypeSize, .accessibility2)
        assertSnapshot(
            of: host(view, scheme: .light, size: size),
            as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size),
            named: "phone-firstRun-accessibility2-light"
        )
    }

    func testRightToLeftMirrorsTheSteps() {
        let size = CGSize(width: 390, height: 620)
        let view = Self.firstRun(size)
            .environment(\.layoutDirection, .rightToLeft)
        assertSnapshot(
            of: host(view, scheme: .light, size: size),
            as: .image(precision: 0.98, perceptualPrecision: 0.98, size: size),
            named: "phone-firstRun-rtl-light"
        )
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

    private static var fixtures: [(String, CGSize, (CGSize) -> AnyView)] {
        [
            ("phone-firstRun", CGSize(width: 390, height: 620), { AnyView(firstRun($0)) }),
            ("closedCover-recording", CGSize(width: 330, height: 230), { size in
                AnyView(GlassShowcaseEmptyState(
                    emblem: .hound,
                    title: "Your first trip is on the road",
                    message: "When you stop, it appears here with its route, distance and time.",
                    available: size
                ))
            }),
            ("phoneBook-travels", CGSize(width: 560, height: 250), { size in
                AnyView(GlassShowcaseEmptyState(
                    emblem: .symbol("suitcase.rolling.fill"),
                    title: "Create your first travel",
                    message: "Group trips under one map when you go away.",
                    highlights: [
                        GlassShowcaseHighlight(systemImage: "map.fill", title: "One map"),
                        GlassShowcaseHighlight(systemImage: "sum", title: "Trip totals"),
                        GlassShowcaseHighlight(systemImage: "sparkles", title: "Smart suggestions")
                    ],
                    available: size
                ) {
                    Button {} label: {
                        Text("Create travel")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .milehoundProminentButton()
                })
            }),
            ("pad-stats", CGSize(width: 700, height: 760), { size in
                AnyView(GlassShowcaseEmptyState(
                    emblem: .symbol("chart.bar.xaxis"),
                    title: "Stats arrive with your first drive",
                    message: "Distance, time, speed and fuel estimates build up as you drive.",
                    highlights: [
                        GlassShowcaseHighlight(systemImage: "calendar", title: "Weekly totals"),
                        GlassShowcaseHighlight(systemImage: "speedometer", title: "Speed & time"),
                        GlassShowcaseHighlight(systemImage: "fuelpump.fill", title: "Fuel estimate")
                    ],
                    available: size
                ) {
                    Button {} label: {
                        Label("Go to Trips", systemImage: "car.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .milehoundGlassButton()
                })
            }),
            ("condensed-vehicle", CGSize(width: 360, height: 360), { size in
                AnyView(PairingEmptyStateFixture(available: size))
            })
        ]
    }

    private static func firstRun(_ size: CGSize) -> some View {
        GlassShowcaseEmptyState(
            emblem: .hound,
            title: "Your first drive starts here",
            message: "Milehound records the route, distance and time for you. Every drive lands here.",
            highlights: [
                GlassShowcaseHighlight(systemImage: "play.fill", title: "Tap Start"),
                GlassShowcaseHighlight(systemImage: "steeringwheel", title: "Drive"),
                GlassShowcaseHighlight(systemImage: "flag.checkered", title: "Review the trip")
            ],
            highlightsAreSteps: true,
            available: size
        ) {
            Button {} label: {
                Label("Record automatically in the car", systemImage: "bolt.car")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .milehoundGlassButton()
        }
    }
}

/// Fixed English copy so the baseline does not follow the simulator language.
private struct PairingEmptyStateFixture: View {
    let available: CGSize

    var body: some View {
        GlassShowcaseEmptyState(
            emblem: .symbol("car.side.fill"),
            title: "Define your vehicle",
            message: "Get in your car, open the app, and tap pair.",
            highlights: [
                GlassShowcaseHighlight(systemImage: "bolt.car", title: "Auto recording"),
                GlassShowcaseHighlight(systemImage: "wrench.and.screwdriver.fill", title: "Care reminders"),
                GlassShowcaseHighlight(systemImage: "creditcard.fill", title: "Costs")
            ],
            available: available
        ) {
            Button {} label: {
                Label("Add vehicle", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .milehoundProminentButton()
        }
    }
}
