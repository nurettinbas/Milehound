import Foundation

enum FuelTrafficLevel: String, Sendable {
    case low
    case moderate
    case heavy
    case unknown
}

/// The 25 GPS metrics plus quality, derived from one cleaned motion walk.
struct FuelTripFeatures: Equatable, Sendable {
    var distanceKm: Double
    var durationSeconds: TimeInterval
    var averageSpeedKmh: Double
    var movingAverageSpeedKmh: Double
    var stopDurationSeconds: TimeInterval
    var waitingDurationSeconds: TimeInterval
    var estimatedIdleSeconds: TimeInterval
    var stopGoCount: Int
    var stopGoPerKm: Double
    var accelerationEpisodeCount: Int
    var hardAccelerationCount: Int
    var meanPositiveAcceleration: Double
    var maxAcceleration: Double
    var hardBrakingCount: Int
    var constantSpeedSeconds: TimeInterval
    var constantSpeedMeters: Double
    var constantSpeedRatio: Double
    var lowSpeedSeconds: TimeInterval
    var mediumSpeedSeconds: TimeInterval
    var highSpeedSeconds: TimeInterval
    var veryHighSpeedSeconds: TimeInterval
    /// Seconds in 0–5 / 5–30 / 30–50 / 50–70 / 70–90 / 90–110 / 110+.
    var speedHistogram: [TimeInterval]
    var speedVariability: Double
    var trafficScore: Double
    var trafficLevel: FuelTrafficLevel
    var distanceWeightedSpeedFactor: Double
    var energyIndex: Double
    var motionConfidence: Double
    var observedMovingKm: Double
    var maxSpeedKmh: Double
    var stopShare: Double
    var veryHighShare: Double

    static let empty = FuelTripFeatures(
        distanceKm: 0,
        durationSeconds: 0,
        averageSpeedKmh: 0,
        movingAverageSpeedKmh: 0,
        stopDurationSeconds: 0,
        waitingDurationSeconds: 0,
        estimatedIdleSeconds: 0,
        stopGoCount: 0,
        stopGoPerKm: 0,
        accelerationEpisodeCount: 0,
        hardAccelerationCount: 0,
        meanPositiveAcceleration: 0,
        maxAcceleration: 0,
        hardBrakingCount: 0,
        constantSpeedSeconds: 0,
        constantSpeedMeters: 0,
        constantSpeedRatio: 0,
        lowSpeedSeconds: 0,
        mediumSpeedSeconds: 0,
        highSpeedSeconds: 0,
        veryHighSpeedSeconds: 0,
        speedHistogram: Array(repeating: 0, count: 7),
        speedVariability: 0,
        trafficScore: 0,
        trafficLevel: .unknown,
        distanceWeightedSpeedFactor: 1,
        energyIndex: 0,
        motionConfidence: 0,
        observedMovingKm: 0,
        maxSpeedKmh: 0,
        stopShare: 0,
        veryHighShare: 0
    )

    static func extract(
        timeline: TripFuelMotionTimeline.Result,
        storedDistanceMeters: Double,
        durationSeconds: TimeInterval,
        fuelType: VehicleFuelType
    ) -> FuelTripFeatures {
        let storedKm = max(0, storedDistanceMeters) / 1_000
        let duration = max(0, durationSeconds)
        let profile = PowertrainFuelProfile.profile(for: fuelType)
        let intervals = timeline.intervals
        guard !intervals.isEmpty else {
            var empty = FuelTripFeatures.empty
            empty.distanceKm = storedKm
            empty.durationSeconds = duration
            empty.averageSpeedKmh = duration > 0 ? storedKm / (duration / 3_600) : 0
            empty.motionConfidence = 0
            empty.trafficLevel = .unknown
            return empty
        }

        var stopDuration: TimeInterval = 0
        var waitingDuration: TimeInterval = 0
        var idleSeconds: TimeInterval = 0
        var movingSeconds: TimeInterval = 0
        var movingMeters = 0.0
        var shapeWeightedKm = 0.0
        var kineticSum = 0.0
        var regenSum = 0.0
        var low: TimeInterval = 0
        var medium: TimeInterval = 0
        var high: TimeInterval = 0
        var veryHigh: TimeInterval = 0
        var histogram = Array(repeating: 0.0, count: 7)
        var constantSeconds: TimeInterval = 0
        var constantMeters = 0.0
        var constantRun: TimeInterval = 0
        var constantRunMeters = 0.0
        var positiveATime: TimeInterval = 0
        var positiveASum = 0.0
        var accelerations: [Double] = []
        var movingSpeedsKmh: [Double] = []
        var maxSpeedKmh = 0.0
        var accelEpisodes = 0
        var hardAccelCount = 0
        var hardBrakeCount = 0
        var inAccelEpisode = false
        var inHardAccel = false
        var hardAccelRun: TimeInterval = 0
        var hardBrakeRun: TimeInterval = 0
        var stopGoCount = 0
        var previousWasStopRun = false
        var secondsSinceStop: TimeInterval = 0
        var reached15AfterStop = false

        func flushConstant() {
            if constantRun >= 10 {
                constantSeconds += constantRun
                constantMeters += constantRunMeters
            }
            constantRun = 0
            constantRunMeters = 0
        }

        func histogramIndex(kmh: Double) -> Int {
            if kmh < 5 { return 0 }
            if kmh < 30 { return 1 }
            if kmh < 50 { return 2 }
            if kmh < 70 { return 3 }
            if kmh < 90 { return 4 }
            if kmh < 110 { return 5 }
            return 6
        }

        var stopRunRaw: TimeInterval = 0
        var stopRunEvidence: TimeInterval = 0

        func flushStopRun() {
            guard stopRunRaw > 0 else { return }
            stopDuration += stopRunRaw
            if stopRunRaw >= 10 {
                waitingDuration += stopRunRaw
            }
            let probability = TripFuelMotionTimeline.engineOnProbability(forRunDuration: stopRunRaw)
            idleSeconds += stopRunEvidence * probability
            previousWasStopRun = true
            secondsSinceStop = 0
            reached15AfterStop = false
            stopRunRaw = 0
            stopRunEvidence = 0
        }

        var previousSpeedMps: Double?
        for interval in intervals {
            switch interval.kind {
            case .unobserved, .teleport:
                flushStopRun()
                flushConstant()
                previousSpeedMps = nil
                previousWasStopRun = false
            case .observedStop:
                flushConstant()
                stopRunRaw += interval.dt
                stopRunEvidence += interval.dt * interval.evidenceWeight
                previousSpeedMps = 0
            case .moving:
                flushStopRun()
                let kmh = interval.speedMps * 3.6
                let km = interval.distanceMeters / 1_000
                movingSeconds += interval.dt
                movingMeters += interval.distanceMeters
                movingSpeedsKmh.append(kmh)
                maxSpeedKmh = max(maxSpeedKmh, kmh)
                shapeWeightedKm += km * profile.shape(kmh)
                histogram[histogramIndex(kmh: kmh)] += interval.dt

                if kmh < 30 {
                    low += interval.dt
                } else if kmh < 70 {
                    medium += interval.dt
                } else if kmh < 100 {
                    high += interval.dt
                } else {
                    veryHigh += interval.dt
                }

                let isConstant = abs(interval.accelerationMps2) < 0.3 && kmh >= 40 && kmh <= 100
                if isConstant {
                    constantRun += interval.dt
                    constantRunMeters += interval.distanceMeters
                } else {
                    flushConstant()
                }

                if interval.accelerationAvailable, interval.accelerationMps2 > 0.5 {
                    if !inAccelEpisode { accelEpisodes += 1 }
                    inAccelEpisode = true
                } else {
                    inAccelEpisode = false
                }

                if interval.accelerationAvailable, interval.accelerationMps2 > 1.5 {
                    inHardAccel = true
                    hardAccelRun += interval.dt
                } else {
                    if inHardAccel, hardAccelRun >= 1 { hardAccelCount += 1 }
                    inHardAccel = false
                    hardAccelRun = 0
                }

                if interval.accelerationAvailable, interval.accelerationMps2 < -2.0 {
                    hardBrakeRun += interval.dt
                } else {
                    if hardBrakeRun >= 1 { hardBrakeCount += 1 }
                    hardBrakeRun = 0
                }

                if interval.accelerationAvailable, interval.accelerationMps2 > 0 {
                    positiveATime += interval.dt
                    positiveASum += interval.accelerationMps2 * interval.dt
                    accelerations.append(interval.accelerationMps2)
                }

                if previousWasStopRun {
                    secondsSinceStop += interval.dt
                    if kmh >= 15, secondsSinceStop <= 20, !reached15AfterStop {
                        stopGoCount += 1
                        reached15AfterStop = true
                    }
                    if secondsSinceStop > 20 {
                        previousWasStopRun = false
                    }
                }

                if let previousSpeedMps, interval.accelerationAvailable {
                    let dv2 = interval.speedMps * interval.speedMps - previousSpeedMps * previousSpeedMps
                    if dv2 > 0 {
                        let severity = 1 + 0.35 * min(2, max(0, interval.accelerationMps2 - 1.0))
                        kineticSum += severity * dv2
                    } else if dv2 < 0 {
                        regenSum += -dv2
                    }
                }
                previousSpeedMps = interval.speedMps
            }
        }
        flushStopRun()
        flushConstant()
        if inHardAccel, hardAccelRun >= 1 { hardAccelCount += 1 }
        if hardBrakeRun >= 1 { hardBrakeCount += 1 }

        let observedMovingKm = movingMeters / 1_000
        let g = 9.81
        let storedDistance = max(storedDistanceMeters, 1)
        var energyIndex = kineticSum / (2 * g * storedDistance)
        if profile.regenCap > 0 {
            let recovered = min(kineticSum * profile.regenCap, regenSum)
            energyIndex = max(0, (kineticSum - recovered) / (2 * g * storedDistance))
        }

        let speedFactor: Double
        if observedMovingKm > 0 {
            speedFactor = shapeWeightedKm / observedMovingKm
        } else {
            speedFactor = 1
        }

        let sortedSpeeds = movingSpeedsKmh.sorted()
        let variability: Double
        if sortedSpeeds.count >= 3 {
            let mid = sortedSpeeds[sortedSpeeds.count / 2]
            let deviations = sortedSpeeds.map { abs($0 - mid) }.sorted()
            let mad = deviations[deviations.count / 2]
            variability = mid > 0.5 ? mad / mid : 0
        } else {
            variability = 0
        }

        let p99Accel: Double
        if accelerations.isEmpty {
            p99Accel = 0
        } else {
            let sortedA = accelerations.sorted()
            let idx = min(sortedA.count - 1, max(0, Int((Double(sortedA.count) - 1) * 0.99)))
            p99Accel = sortedA[idx]
        }

        let stopShare = duration > 0 ? min(1, stopDuration / duration) : 0
        let slowShare = movingSeconds > 0 ? low / movingSeconds : 0
        let movingAvg = movingSeconds > 0 ? observedMovingKm / (movingSeconds / 3_600) : 0
        let stopGoPerKm = stopGoCount == 0 ? 0 : Double(stopGoCount) / max(storedKm, 0.5)
        let stopShareNorm = min(1, stopShare / 0.45)
        let stopGoNorm = min(1, stopGoPerKm / 1.5)
        let speedDeficit = min(1, max(0, (35 - movingAvg) / 25))
        let variabilityNorm = min(1, variability / 0.60)
        let trafficRaw = 0.30 * stopShareNorm
            + 0.25 * stopGoNorm
            + 0.20 * slowShare
            + 0.15 * speedDeficit
            + 0.10 * variabilityNorm
        let motion = timeline.confidence
        let level: FuelTrafficLevel
        if motion < 0.5 {
            level = .unknown
        } else if trafficRaw < 0.33 {
            level = .low
        } else if trafficRaw <= 0.66 {
            level = .moderate
        } else {
            level = .heavy
        }

        return FuelTripFeatures(
            distanceKm: storedKm,
            durationSeconds: duration,
            averageSpeedKmh: duration > 0 ? storedKm / (duration / 3_600) : 0,
            movingAverageSpeedKmh: movingAvg,
            stopDurationSeconds: stopDuration,
            waitingDurationSeconds: waitingDuration,
            estimatedIdleSeconds: idleSeconds,
            stopGoCount: stopGoCount,
            stopGoPerKm: stopGoPerKm,
            accelerationEpisodeCount: accelEpisodes,
            hardAccelerationCount: hardAccelCount,
            meanPositiveAcceleration: positiveATime > 0 ? positiveASum / positiveATime : 0,
            maxAcceleration: p99Accel,
            hardBrakingCount: hardBrakeCount,
            constantSpeedSeconds: constantSeconds,
            constantSpeedMeters: constantMeters,
            constantSpeedRatio: movingSeconds > 0 ? constantSeconds / movingSeconds : 0,
            lowSpeedSeconds: low,
            mediumSpeedSeconds: medium,
            highSpeedSeconds: high,
            veryHighSpeedSeconds: veryHigh,
            speedHistogram: histogram,
            speedVariability: variability,
            trafficScore: trafficRaw,
            trafficLevel: level,
            distanceWeightedSpeedFactor: speedFactor,
            energyIndex: energyIndex,
            motionConfidence: motion,
            observedMovingKm: observedMovingKm,
            maxSpeedKmh: maxSpeedKmh,
            stopShare: stopShare,
            veryHighShare: movingSeconds > 0 ? veryHigh / movingSeconds : 0
        )
    }
}
