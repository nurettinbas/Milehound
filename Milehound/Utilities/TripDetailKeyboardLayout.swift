import CoreGraphics
import Foundation

/// Pure layout math for trip-detail keyboard avoidance (no UI).
enum TripDetailKeyboardLayout {
    /// Resting panel fraction of the map container (matches historic trip detail sheet).
    static let restHeightFraction: CGFloat = 0.52
    /// Expanded fraction while a text field is focused / keyboard is up.
    static let editingHeightFraction: CGFloat = 0.86
    /// Bottom pad when the keyboard is hidden (tab bar + home indicator).
    static let restingScrollBottomInset: CGFloat = 88
    /// Extra gap between the focused field and the accessory bar.
    static let keyboardScrollPadding: CGFloat = 28
    /// Compact title + Done accessory above the keyboard (`inputAccessoryView`).
    static let accessoryBarHeight: CGFloat = 52

    static func panelHeight(
        containerHeight: CGFloat,
        isEditing: Bool,
        mapPeek: CGFloat
    ) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let resting = containerHeight * restHeightFraction
        guard isEditing else { return resting }

        let preferred = containerHeight * editingHeightFraction
        let capped = max(0, containerHeight - max(mapPeek, 0))
        return min(preferred, capped)
    }

    static func scrollBottomInset(keyboardOverlap: CGFloat) -> CGFloat {
        let overlap = max(0, keyboardOverlap)
        if overlap <= 0 {
            return restingScrollBottomInset
        }
        // keyboardFrameEnd is the software keyboard only; inputAccessoryView sits above it.
        return max(
            restingScrollBottomInset,
            overlap + accessoryBarHeight + keyboardScrollPadding
        )
    }

    /// Intersection of the keyboard end-frame with `containerBounds` (same coordinate space).
    static func keyboardOverlap(endFrame: CGRect, in containerBounds: CGRect) -> CGFloat {
        guard !endFrame.isNull, !endFrame.isEmpty, !containerBounds.isEmpty else { return 0 }
        let intersection = endFrame.intersection(containerBounds)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return max(0, intersection.height)
    }
}

/// Text fields in the trip-detail edit form, in navigation order.
enum TripDetailFocusedField: Int, Hashable, CaseIterable, Comparable {
    case startPlace
    case endPlace
    case startAddress
    case endAddress
    case fuelConsumption
    case fuelPrice
    case note

    static func < (lhs: TripDetailFocusedField, rhs: TripDetailFocusedField) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var previous: TripDetailFocusedField? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }

    var next: TripDetailFocusedField? {
        guard let index = Self.allCases.firstIndex(of: self),
              index < Self.allCases.count - 1 else { return nil }
        return Self.allCases[index + 1]
    }

    /// Toolbar / accessibility title. Fuel labels are vehicle-dependent.
    func title(consumptionLabel: String, fuelPriceLabel: String) -> String {
        switch self {
        case .startPlace:
            return L10n.tripStartPlaceName
        case .endPlace:
            return L10n.tripEndPlaceName
        case .startAddress:
            return L10n.tripStartAddress
        case .endAddress:
            return L10n.tripEndAddress
        case .fuelConsumption:
            return consumptionLabel
        case .fuelPrice:
            return fuelPriceLabel
        case .note:
            return L10n.tripEditNote
        }
    }
}
