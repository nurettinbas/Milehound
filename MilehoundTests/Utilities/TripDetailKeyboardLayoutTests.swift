import CoreGraphics
import XCTest
@testable import Milehound

final class TripDetailKeyboardLayoutTests: XCTestCase {
    func testRestingPanelHeightUsesHistoricFraction() {
        let height = TripDetailKeyboardLayout.panelHeight(
            containerHeight: 800,
            isEditing: false,
            mapPeek: 120
        )
        XCTAssertEqual(height, 800 * 0.52, accuracy: 0.001)
    }

    func testEditingPanelHeightUsesPreferredFraction() {
        let height = TripDetailKeyboardLayout.panelHeight(
            containerHeight: 800,
            isEditing: true,
            mapPeek: 96
        )
        XCTAssertEqual(height, 800 * 0.86, accuracy: 0.001)
    }

    func testEditingPanelHeightClampsToMapPeek() {
        let height = TripDetailKeyboardLayout.panelHeight(
            containerHeight: 667,
            isEditing: true,
            mapPeek: 120
        )
        XCTAssertEqual(height, 667 - 120, accuracy: 0.001)
        XCTAssertLessThan(height, 667 * 0.86)
    }

    func testEditingPanelNeverCoversNavBandOnSmallPhone() {
        let container: CGFloat = 667
        let mapPeek: CGFloat = 120
        let height = TripDetailKeyboardLayout.panelHeight(
            containerHeight: container,
            isEditing: true,
            mapPeek: mapPeek
        )
        XCTAssertLessThanOrEqual(height, container - mapPeek)
        XCTAssertGreaterThan(height, container * TripDetailKeyboardLayout.restHeightFraction)
    }

    func testScrollInsetWithoutKeyboardKeepsTabBarPad() {
        XCTAssertEqual(TripDetailKeyboardLayout.scrollBottomInset(keyboardOverlap: 0), 88)
    }

    func testScrollInsetWithKeyboardAddsAccessoryAndPadding() {
        let inset = TripDetailKeyboardLayout.scrollBottomInset(keyboardOverlap: 336)
        let expected = 336
            + TripDetailKeyboardLayout.accessoryBarHeight
            + TripDetailKeyboardLayout.keyboardScrollPadding
        XCTAssertEqual(inset, expected, accuracy: 0.001)
    }

    func testFloatingKeyboardWithZeroOverlapKeepsRestingInset() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let floating = CGRect(x: 40, y: 200, width: 310, height: 280)
        let overlap = TripDetailKeyboardLayout.keyboardOverlap(endFrame: floating, in: bounds)
        // Floating mid-screen still intersects — use a frame fully above the container.
        let above = CGRect(x: 0, y: -400, width: 390, height: 300)
        XCTAssertEqual(
            TripDetailKeyboardLayout.keyboardOverlap(endFrame: above, in: bounds),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(TripDetailKeyboardLayout.scrollBottomInset(keyboardOverlap: 0), 88)
        _ = overlap
    }

    func testKeyboardOverlapMeasuresIntersectionHeight() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let keyboard = CGRect(x: 0, y: 508, width: 390, height: 336)
        let overlap = TripDetailKeyboardLayout.keyboardOverlap(endFrame: keyboard, in: bounds)
        XCTAssertEqual(overlap, 336, accuracy: 0.001)
    }

    func testKeyboardOverlapPartialClipUsesIntersectionOnly() {
        // Panel bottom half overlaps keyboard by 120pt (keyboard starts mid-panel).
        let panel = CGRect(x: 0, y: 400, width: 390, height: 400)
        let keyboard = CGRect(x: 0, y: 680, width: 390, height: 300)
        let overlap = TripDetailKeyboardLayout.keyboardOverlap(endFrame: keyboard, in: panel)
        XCTAssertEqual(overlap, 120, accuracy: 0.001)
    }

    func testFocusOrderPreviousNext() {
        XCTAssertNil(TripDetailFocusedField.startPlace.previous)
        XCTAssertEqual(TripDetailFocusedField.startPlace.next, .endPlace)
        XCTAssertEqual(TripDetailFocusedField.endPlace.previous, .startPlace)
        XCTAssertEqual(TripDetailFocusedField.fuelPrice.next, .note)
        XCTAssertNil(TripDetailFocusedField.note.next)
        XCTAssertEqual(TripDetailFocusedField.note.previous, .fuelPrice)
    }

    func testFocusTitlesUseProvidedFuelLabels() {
        let title = TripDetailFocusedField.fuelConsumption.title(
            consumptionLabel: "L/100km",
            fuelPriceLabel: "₺/L"
        )
        XCTAssertEqual(title, "L/100km")
        XCTAssertEqual(
            TripDetailFocusedField.fuelPrice.title(
                consumptionLabel: "L/100km",
                fuelPriceLabel: "₺/L"
            ),
            "₺/L"
        )
        XCTAssertEqual(
            TripDetailFocusedField.note.title(
                consumptionLabel: "L/100km",
                fuelPriceLabel: "₺/L"
            ),
            L10n.tripEditNote
        )
    }
}
