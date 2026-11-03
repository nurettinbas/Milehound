import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Trailhound

@MainActor
final class AcknowledgementsSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 390, height: 560)
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testAcknowledgementsSnapshots() {
        for (schemeName, scheme) in Self.schemes {
            assertSnapshot(
                of: host(scheme: scheme),
                as: .shellImage(size: Self.size),
                named: schemeName
            )
        }
    }

    func testEverySoundCreditsAuthorAndLinksOverHTTPS() {
        XCTAssertEqual(AcknowledgementCredit.sounds.map(\.id), ["trip_start", "trip_stop"])
        for credit in AcknowledgementCredit.sounds {
            XCTAssertFalse(credit.author.isEmpty)
            XCTAssertEqual(credit.sourceURL.scheme, "https")
            XCTAssertEqual(credit.sourceURL.host, "commons.wikimedia.org")
            XCTAssertNotEqual(L10n.string(credit.titleKey), credit.titleKey, "Missing localization for \(credit.titleKey)")
        }
        XCTAssertEqual(AcknowledgementCredit.licenseURL.host, "creativecommons.org")
    }

    func testBundledSoundsHaveACredit() {
        let candidates: [String] = ["trip_start", "trip_stop"]
        let bundled = candidates.filter { name in
            Bundle.main.url(forResource: name, withExtension: "caf") != nil
        }
        XCTAssertFalse(bundled.isEmpty, "Trip sounds are missing from the app bundle")
        let credited = Set(AcknowledgementCredit.sounds.map { $0.id })
        for sound in bundled {
            XCTAssertTrue(credited.contains(sound), "\(sound).caf ships without a credit")
        }
    }

    private func host(scheme: ColorScheme) -> UIViewController {
        // Solid plate, not native Liquid Glass. Those shaders differ between simulator runtimes.
        let root = NavigationStack {
            AcknowledgementsView()
        }
        .environment(\.colorScheme, scheme)
        .environment(\.shellPalette, .sky)
        .environment(\.glassForcesSolidPlate, true)
        .frame(width: Self.size.width, height: Self.size.height)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        controller.view.bounds = CGRect(origin: .zero, size: Self.size)
        controller.view.backgroundColor = .clear
        return controller
    }
}
