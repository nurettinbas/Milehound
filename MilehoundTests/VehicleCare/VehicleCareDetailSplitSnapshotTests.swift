import SnapshotTesting
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class VehicleCareDetailSplitSnapshotTests: XCTestCase {
    func testVehicleDetailPadColumns() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let vehicleID = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
        let vehicle = VehicleProfile(
            id: vehicleID,
            name: "Trail",
            consumption: 7.5,
            isDefault: true,
            photoFileName: nil,
            currentOdometerKm: 12_000,
            odometerAnchorKm: 12_000,
            odometerAnchorAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        container.mainContext.insert(vehicle)
        try container.mainContext.save()

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
                    let root = NavigationStack {
                        VehicleDetailView(vehicleID: vehicleID)
                    }
                    .modelContainer(container)
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
                        as: .shellImage(size: size.1),
                        named: "\(size.0)-\(scheme.0)"
                    )
                }
            }
        }
    }
}
