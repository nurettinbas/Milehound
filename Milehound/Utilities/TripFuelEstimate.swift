import CoreLocation
import Foundation

struct FuelThermalInput: Equatable, Sendable {
    var previousEndedAt: Date?
    var previousMovingMinutes: Double
    var previousDistanceKm: Double
    var tripStartedAt: Date
    var hasVehicleContinuity: Bool

    static func unknown(startedAt: Date) -> FuelThermalInput {
        FuelThermalInput(
            previousEndedAt: nil,
            previousMovingMinutes: 0,
            previousDistanceKm: 0,
            tripStartedAt: startedAt,
            hasVehicleContinuity: false
        )
    }
}

struct FuelCalibrationSnapshot: Equatable, Sendable {
    var bias: Double = 1
    var speedWeight: Double = 1
    var idleWeight: Double = 1
    var transientWeight: Double = 1
    var coldWeight: Double = 1
    var acceptedCount: Int = 0
    var confidence: Double = 0

    static let identity = FuelCalibrationSnapshot()

    var usesComponentWeights: Bool { acceptedCount >= 20 }
}

struct FuelEstimateBreakdown: Equatable, Sendable {
    var baseLitres: Double
    var speedDelta: Double
    var idleLitres: Double
    var transientDelta: Double
    var coldStartLitres: Double
    var guardAdjustment: Double
    var wasClipped: Bool

    var total: Double {
        max(0, baseLitres + speedDelta + idleLitres + transientDelta + coldStartLitres + guardAdjustment)
    }
}

enum FuelFactorKind: String, Sendable {
    case coldStart
    case idleTraffic
    case transientAcceleration
    case highSpeed
    case lowSpeed
    case steadyEfficientSpeed
}

/// Trip-specific fuel from GPS, scaled to the vehicle's catalog C₀.
///
/// Canonical formula (model v6). C₀ is the Settings average for this car — never a hardcoded 7.5.
/// Traffic score is a label, not a multiplier. Stop-go count is not a fuel term.
///
/// ```
/// Avg  = km × C₀ / 100
///
/// baseLitres     = Avg
/// speedDelta     = km × C₀/100 × (distanceWeightedSpeedFactor − 1)   // signed
/// idleLitres     = estimatedIdleSeconds / 3600 × idleLph(C₀)
/// transientDelta = baseLitres × clamp(kTransient × energyIndex, 0, 0.35)
/// coldLitres     = coldProbability × maxCold(C₀) × warmupProgress
///
/// Est litres = base
///            + motionConfidence × (speedDelta + idle + transient)
///            + thermalConfidence × cold
///            [× vehicle bias when ≥5 accepted measurements]
///
/// L/100 = 100 × Est litres / km
/// cost  = Est litres × unit price
/// ```
///
/// Unusable traces fall back toward `C₀ × km / 100`. See `docs/FUEL_ESTIMATION.md`.
enum TripFuelEstimate {
    static let movingSpeedKmh: Double = TripMotionThresholds.movingSpeedKmh
    static let maximumStopGapSeconds: TimeInterval = TripMotionThresholds.maximumStopGapSeconds
    static let minimumIntervalSeconds: TimeInterval = TripMotionThresholds.minimumAccelIntervalSeconds
    static let maximumAbsAccelerationMps2: Double = TripMotionThresholds.maximumAbsAccelerationMps2
    static let currentModelVersion = 6

    struct Result: Equatable, Sendable {
        var avgVolume: Double
        var dynamicVolume: Double
        var avgCost: Double
        var dynamicCost: Double
        var confidence: Double
        var ratePer100: Double?
        var efficiencyScore: Double
        var trafficScore: Double
        var trafficLevel: FuelTrafficLevel
        var coldStartProbability: Double
        var thermalConfidence: Double
        var breakdown: FuelEstimateBreakdown
        var features: FuelTripFeatures
        var factors: [FuelFactorKind]

        static let zero = Result(
            avgVolume: 0,
            dynamicVolume: 0,
            avgCost: 0,
            dynamicCost: 0,
            confidence: 0,
            ratePer100: nil,
            efficiencyScore: 80,
            trafficScore: 0,
            trafficLevel: .unknown,
            coldStartProbability: 0,
            thermalConfidence: 0,
            breakdown: FuelEstimateBreakdown(
                baseLitres: 0,
                speedDelta: 0,
                idleLitres: 0,
                transientDelta: 0,
                coldStartLitres: 0,
                guardAdjustment: 0,
                wasClipped: false
            ),
            features: .empty,
            factors: []
        )
    }

    static func compute(
        samples: [RouteSample],
        distanceMeters: Double,
        consumptionPer100: Double,
        unitPrice: Double,
        fuelType: VehicleFuelType,
        durationSeconds: TimeInterval? = nil,
        thermal: FuelThermalInput? = nil,
        calibration: FuelCalibrationSnapshot = .identity,
        excludedStops: [TripFuelMotionTimeline.ExcludedStop] = []
    ) -> Result {
        let kilometers = max(0, distanceMeters) / 1_000
        let c0 = consumptionPer100
        let price = max(0, unitPrice)
        let avgVolume = c0 > 0 ? kilometers * c0 / 100 : 0
        let avgCost = avgVolume * price
        let duration = durationSeconds
            ?? (samples.count >= 2
                ? samples[samples.count - 1].timestamp.timeIntervalSince(samples[0].timestamp)
                : 0)

        guard c0 > 0 else {
            var empty = Result.zero
            empty.avgVolume = 0
            empty.avgCost = 0
            return empty
        }

        let timeline = TripFuelMotionTimeline.build(
            samples: samples,
            storedDistanceMeters: distanceMeters,
            excludedStops: excludedStops
        )
        let features = FuelTripFeatures.extract(
            timeline: timeline,
            storedDistanceMeters: distanceMeters,
            durationSeconds: duration,
            fuelType: fuelType
        )

        let profile = PowertrainFuelProfile.profile(for: fuelType)
        let baseLitres = avgVolume
        let thermalState = thermalState(thermal)
        let motionConfidence = features.motionConfidence

        var speedDelta = baseLitres * (features.distanceWeightedSpeedFactor - 1)
        var idleLitres = features.estimatedIdleSeconds / 3_600 * profile.idleLitresPerHour(c0: c0)
        var transientDelta = baseLitres * min(0.35, max(0, profile.kTransient * features.energyIndex))
        let warmupProgress = 1 - exp(
            -((features.durationSeconds - features.stopDurationSeconds) / 120
                + features.estimatedIdleSeconds / 174)
        )
        var coldLitres = thermalState.probability * profile.maxColdLitres(c0: c0) * min(1, max(0, warmupProgress))

        if calibration.usesComponentWeights {
            speedDelta *= calibration.speedWeight
            idleLitres *= calibration.idleWeight
            transientDelta *= calibration.transientWeight
            coldLitres *= calibration.coldWeight
        }

        let blendedSpeed = motionConfidence * speedDelta
        let blendedIdle = motionConfidence * idleLitres
        let blendedTransient = motionConfidence * transientDelta
        let blendedCold = thermalState.confidence * coldLitres
        var raw = baseLitres + blendedSpeed + blendedIdle + blendedTransient + blendedCold
        if calibration.acceptedCount >= 5 {
            raw *= min(1.30, max(0.75, calibration.bias))
        }
        raw = max(0, raw)

        var wasClipped = false
        var guardAdjustment = raw - (baseLitres + blendedSpeed + blendedIdle + blendedTransient + blendedCold)
        if kilometers >= 1 {
            let minRate = 0.5 * c0
            let maxRate = 3.5 * c0
            let rate = 100 * raw / kilometers
            if rate < minRate {
                let clipped = kilometers * minRate / 100
                guardAdjustment += clipped - raw
                raw = clipped
                wasClipped = true
            } else if rate > maxRate {
                let clipped = kilometers * maxRate / 100
                guardAdjustment += clipped - raw
                raw = clipped
                wasClipped = true
            }
        }

        let breakdown = FuelEstimateBreakdown(
            baseLitres: baseLitres,
            speedDelta: blendedSpeed,
            idleLitres: blendedIdle,
            transientDelta: blendedTransient,
            coldStartLitres: blendedCold,
            guardAdjustment: guardAdjustment,
            wasClipped: wasClipped
        )
        let dynamicVolume = max(0, raw)
        let rate: Double? = kilometers >= 0.2 ? 100 * dynamicVolume / kilometers : nil
        let efficiency = efficiencyScore(
            rate: rate,
            c0: c0,
            features: features,
            motionConfidence: motionConfidence
        )
        let factors = contributingFactors(breakdown: breakdown, baseLitres: baseLitres, features: features)

        return Result(
            avgVolume: avgVolume,
            dynamicVolume: dynamicVolume,
            avgCost: avgCost,
            dynamicCost: dynamicVolume * price,
            confidence: motionConfidence,
            ratePer100: rate,
            efficiencyScore: efficiency,
            trafficScore: features.trafficScore,
            trafficLevel: features.trafficLevel,
            coldStartProbability: thermalState.probability,
            thermalConfidence: thermalState.confidence,
            breakdown: breakdown,
            features: features,
            factors: factors
        )
    }

    static func compute(
        points: [TripPoint],
        distanceMeters: Double,
        consumptionPer100: Double,
        unitPrice: Double,
        fuelType: VehicleFuelType,
        durationSeconds: TimeInterval? = nil,
        thermal: FuelThermalInput? = nil,
        calibration: FuelCalibrationSnapshot = .identity,
        excludedStops: [TripFuelMotionTimeline.ExcludedStop] = []
    ) -> Result {
        compute(
            samples: RouteDisplayPath.samples(from: points),
            distanceMeters: distanceMeters,
            consumptionPer100: consumptionPer100,
            unitPrice: unitPrice,
            fuelType: fuelType,
            durationSeconds: durationSeconds,
            thermal: thermal,
            calibration: calibration,
            excludedStops: excludedStops
        )
    }

    static func coldProbability(
        previousMovingMinutes: Double,
        previousDistanceKm: Double,
        soakHours: Double
    ) -> Double {
        let prevWarmEnd = 1 - exp(-(previousMovingMinutes / 8 + previousDistanceKm / 5))
        let retained = prevWarmEnd * exp(-soakHours / 2.0)
        return min(1, max(0, 1 - retained))
    }

    private static func thermalState(_ thermal: FuelThermalInput?) -> (probability: Double, confidence: Double) {
        guard let thermal else {
            return (1, 0.65)
        }
        guard let ended = thermal.previousEndedAt, thermal.hasVehicleContinuity else {
            return (1, 0.65)
        }
        let soakHours = max(0, thermal.tripStartedAt.timeIntervalSince(ended) / 3_600)
        let probability = coldProbability(
            previousMovingMinutes: thermal.previousMovingMinutes,
            previousDistanceKm: thermal.previousDistanceKm,
            soakHours: soakHours
        )
        return (probability, 1)
    }

    private static func efficiencyScore(
        rate: Double?,
        c0: Double,
        features: FuelTripFeatures,
        motionConfidence: Double
    ) -> Double {
        guard let rate, c0 > 0, rate > 0 else { return 80 }
        let ratio = rate / c0
        let fuelScore = min(100, max(0, 80 - 70 * log(ratio)))
        let km = max(features.distanceKm, 0.5)
        let idleNorm = min(1, features.stopShare / 0.40)
        let hardAccelNorm = min(1, Double(features.hardAccelerationCount) / km / 0.75)
        let hardBrakeNorm = min(1, Double(features.hardBrakingCount) / km / 0.75)
        let veryHighNorm = min(1, features.veryHighShare / 0.30)
        let healthyConstant = min(1, features.constantSpeedRatio / 0.50)
        let behavior = min(
            100,
            max(
                0,
                100 - 25 * idleNorm - 20 * hardAccelNorm - 15 * hardBrakeNorm
                    - 15 * veryHighNorm + 10 * healthyConstant
            )
        )
        return motionConfidence * (0.70 * fuelScore + 0.30 * behavior)
            + (1 - motionConfidence) * fuelScore
    }

    private static func contributingFactors(
        breakdown: FuelEstimateBreakdown,
        baseLitres: Double,
        features: FuelTripFeatures
    ) -> [FuelFactorKind] {
        let threshold = max(0.0001, abs(baseLitres) * 0.05)
        var ranked: [(FuelFactorKind, Double)] = []
        if breakdown.coldStartLitres >= threshold {
            ranked.append((.coldStart, breakdown.coldStartLitres))
        }
        if breakdown.idleLitres >= threshold {
            ranked.append((.idleTraffic, breakdown.idleLitres))
        }
        if breakdown.transientDelta >= threshold {
            ranked.append((.transientAcceleration, breakdown.transientDelta))
        }
        if breakdown.speedDelta >= threshold {
            let kind: FuelFactorKind = features.veryHighShare >= 0.08 || features.highSpeedSeconds > features.lowSpeedSeconds
                ? .highSpeed
                : .lowSpeed
            ranked.append((kind, breakdown.speedDelta))
        } else if breakdown.speedDelta <= -threshold {
            ranked.append((.steadyEfficientSpeed, -breakdown.speedDelta))
        }
        return Array(ranked.sorted { $0.1 > $1.1 }.prefix(4).map(\.0))
    }
}
