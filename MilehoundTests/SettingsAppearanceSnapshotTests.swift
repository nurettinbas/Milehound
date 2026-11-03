import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class SettingsAppearanceSnapshotTests: XCTestCase {
    private static let page = CGSize(width: 390, height: 844)
    private static let row = CGSize(width: 390, height: 120)
    private static let switchRow = CGSize(width: 390, height: 160)
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    private var savedMode: AppearanceMode = .system
    private var savedTextSize: AppTextSize = .standard
    private var savedPalette: ShellPalette = .sky
    private var savedLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        let settings = AppSettings.shared
        savedMode = settings.appearanceMode
        savedTextSize = settings.textSize
        savedPalette = settings.shellPalette
        savedLanguage = AppLanguageStore.shared.language
        settings.textSize = .standard
        settings.shellPalette = .sky
    }

    override func tearDown() {
        let settings = AppSettings.shared
        settings.appearanceMode = savedMode
        settings.textSize = savedTextSize
        settings.shellPalette = savedPalette
        if AppLanguageStore.shared.language != savedLanguage {
            AppLanguageStore.shared.select(savedLanguage)
        }
        super.tearDown()
    }

    func testDayNightSwitchSnapshots() {
        withSnapshotTesting(record: .missing) {
            for (schemeName, scheme) in Self.schemes {
                AppSettings.shared.appearanceMode = scheme == .dark ? .dark : .light
                assertSnapshot(
                    of: host(dayNightRow, scheme: scheme, size: Self.switchRow),
                    as: .shellImage(size: Self.switchRow),
                    named: schemeName
                )
            }
        }
    }

    func testTextSizePickerSnapshots() {
        withSnapshotTesting(record: .missing) {
            for (schemeName, scheme) in Self.schemes {
                assertSnapshot(
                    of: host(textSizePicker, scheme: scheme, size: Self.row),
                    as: .shellImage(size: Self.row),
                    named: schemeName
                )
            }
        }
    }

    func testAppearancePageSnapshots() {
        withSnapshotTesting(record: .missing) {
            for (schemeName, scheme) in Self.schemes {
                AppSettings.shared.appearanceMode = scheme == .dark ? .dark : .light
                assertSnapshot(
                    of: host(AppearanceSettingsView(), scheme: scheme, size: Self.page),
                    as: .shellImage(size: Self.page),
                    named: schemeName
                )
            }
            AppSettings.shared.appearanceMode = .light
            assertSnapshot(
                of: host(
                    AppearanceSettingsView().environment(\.dynamicTypeSize, .accessibility3),
                    scheme: .light,
                    size: Self.page
                ),
                as: .shellImage(size: Self.page),
                named: "largeType-light"
            )
        }
    }

    func testLanguagePageSnapshots() {
        withSnapshotTesting(record: .missing) {
            AppLanguageStore.shared.select(.en)
            for (schemeName, scheme) in Self.schemes {
                assertSnapshot(
                    of: host(LanguageSettingsView(), scheme: scheme, size: CGSize(width: 390, height: 420)),
                    as: .shellImage(size: CGSize(width: 390, height: 420)),
                    named: "en-\(schemeName)"
                )
            }
            AppLanguageStore.shared.select(.tr)
            assertSnapshot(
                of: host(LanguageSettingsView(), scheme: .light, size: CGSize(width: 390, height: 420)),
                as: .shellImage(size: CGSize(width: 390, height: 420)),
                named: "tr-light"
            )
        }
    }

    private var dayNightRow: some View {
        ThemeModeHeroRow()
            .padding()
            .background { AtmosphericBackground(style: .full) }
    }

    private var textSizePicker: some View {
        GlassTextSizePicker(selection: .constant(.standard))
            .padding()
    }

    private func host<V: View>(_ view: V, scheme: ColorScheme, size: CGSize) -> UIViewController {
        let root = NavigationStack { view }
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
}
