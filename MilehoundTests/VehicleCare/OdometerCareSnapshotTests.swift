import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class OdometerCareSnapshotTests: XCTestCase {
    func testOdometerCareSurfaces() {
        let sizes: [(String, CGSize, DynamicTypeSize)] = [
            ("portrait", CGSize(width: 390, height: 420), .large),
            ("landscape", CGSize(width: 844, height: 320), .large),
            ("pad", CGSize(width: 1024, height: 420), .large),
            ("ax5", CGSize(width: 390, height: 640), .accessibility5),
        ]
        let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
        withSnapshotTesting(record: .missing) {
            for size in sizes {
                for scheme in schemes {
                    let root = OdometerCareSnapshotPage()
                        .environment(\.colorScheme, scheme.1)
                        .environment(\.dynamicTypeSize, size.2)
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

private struct OdometerCareSnapshotPage: View {
    @Namespace private var presets
    private let item = VehicleDueItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000024")!,
        scheduleID: UUID(uuidString: "00000000-0000-4000-8000-000000000024")!,
        vehicleID: UUID(uuidString: "00000000-0000-4000-8000-000000000025")!,
        vehicleName: "Vespa",
        kind: .service,
        title: "Service",
        dueDate: nil,
        dueOdometerKm: 4_000,
        kmLeft: 500,
        state: .upcomingKm(kmLeft: 500, approaching: true)
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VehicleCareDueChip(
                text: "500 km left",
                band: .warning,
                leadingSystemImage: "wrench.and.screwdriver",
                title: "Service"
            )
            VehicleCareDueChip(text: "40 km past", band: .alert)
            VehicleCareStatusCard(
                title: "Service",
                systemImage: "wrench.and.screwdriver",
                state: .upcomingKm(kmLeft: 500, approaching: true)
            )
            VehicleCareBannerView(item: item, onTap: {}, onDismiss: {})
            ScrollView(.horizontal, showsIndicators: false) {
                GlassChipGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([1_000, 4_000, 6_000, 10_000, 15_000], id: \.self) { preset in
                            GlassFilterChip(
                                title: "\(preset) km",
                                isSelected: false,
                                namespace: presets,
                                highlightID: "snap-\(preset)",
                                size: .compact,
                                action: {}
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
