import SwiftUI
import XCTest
@testable import Milehound

final class AppTextSizeTests: XCTestCase {
    func testStandardLeavesTheSystemSizeAlone() {
        for system in DynamicTypeSize.allCases {
            XCTAssertEqual(AppTextSize.standard.resolved(system: system), system)
        }
    }

    func testStepsStayInsideTheScale() {
        XCTAssertEqual(AppTextSize.small.resolved(system: .xSmall), .xSmall)
        XCTAssertEqual(AppTextSize.small.resolved(system: .large), .medium)
        XCTAssertEqual(AppTextSize.large.resolved(system: .large), .xLarge)
        XCTAssertEqual(AppTextSize.extraLarge.resolved(system: .large), .xxLarge)
        XCTAssertEqual(AppTextSize.extraLarge.resolved(system: .accessibility5), .accessibility5)
    }

    func testAccessibilitySizesAreNotForcedDownToStandard() {
        XCTAssertEqual(AppTextSize.small.resolved(system: .accessibility1), .xxxLarge)
        XCTAssertNotEqual(AppTextSize.small.resolved(system: .accessibility1), .large)
    }
}

@MainActor
final class AppSettingsTextSizeTests: XCTestCase {
    func testTextSizeDefaultsToStandardAndPersists() {
        let suiteName = "test.milehound.textSize.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        XCTAssertEqual(settings.textSize, .standard)
        XCTAssertEqual(settings.appearanceMode, .system)

        settings.textSize = .large
        XCTAssertEqual(defaults.string(forKey: "appearance.textSize"), "large")

        let reloaded = AppSettings(userDefaults: defaults)
        XCTAssertEqual(reloaded.textSize, .large)
    }
}

@MainActor
final class AppLanguageStoreTests: XCTestCase {
    func testUnknownStoredCodeStaysOnSystem() {
        let suiteName = "test.milehound.language.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("de", forKey: SharedLanguage.storageKey)

        let store = AppLanguageStore(userDefaults: defaults)
        XCTAssertEqual(store.language, .system)
        XCTAssertEqual(AppLanguage.en.nativeName, "English")
        XCTAssertEqual(AppLanguage.tr.nativeName, "Türkçe")
    }

    func testSelectWritesTheAppGroupAndAppleLanguages() {
        let suiteName = "test.milehound.language.select.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previous = UserDefaults.standard.object(forKey: "AppleLanguages")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }

        let store = AppLanguageStore(userDefaults: defaults)
        XCTAssertEqual(store.language, .system)

        store.select(.tr)
        XCTAssertEqual(store.language, .tr)
        XCTAssertEqual(defaults.string(forKey: SharedLanguage.storageKey), "tr")
        let domain = Bundle.main.bundleIdentifier ?? ""
        XCTAssertEqual(
            UserDefaults.standard.persistentDomain(forName: domain)?["AppleLanguages"] as? [String],
            ["tr"]
        )
        let revision = store.revision

        store.select(.tr)
        XCTAssertEqual(store.revision, revision)

        store.select(.system)
        XCTAssertEqual(store.language, .system)
        XCTAssertEqual(defaults.string(forKey: SharedLanguage.storageKey), "system")
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: domain)?["AppleLanguages"])
    }
}

final class SupportMailLanguageTests: XCTestCase {
    func testPrivacyURLFollowsTheStoredAppLanguage() {
        let defaults = RecordingControlBridge.sharedDefaults()
        let key = SharedLanguage.storageKey
        let previous = defaults.string(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            SharedLanguage.invalidate()
        }

        defaults.set("tr", forKey: key)
        SharedLanguage.invalidate()
        XCTAssertEqual(SupportMail.privacyPolicyURL, SupportMail.privacyPolicyTurkishURL)

        defaults.set("en", forKey: key)
        SharedLanguage.invalidate()
        XCTAssertEqual(SupportMail.privacyPolicyURL, SupportMail.privacyPolicyEnglishURL)
    }
}
