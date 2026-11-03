import Foundation

/// Liter / kWh prices keyed by fuel type. Petrol keeps `fuelPricePerLiter`.
/// Diesel and hybrid use that liter price until their own key is set, so an existing
/// shared price does not jump. LPG and electric never read the petrol price.
enum FuelUnitPrices {
    static let petrolFallback = 65.0
    static let lpgFallback = 35.0
    static let electricFallback = 8.5

    static func resolved(fuelType: VehicleFuelType, defaults: UserDefaults) -> Double {
        switch fuelType {
        case .electric:
            return positive(defaults, key: "evChargePricePerKWh") ?? electricFallback
        case .lpg:
            return positive(defaults, key: "lpgPricePerLiter") ?? lpgFallback
        case .diesel:
            return positive(defaults, key: "dieselPricePerLiter") ?? sharedLiter(defaults)
        case .hybrid:
            return positive(defaults, key: "hybridPricePerLiter") ?? sharedLiter(defaults)
        case .petrol:
            return sharedLiter(defaults)
        }
    }

    static func set(_ value: Double, fuelType: VehicleFuelType, defaults: UserDefaults) {
        defaults.set(value, forKey: storageKey(for: fuelType))
    }

    static func storageKey(for fuelType: VehicleFuelType) -> String {
        switch fuelType {
        case .petrol: "fuelPricePerLiter"
        case .diesel: "dieselPricePerLiter"
        case .lpg: "lpgPricePerLiter"
        case .hybrid: "hybridPricePerLiter"
        case .electric: "evChargePricePerKWh"
        }
    }

    private static func sharedLiter(_ defaults: UserDefaults) -> Double {
        positive(defaults, key: "fuelPricePerLiter") ?? petrolFallback
    }

    private static func positive(_ defaults: UserDefaults, key: String) -> Double? {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }
}

/// Settings shows one price row per fuel type the user actually has.
/// No vehicles yet → petrol, which is the default type on a new car.
enum FuelPriceRows {
    static func types(in fuelTypes: [VehicleFuelType]) -> [VehicleFuelType] {
        let present = Set(fuelTypes)
        let ordered = VehicleFuelType.allCases.filter { present.contains($0) }
        return ordered.isEmpty ? [.petrol] : ordered
    }
}

enum FuelCostCalculator {
    private static let suiteName = "group.com.milehound.app"
    private static let fuelCurrencyKey = "fuelCurrency"

    /// Resolved L/100 km or kWh/100 km for estimates (trip snapshot → vehicle → global default).
    static func resolvedConsumption(
        tripConsumption: Double? = nil,
        vehicle: VehicleProfile? = nil
    ) -> Double {
        if let tripConsumption, tripConsumption > 0 {
            return tripConsumption
        }
        if let vehicle, vehicle.consumption > 0 {
            return vehicle.consumption
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let litersPer100 = defaults.double(forKey: "fuelLitersPer100km")
        return litersPer100 > 0 ? litersPer100 : 7.5
    }

    /// Resolved unit price (per liter or per kWh).
    static func resolvedUnitPrice(
        tripUnitPrice: Double? = nil,
        vehicle: VehicleProfile? = nil,
        fuelType: VehicleFuelType? = nil
    ) -> Double {
        if let tripUnitPrice, tripUnitPrice > 0 {
            return tripUnitPrice
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let resolvedType = vehicle?.fuelType ?? fuelType ?? .petrol
        if resolvedType == .electric,
           let vehiclePrice = vehicle?.chargePricePerKWh,
           vehiclePrice > 0 {
            return vehiclePrice
        }
        return FuelUnitPrices.resolved(fuelType: resolvedType, defaults: defaults)
    }

    static func estimateCost(
        distanceMeters: Double,
        vehicle: VehicleProfile? = nil,
        consumptionPer100: Double? = nil,
        unitPrice: Double? = nil,
        fuelType: VehicleFuelType? = nil
    ) -> Double {
        let kilometers = distanceMeters / 1000
        guard kilometers > 0 else { return 0 }

        let consumption = resolvedConsumption(tripConsumption: consumptionPer100, vehicle: vehicle)
        let price = resolvedUnitPrice(
            tripUnitPrice: unitPrice,
            vehicle: vehicle,
            fuelType: fuelType ?? vehicle?.fuelType
        )
        let volume = kilometers * consumption / 100
        return volume * price
    }

    static func estimateCost(for trip: Trip, vehicle: VehicleProfile? = nil) -> Double {
        if let cost = trip.estimatedFuelCost, cost > 0 {
            return cost
        }
        return estimateCost(
            distanceMeters: trip.distanceMeters,
            vehicle: vehicle,
            consumptionPer100: trip.fuelConsumptionPer100,
            unitPrice: trip.fuelUnitPrice
        )
    }

    /// Applies resolved consumption/price snapshots and recomputes `estimatedFuelCost`.
    static func applyEstimate(
        to trip: Trip,
        distanceMeters: Double,
        vehicle: VehicleProfile?,
        consumptionPer100: Double? = nil,
        unitPrice: Double? = nil
    ) {
        let consumption = resolvedConsumption(
            tripConsumption: (consumptionPer100 ?? 0) > 0 ? consumptionPer100 : trip.fuelConsumptionPer100,
            vehicle: vehicle
        )
        let price = resolvedUnitPrice(
            tripUnitPrice: (unitPrice ?? 0) > 0 ? unitPrice : trip.fuelUnitPrice,
            vehicle: vehicle,
            fuelType: vehicle?.fuelType
        )
        trip.fuelConsumptionPer100 = consumption
        trip.fuelUnitPrice = price
        trip.estimatedFuelCost = estimateCost(
            distanceMeters: distanceMeters,
            vehicle: vehicle,
            consumptionPer100: consumption,
            unitPrice: price
        )
    }

    /// ISO currency code from App Group settings (`TRY` when unset).
    static func resolvedCurrencyCode(
        defaults: UserDefaults? = nil
    ) -> String {
        let store = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        if let raw = store.string(forKey: fuelCurrencyKey),
           let currency = FuelCurrency(rawValue: raw) {
            return currency.rawValue
        }
        return FuelCurrency.default.rawValue
    }

    static func formatCost(
        _ amount: Double,
        currencyCode: String? = nil,
        locale: Locale? = nil
    ) -> String {
        let code = currencyCode ?? resolvedCurrencyCode()
        let formatter = NumberFormatter()
        formatter.locale = locale ?? DateFormatters.currentLocale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        if let symbol = FuelCurrency(rawValue: code)?.symbol {
            formatter.currencySymbol = "\(symbol) "
        }
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount.rounded()))"
    }

    /// Litres or kWh implied by cost ÷ unit price, e.g. `"0,3 L"`.
    static func formatVolume(
        cost: Double,
        unitPrice: Double,
        isElectric: Bool,
        locale: Locale? = nil
    ) -> String? {
        guard cost > 0, unitPrice > 0 else { return nil }
        let volume = cost / unitPrice
        let unit = isElectric ? "kWh" : "L"
        let formatter = NumberFormatter()
        formatter.locale = locale ?? DateFormatters.currentLocale
        formatter.maximumFractionDigits = volume >= 10 ? 1 : 2
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: volume)) ?? String(format: "%.1f", volume)
        return "\(number) \(unit)"
    }

    static func formatVolumeAmount(
        _ volume: Double,
        isElectric: Bool,
        locale: Locale? = nil
    ) -> String? {
        guard volume > 0 else { return nil }
        let unit = isElectric ? "kWh" : "L"
        let formatter = NumberFormatter()
        formatter.locale = locale ?? DateFormatters.currentLocale
        formatter.maximumFractionDigits = volume >= 10 ? 1 : 2
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: volume)) ?? String(format: "%.1f", volume)
        return "\(number) \(unit)"
    }

    static func formatRatePer100(
        _ rate: Double,
        isElectric: Bool,
        locale: Locale? = nil
    ) -> String? {
        guard rate > 0 else { return nil }
        let unit = isElectric ? "kWh/100 km" : "L/100 km"
        let formatter = NumberFormatter()
        formatter.locale = locale ?? DateFormatters.currentLocale
        formatter.maximumFractionDigits = rate >= 10 ? 1 : 1
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: rate)) ?? String(format: "%.1f", rate)
        return "\(number) \(unit)"
    }
}
