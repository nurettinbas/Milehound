import CoreLocation
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Trailhound

@MainActor
final class LiveFollowPlannedRouteSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private struct LayoutCase {
        var name: String
        var size: CGSize
        var horizontal: UserInterfaceSizeClass
        var vertical: UserInterfaceSizeClass
        var idiom: UIUserInterfaceIdiom
    }

    /// Every shell the live map runs in: phone, closed Duo, open Duo (upright and book), iPad.
    private let layouts: [LayoutCase] = [
        LayoutCase(name: "phone", size: CGSize(width: 390, height: 844), horizontal: .compact, vertical: .regular, idiom: .phone),
        LayoutCase(name: "phone-landscape", size: CGSize(width: 844, height: 390), horizontal: .compact, vertical: .compact, idiom: .phone),
        LayoutCase(name: "phone-book", size: CGSize(width: 1600, height: 402), horizontal: .regular, vertical: .compact, idiom: .phone),
        LayoutCase(name: "duo-closed-portrait", size: CGSize(width: 402, height: 874), horizontal: .compact, vertical: .regular, idiom: .phone),
        LayoutCase(name: "duo-closed-landscape", size: CGSize(width: 874, height: 402), horizontal: .compact, vertical: .compact, idiom: .phone),
        LayoutCase(name: "duo-open-portrait", size: CGSize(width: 680, height: 1100), horizontal: .regular, vertical: .regular, idiom: .phone),
        LayoutCase(name: "duo-open-book", size: CGSize(width: 1600, height: 1100), horizontal: .regular, vertical: .regular, idiom: .phone),
        LayoutCase(name: "pad-portrait", size: CGSize(width: 820, height: 1180), horizontal: .regular, vertical: .regular, idiom: .pad),
        LayoutCase(name: "pad-landscape", size: CGSize(width: 1180, height: 820), horizontal: .regular, vertical: .regular, idiom: .pad),
    ]

    private let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    private var savedPlaces: [LiveFollowDestinationOption] {
        [
            LiveFollowDestinationOption(
                id: "place.home",
                name: "Home",
                subtitle: "Home",
                systemImage: "house.fill",
                coordinate: CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
            ),
            LiveFollowDestinationOption(
                id: "place.office",
                name: "Route Seed Office",
                subtitle: "Work",
                systemImage: "briefcase.fill",
                coordinate: CLLocationCoordinate2D(latitude: 41.04, longitude: 29.01)
            ),
        ]
    }

    /// Bottom sheet on phones is the full width; the open Duo and iPad get a form-sized card.
    private func sheetCanvas(for layout: TrailhoundLayoutSnapshot, size: CGSize) -> CGSize {
        if LiveFollowDestinationSheet.usesFormSizing(layout) {
            return CGSize(width: 580, height: min(size.height, 720))
        }
        return CGSize(width: min(size.width, 700), height: min(size.height, 640))
    }

    func testDestinationSheetAcrossLayouts() {
        withSnapshotTesting(record: .missing) {
            for layoutCase in layouts {
                let layout = TrailhoundLayoutResolver.snapshot(
                    horizontal: layoutCase.horizontal,
                    vertical: layoutCase.vertical,
                    size: layoutCase.size,
                    idiom: layoutCase.idiom
                )
                let canvas = sheetCanvas(for: layout, size: layoutCase.size)
                for scheme in schemes {
                    for allowsSearch in [true, false] {
                        assertSheet(
                            layout: layout,
                            canvas: canvas,
                            scheme: scheme.1,
                            allowsSearch: allowsSearch,
                            named: "\(layoutCase.name)-\(allowsSearch ? "search" : "locked")-\(scheme.0)"
                        )
                    }
                }
            }
        }
    }

    func testDestinationSheetRightToLeftAndLargeText() {
        let layout = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact, vertical: .regular, size: CGSize(width: 390, height: 844), idiom: .phone
        )
        withSnapshotTesting(record: .missing) {
            for scheme in schemes {
                assertSheet(
                    layout: layout,
                    canvas: CGSize(width: 390, height: 640),
                    scheme: scheme.1,
                    allowsSearch: false,
                    direction: .rightToLeft,
                    named: "phone-rtl-\(scheme.0)"
                )
                assertSheet(
                    layout: layout,
                    canvas: CGSize(width: 390, height: 900),
                    scheme: scheme.1,
                    allowsSearch: true,
                    typeSize: .accessibility3,
                    named: "phone-ax3-\(scheme.0)"
                )
            }
        }
    }

    func testLiveFollowHUDAcrossLayouts() {
        let sample = LiveFollowHUDSample(duration: "9:49", speed: "100 km/h", distance: "19.4 km")
        withSnapshotTesting(record: .missing) {
            for layoutCase in layouts {
                let layout = TrailhoundLayoutResolver.snapshot(
                    horizontal: layoutCase.horizontal,
                    vertical: layoutCase.vertical,
                    size: layoutCase.size,
                    idiom: layoutCase.idiom
                )
                let fillsPane = layout.splitsRecording || layout.pinsRecordingCardToFold
                let landscapeCover = !fillsPane
                    && layout.layoutClass == .phoneLandscape
                    && !layout.isPhoneBook
                let mapWidth = liveMapWidth(layout)
                for scheme in schemes {
                    for paused in [false, true] {
                        let state = paused ? "paused" : "recording"
                        assertHUD(
                            sample: sample,
                            mapWidth: mapWidth,
                            scheme: scheme.1,
                            palette: .sky,
                            paused: paused,
                            tight: landscapeCover,
                            named: "\(layoutCase.name)-\(scheme.0)-\(state)"
                        )
                    }
                }
            }
            let phone = TrailhoundLayoutResolver.snapshot(
                horizontal: .compact,
                vertical: .regular,
                size: CGSize(width: 390, height: 844),
                idiom: .phone
            )
            assertHUD(
                sample: sample,
                mapWidth: phone.size.width,
                scheme: .light,
                palette: .rose,
                paused: false,
                tight: false,
                named: "phone-rose-light-recording"
            )
        }
    }

    func testRouteChipStates() {
        let states: [(String, RecordingRouteChip.Content)] = [
            ("set", .setDestination),
            ("loading", .loading),
            ("offline", .offline),
            ("failed", .failed),
            ("estimate", .estimate(distance: "12.4 km", arrival: "14:35")),
        ]
        let variants: [(String, ColorScheme, LayoutDirection, DynamicTypeSize, CGSize)] = [
            ("light", .light, .leftToRight, .large, CGSize(width: 320, height: 300)),
            ("dark", .dark, .leftToRight, .large, CGSize(width: 320, height: 300)),
            ("rtl-light", .light, .rightToLeft, .large, CGSize(width: 320, height: 300)),
            ("ax3-dark", .dark, .leftToRight, .accessibility3, CGSize(width: 390, height: 560)),
        ]
        withSnapshotTesting(record: .missing) {
            for variant in variants {
                let root = ZStack {
                    LiveFollowChipBackdrop(scheme: variant.1)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(states, id: \.0) { state in
                            RecordingRouteChip(content: state.1, action: {})
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .environment(\.colorScheme, variant.1)
                .environment(\.layoutDirection, variant.2)
                .environment(\.dynamicTypeSize, variant.3)
                .environment(\.shellPalette, .sky)
                .frame(width: variant.4.width, height: variant.4.height)
                assertHosted(root, size: variant.4, scheme: variant.1, named: "chip-\(variant.0)")
            }
        }
    }

    func testMissedTurnNotices() {
        withSnapshotTesting(record: .missing) {
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let root = ZStack {
                    LiveFollowChipBackdrop(scheme: scheme)
                    LiveFollowRouteNotices(missedTurn: true, isRerouting: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .environment(\.colorScheme, scheme)
                .environment(\.shellPalette, .sky)
                .frame(width: 280, height: 120)
                assertHosted(
                    root,
                    size: CGSize(width: 280, height: 120),
                    scheme: scheme,
                    named: "notices-\(scheme == .dark ? "dark" : "light")"
                )
                let maneuver = ZStack {
                    LiveFollowChipBackdrop(scheme: scheme)
                    LiveFollowRouteNotices(
                        missedTurn: false,
                        isRerouting: false,
                        maneuver: UpcomingManeuver(distanceMeters: 400, instruction: "Turn left")
                    )
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .environment(\.colorScheme, scheme)
                .environment(\.shellPalette, .sky)
                .frame(width: 280, height: 120)
                assertHosted(
                    maneuver,
                    size: CGSize(width: 280, height: 120),
                    scheme: scheme,
                    named: "maneuver-\(scheme == .dark ? "dark" : "light")"
                )
            }
        }
    }

    /// Cover and the upright fold use the window. A split map uses half the window.
    private func liveMapWidth(_ layout: TrailhoundLayoutSnapshot) -> CGFloat {
        let fillsPane = layout.splitsRecording || layout.pinsRecordingCardToFold
        if !fillsPane || layout.pinsRecordingCardToFold {
            return layout.size.width
        }
        let gutter: CGFloat = 24
        return max(280, (layout.size.width - gutter) / 2)
    }

    private func assertHUD(
        sample: LiveFollowHUDSample,
        mapWidth: CGFloat,
        scheme: ColorScheme,
        palette: ShellPalette,
        paused: Bool,
        tight: Bool,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let canvas = CGSize(width: mapWidth, height: 520)
        let root = ZStack(alignment: .bottomLeading) {
            Color(white: scheme == .dark ? 0.15 : 0.78)
            LiveFollowHUD(
                tight: tight,
                isPaused: paused,
                uses3D: false,
                isFollowing: true,
                stats: sample,
                onPause: {},
                onStop: {},
                onSelectDimension: { _ in },
                onOverview: {},
                onRecenter: {}
            ) {
                RecordingRouteChip(
                    content: .estimate(distance: "12.4 km", arrival: "19:36"),
                    action: {},
                    wide: true
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .environment(\.shellPalette, palette)
        .environment(\.colorScheme, scheme)
        .frame(width: canvas.width, height: canvas.height)
        assertHosted(root, size: canvas, scheme: scheme, named: name, file: file, testName: testName, line: line)
    }

    private func assertSheet(
        layout: TrailhoundLayoutSnapshot,
        canvas: CGSize,
        scheme: ColorScheme,
        allowsSearch: Bool,
        direction: LayoutDirection = .leftToRight,
        typeSize: DynamicTypeSize = .large,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = ZStack {
            AtmosphericBackground(style: .full)
                .ignoresSafeArea()
            LiveFollowDestinationSheetContent(
                savedPlaces: savedPlaces,
                currentDestinationName: "Route Seed Office",
                allowsSearch: allowsSearch,
                query: .constant(""),
                results: [],
                isSearching: false,
                onPick: { _ in },
                onClear: {},
                onDismiss: {}
            )
        }
        .onGlassShell()
        .environment(\.trailhoundLayout, layout)
        .environment(\.colorScheme, scheme)
        .environment(\.layoutDirection, direction)
        .environment(\.dynamicTypeSize, typeSize)
        .environment(\.shellPalette, .sky)
        .frame(width: canvas.width, height: canvas.height)
        assertHosted(root, size: canvas, scheme: scheme, named: name, file: file, testName: testName, line: line)
    }

    private func assertHosted(
        _ root: some View,
        size: CGSize,
        scheme: ColorScheme,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        // Solid plate, not native Liquid Glass: those shaders differ across simulator runtimes.
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

/// Flat stand-in for map tiles so chip contrast is checked on a light and a dark map.
private struct LiveFollowChipBackdrop: View {
    var scheme: ColorScheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(white: 0.16), Color(red: 0.12, green: 0.16, blue: 0.2)]
                : [Color(red: 0.93, green: 0.92, blue: 0.88), Color(red: 0.82, green: 0.9, blue: 0.84)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
