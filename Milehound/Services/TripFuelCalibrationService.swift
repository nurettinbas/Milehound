import Foundation
import SwiftData

enum TripFuelCalibrationService {
    static func snapshot(for vehicleID: UUID?, in context: ModelContext?) -> FuelCalibrationSnapshot {
        guard let vehicleID, let context else { return .identity }
        return row(for: vehicleID, in: context)?.snapshot ?? .identity
    }

    static func rebuild(for vehicleID: UUID, in context: ModelContext) {
        let trips = measuredTrips(vehicleID: vehicleID, in: context)
        let row = row(for: vehicleID, in: context) ?? {
            let created = VehicleFuelCalibration(vehicleID: vehicleID)
            context.insert(created)
            return created
        }()

        var samples: [Sample] = []
        for trip in trips {
            guard trip.distanceMeters >= 1_000,
                  let measured = trip.measuredFuelConsumptionPer100, measured > 0
            else { continue }
            let c0 = trip.fuelConsumptionPer100 ?? 0
            guard c0 > 0, measured >= 0.5 * c0, measured <= 3.0 * c0 else { continue }

            let estimate = uncalibratedEstimate(for: trip)
            guard estimate.confidence >= 0.45, let estimatedRate = estimate.ratePer100, estimatedRate > 0
            else { continue }
            samples.append(
                Sample(
                    measuredRate: measured,
                    estimatedRate: estimatedRate,
                    km: trip.distanceMeters / 1_000,
                    speedDelta: estimate.breakdown.speedDelta,
                    idle: estimate.breakdown.idleLitres,
                    transient: estimate.breakdown.transientDelta,
                    cold: estimate.breakdown.coldStartLitres,
                    base: estimate.breakdown.baseLitres
                )
            )
        }

        let accepted = rejectOutliers(samples)
        row.acceptedCount = accepted.count
        if accepted.isEmpty {
            row.bias = 1
            row.biasLog = 0
            row.wape = 0
            row.maeRate = 0
            row.confidence = 0
            row.speedWeight = 1
            row.idleWeight = 1
            row.transientWeight = 1
            row.coldWeight = 1
            row.updatedAt = Date()
            return
        }

        let logs = accepted.map { log($0.measuredRate / $0.estimatedRate) }
        let biasLog = logs.reduce(0, +) / Double(logs.count)
        row.biasLog = biasLog
        row.bias = min(1.30, max(0.75, exp(biasLog)))

        let absLitreError = accepted.reduce(0.0) { partial, sample in
            partial + abs(sample.measuredRate - sample.estimatedRate) * sample.km / 100
        }
        let measuredLitres = accepted.reduce(0.0) { $0 + $1.measuredRate * $1.km / 100 }
        row.wape = measuredLitres > 0 ? absLitreError / measuredLitres : 0
        row.maeRate = accepted.reduce(0.0) { $0 + abs($1.measuredRate - $1.estimatedRate) } / Double(accepted.count)
        row.confidence = min(1, Double(accepted.count) / 20) * quality(accepted)

        if accepted.count >= 20, hasFeatureDiversity(accepted) {
            let weights = ridgeWeights(accepted)
            row.speedWeight = weights.speed
            row.idleWeight = weights.idle
            row.transientWeight = weights.transient
            row.coldWeight = weights.cold
        } else {
            row.speedWeight = 1
            row.idleWeight = 1
            row.transientWeight = 1
            row.coldWeight = 1
        }
        row.updatedAt = Date()
    }

    static func recomputeVehicleTrips(vehicleID: UUID, in context: ModelContext) {
        let vehicle = VehicleResolver.vehicle(withID: vehicleID, in: context)
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.vehicleID == vehicleID && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let trips = (try? context.fetch(descriptor)) ?? []
        for trip in trips {
            let previous = TripRollupDelta.snapshot(of: trip)
            TripDerivedMetrics.recomputeFuel(
                for: trip,
                fuelType: vehicle?.fuelType ?? trip.fuelTypeSnapshot ?? .petrol,
                vehicle: vehicle
            )
            TripRollupDelta.update(trip, from: previous, in: context)
        }
    }

    private struct Sample {
        var measuredRate: Double
        var estimatedRate: Double
        var km: Double
        var speedDelta: Double
        var idle: Double
        var transient: Double
        var cold: Double
        var base: Double
    }

    private static func uncalibratedEstimate(for trip: Trip) -> TripFuelEstimate.Result {
        let fuelType = trip.fuelTypeSnapshot ?? trip.vehicle?.fuelType ?? .petrol
        let c0 = trip.fuelConsumptionPer100 ?? 0
        let price = trip.fuelUnitPrice ?? 0
        return TripFuelEstimate.compute(
            points: trip.sortedPoints,
            distanceMeters: trip.distanceMeters,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: fuelType,
            durationSeconds: trip.duration,
            thermal: TripDerivedMetrics.thermalInput(for: trip),
            calibration: .identity
        )
    }

    private static func rejectOutliers(_ samples: [Sample]) -> [Sample] {
        guard samples.count >= 3 else { return samples }
        let logs = samples.map { log($0.measuredRate / $0.estimatedRate) }.sorted()
        let median = logs[logs.count / 2]
        let deviations = logs.map { abs($0 - median) }.sorted()
        let mad = max(deviations[deviations.count / 2], 1e-6)
        return zip(samples, samples.map { log($0.measuredRate / $0.estimatedRate) })
            .compactMap { sample, value in
                abs(value - median) <= 3 * mad ? sample : nil
            }
    }

    private static func quality(_ samples: [Sample]) -> Double {
        let wape = samples.reduce(0.0) { $0 + abs($1.measuredRate - $1.estimatedRate) * $1.km }
        let denom = samples.reduce(0.0) { $0 + $1.measuredRate * $1.km }
        let relative = denom > 0 ? wape / denom : 1
        return min(1, max(0.2, 1 - relative))
    }

    private static func hasFeatureDiversity(_ samples: [Sample]) -> Bool {
        let idle = samples.filter { $0.idle > 0.01 }.count
        let cold = samples.filter { $0.cold > 0.01 }.count
        let speed = samples.filter { abs($0.speedDelta) > 0.01 }.count
        return idle >= 3 && cold >= 3 && speed >= 3
    }

    private static func ridgeWeights(_ samples: [Sample]) -> (
        speed: Double, idle: Double, transient: Double, cold: Double
    ) {
        var speed = 1.0
        var idle = 1.0
        var transient = 1.0
        var cold = 1.0
        let lambda = 4.0
        for _ in 0..<24 {
            speed = clampedWeight(samples, current: (speed, idle, transient, cold), axis: 0, lambda: lambda)
            idle = clampedWeight(samples, current: (speed, idle, transient, cold), axis: 1, lambda: lambda)
            transient = clampedWeight(samples, current: (speed, idle, transient, cold), axis: 2, lambda: lambda)
            cold = clampedWeight(samples, current: (speed, idle, transient, cold), axis: 3, lambda: lambda)
        }
        return (speed, idle, transient, cold)
    }

    private static func clampedWeight(
        _ samples: [Sample],
        current: (Double, Double, Double, Double),
        axis: Int,
        lambda: Double
    ) -> Double {
        var numerator = lambda
        var denominator = lambda
        for sample in samples {
            let extras = [
                sample.speedDelta,
                sample.idle,
                sample.transient,
                sample.cold
            ]
            let feature = extras[axis]
            guard abs(feature) > 1e-9 else { continue }
            let predicted = sample.base
                + current.0 * sample.speedDelta
                + current.1 * sample.idle
                + current.2 * sample.transient
                + current.3 * sample.cold
                - extras[axis] * [current.0, current.1, current.2, current.3][axis]
            let target = sample.measuredRate * sample.km / 100
            numerator += feature * (target - predicted)
            denominator += feature * feature
        }
        return min(1.5, max(0.5, numerator / max(denominator, 1e-9)))
    }

    private static func measuredTrips(vehicleID: UUID, in context: ModelContext) -> [Trip] {
        let source = FuelMeasurementSource.userMeasured.rawValue
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate {
                $0.vehicleID == vehicleID
                    && $0.endedAt != nil
                    && $0.fuelMeasurementSourceRaw == source
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func row(for vehicleID: UUID, in context: ModelContext) -> VehicleFuelCalibration? {
        var descriptor = FetchDescriptor<VehicleFuelCalibration>(
            predicate: #Predicate { $0.vehicleID == vehicleID }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
