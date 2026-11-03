import XCTest
@testable import Milehound

/// Accessory bar labels come from these focus enums — catch empty / wrong L10n regressions.
final class KeyboardFieldTitleTests: XCTestCase {
    func testSettingsFocusedFieldTitlesMatchL10n() {
        XCTAssertEqual(SettingsFocusedField.newCategory.title, L10n.categoryNewPlaceholder)
        XCTAssertEqual(SettingsFocusedField.fuelPrice(.petrol).title, L10n.fuelPetrol)
        XCTAssertEqual(SettingsFocusedField.fuelPrice(.lpg).title, L10n.fuelLpg)
        XCTAssertEqual(SettingsFocusedField.privacyRadius.title, L10n.settingsPrivacyRadius)

        for field in [SettingsFocusedField.newCategory, .fuelPrice(.petrol), .fuelPrice(.lpg), .privacyRadius] {
            XCTAssertFalse(field.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testPairingVehicleFocusedFieldTitles() {
        XCTAssertEqual(
            PairingVehicleFocusedField.name.title(consumptionLabel: "L/100 km"),
            L10n.pairingTabVehicleName
        )
        XCTAssertEqual(
            PairingVehicleFocusedField.consumption.title(consumptionLabel: "kWh/100 km"),
            "kWh/100 km"
        )
        XCTAssertEqual(
            PairingVehicleFocusedField.chargePrice.title(consumptionLabel: "ignored"),
            L10n.pairingTabChargePrice
        )

        for field: PairingVehicleFocusedField in [.name, .consumption, .chargePrice] {
            XCTAssertFalse(
                field.title(consumptionLabel: "x")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
        }
    }
}
