import Foundation

struct FuelSpeedKnot: Sendable {
    let kmh: Double
    let factor: Double
}

/// C₀-anchored speed shape, idle burn, and cold-start bolus by powertrain.
///
/// `shape` is L/100 relative to this vehicle’s catalog C₀ (1.0 at 50 km/h for petrol).
/// Absolute litres always scale with the user’s Settings average — never a fleet 7.5.
struct PowertrainFuelProfile: Sendable {
    enum Kind: Sendable {
        case petrol
        case diesel
        case hybrid
        case electric
    }

    let kind: Kind
    let kTransient: Double
    /// Fraction of traction energy that regen may recover (hybrid/EV).
    let regenCap: Double

    func shape(_ kmh: Double) -> Double {
        let raw: Double
        switch kind {
        case .electric:
            raw = Self.electricShape(kmh)
        case .petrol:
            raw = Self.interpolate(Self.petrolKnots(), kmh: kmh)
        case .diesel:
            raw = Self.interpolate(Self.dieselKnots(), kmh: kmh)
        case .hybrid:
            raw = Self.interpolate(Self.hybridKnots(), kmh: kmh)
        }
        return min(1.70, max(0.65, raw))
    }

    func idleLitresPerHour(c0: Double) -> Double {
        guard c0 > 0 else { return 0 }
        let petrol = min(0.20 * c0, max(0.08 * c0, 0.114 * c0))
        switch kind {
        case .electric:
            return 0
        case .petrol:
            return petrol
        case .diesel:
            return petrol * 0.75
        case .hybrid:
            return petrol * 0.10
        }
    }

    func maxColdLitres(c0: Double) -> Double {
        guard c0 > 0 else { return 0 }
        let petrol = 1.4 * c0 / 100
        switch kind {
        case .petrol: return petrol
        case .diesel: return petrol * 0.80
        case .hybrid: return petrol * 0.30
        case .electric: return 0
        }
    }

    static func profile(for fuelType: VehicleFuelType) -> PowertrainFuelProfile {
        switch fuelType {
        case .petrol, .lpg:
            // LPG is spark-ignition. Litres scale with this vehicle’s C₀, so the shape matches petrol.
            return PowertrainFuelProfile(kind: .petrol, kTransient: 3.5, regenCap: 0)
        case .diesel:
            return PowertrainFuelProfile(kind: .diesel, kTransient: 3.0, regenCap: 0)
        case .hybrid:
            return PowertrainFuelProfile(kind: .hybrid, kTransient: 1.8, regenCap: 0.35)
        case .electric:
            return PowertrainFuelProfile(kind: .electric, kTransient: 1.5, regenCap: 0.55)
        }
    }

    /// Petrol: 50 km/h = this vehicle’s C₀. Highway knots sit below 1.0 so a mixed warm trip nets ~C₀.
    private static func petrolKnots() -> [FuelSpeedKnot] {
        [
            FuelSpeedKnot(kmh: 0, factor: 1.70),
            FuelSpeedKnot(kmh: 10, factor: 1.55),
            FuelSpeedKnot(kmh: 30, factor: 1.18),
            FuelSpeedKnot(kmh: 50, factor: 1.00),
            FuelSpeedKnot(kmh: 70, factor: 0.90),
            FuelSpeedKnot(kmh: 85, factor: 0.85),
            FuelSpeedKnot(kmh: 100, factor: 1.00),
            FuelSpeedKnot(kmh: 120, factor: 1.25),
            FuelSpeedKnot(kmh: 140, factor: 1.55),
            FuelSpeedKnot(kmh: 160, factor: 1.70),
        ]
    }

    private static func dieselKnots() -> [FuelSpeedKnot] {
        petrolKnots().map { knot in
            if knot.kmh >= 85 { return knot }
            return FuelSpeedKnot(kmh: knot.kmh, factor: 1 + (knot.factor - 1) * 0.85)
        }
    }

    private static func hybridKnots() -> [FuelSpeedKnot] {
        petrolKnots().map { knot in
            if knot.kmh < 85 {
                return FuelSpeedKnot(kmh: knot.kmh, factor: 1 + (knot.factor - 1) * 0.50)
            }
            return FuelSpeedKnot(kmh: knot.kmh, factor: 1 + (knot.factor - 1) * 0.90)
        }
    }

    private static func electricShape(_ kmh: Double) -> Double {
        0.50 + 0.50 * pow(max(0, kmh) / 80.0, 2)
    }

    private static func interpolate(_ knots: [FuelSpeedKnot], kmh: Double) -> Double {
        let v = max(0, kmh)
        if v <= knots[0].kmh { return knots[0].factor }
        if v >= knots[knots.count - 1].kmh { return knots[knots.count - 1].factor }
        for index in 1..<knots.count {
            let left = knots[index - 1]
            let right = knots[index]
            if v <= right.kmh {
                let t = (v - left.kmh) / (right.kmh - left.kmh)
                return left.factor + t * (right.factor - left.factor)
            }
        }
        return knots[knots.count - 1].factor
    }
}
