import CoreLocation
import XCTest
@testable import Milehound

final class TripFuelEstimateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 38.42, longitude: 27.14)
    private let c0 = 7.5
    private let price = 65.0

    func testSteadyHighwayDynamicBelowAvg() {
        let seconds = 2_000
        let speeds = Array(repeating: 90.0 / 3.6, count: seconds + 1)
        let route = samples(speedsMps: speeds)
        let distance = 90.0 / 3.6 * Double(seconds)

        let result = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertGreaterThan(result.avgVolume, 0)
        XCTAssertGreaterThan(result.dynamicVolume, 0)
        XCTAssertLessThan(result.dynamicVolume, result.avgVolume)
        XCTAssertLessThan(result.dynamicCost, result.avgCost)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testCityIdleAndHardAccelDynamicAboveAvg() {
        var speeds: [Double] = []
        speeds += Array(repeating: 0.2, count: 60)
        for _ in 0..<8 {
            speeds += ramp(fromKmh: 0, toKmh: 50, seconds: 8)
            speeds += Array(repeating: 50.0 / 3.6, count: 20)
            speeds += ramp(fromKmh: 50, toKmh: 0, seconds: 10)
            speeds += Array(repeating: 0.2, count: 40)
        }
        speeds += Array(repeating: 40.0 / 3.6, count: 30)

        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            partial + pair.0.location.distance(from: pair.1.location)
        }

        let result = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertGreaterThan(result.avgVolume, 0)
        XCTAssertGreaterThan(result.dynamicVolume, result.avgVolume)
    }

    func testZeroDistanceYieldsZeroDynamic() {
        let result = TripFuelEstimate.compute(
            samples: samples(speedsMps: [10, 10]),
            distanceMeters: 0,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        XCTAssertEqual(result.avgVolume, 0, accuracy: 0.0001)
        XCTAssertLessThan(result.dynamicVolume, 0.01)
        XCTAssertLessThan(result.dynamicCost, 1)
    }

    func testUnusableTraceFallsBackToCatalogAverage() {
        let alone = [
            RouteSample(coordinate: origin, timestamp: start, speedMps: 20)
        ]
        let result = TripFuelEstimate.compute(
            samples: alone,
            distanceMeters: 5_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        XCTAssertEqual(result.dynamicVolume, result.avgVolume, accuracy: 0.0001)
        XCTAssertEqual(result.confidence, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(result.avgVolume, 0)
    }

    func testPriceDoesNotChangeVolume() {
        let route = steadyCruise(kmh: 90, seconds: 600)
        let cheap = TripFuelEstimate.compute(
            samples: route.samples,
            distanceMeters: route.distance,
            consumptionPer100: c0,
            unitPrice: 40,
            fuelType: .petrol
        )
        let dear = TripFuelEstimate.compute(
            samples: route.samples,
            distanceMeters: route.distance,
            consumptionPer100: c0,
            unitPrice: 80,
            fuelType: .petrol
        )
        XCTAssertEqual(cheap.dynamicVolume, dear.dynamicVolume, accuracy: 0.0001)
        XCTAssertEqual(dear.dynamicCost / cheap.dynamicCost, 2, accuracy: 0.001)
    }

    func testSameProfileDifferentLengthKeepsRate() {
        let short = steadyCruise(kmh: 90, seconds: 400)
        let long = steadyCruise(kmh: 90, seconds: 20_000)
        let shortResult = TripFuelEstimate.compute(
            samples: short.samples,
            distanceMeters: short.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let longResult = TripFuelEstimate.compute(
            samples: long.samples,
            distanceMeters: long.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let shortRate = shortResult.dynamicVolume / (short.distance / 1_000) * 100
        let longRate = longResult.dynamicVolume / (long.distance / 1_000) * 100
        XCTAssertEqual(shortRate, longRate, accuracy: 0.15)
    }

    func testHigherSteadySpeedAboveEightyDoesNotLowerRate() {
        let at80 = rate(kmh: 80)
        let at100 = rate(kmh: 100)
        let at120 = rate(kmh: 120)
        let at140 = rate(kmh: 140)
        XCTAssertGreaterThan(at100, at80)
        XCTAssertGreaterThan(at120, at100)
        XCTAssertGreaterThan(at140, at120)
    }

    func testPetrolOscillationDoesNotBeatSteadyCruise() {
        let seconds = 400
        let steady = steadyCruise(kmh: 50, seconds: seconds)
        var oscillating: [Double] = []
        for index in 0...seconds {
            let kmh = 50 + 20 * sin(Double(index) / 6)
            oscillating.append(max(8, kmh) / 3.6)
        }
        let wave = samples(speedsMps: oscillating)
        let waveDistance = zip(wave.dropFirst(), wave).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let steadyResult = TripFuelEstimate.compute(
            samples: steady.samples,
            distanceMeters: steady.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let waveResult = TripFuelEstimate.compute(
            samples: wave,
            distanceMeters: waveDistance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let steadyRate = steadyResult.dynamicVolume / (steady.distance / 1_000)
        let waveRate = waveResult.dynamicVolume / (waveDistance / 1_000)
        XCTAssertGreaterThanOrEqual(waveRate, steadyRate * 0.98)
    }

    func testObservedTrafficUsesMoreThanSmoothSameDistance() {
        let smooth = steadyCruise(kmh: 40, seconds: 270)
        var trafficSpeeds: [Double] = []
        while trafficSpeeds.count < 1_800 {
            trafficSpeeds += ramp(fromKmh: 0, toKmh: 25, seconds: 6)
            trafficSpeeds += Array(repeating: 20.0 / 3.6, count: 8)
            trafficSpeeds += ramp(fromKmh: 25, toKmh: 0, seconds: 6)
            trafficSpeeds += Array(repeating: 0.15, count: 50)
        }
        trafficSpeeds = Array(trafficSpeeds.prefix(1_801))
        let traffic = samples(speedsMps: trafficSpeeds)
        let trafficDistance = zip(traffic.dropFirst(), traffic).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let smoothResult = TripFuelEstimate.compute(
            samples: smooth.samples,
            distanceMeters: max(trafficDistance, 1),
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol
        )
        let trafficResult = TripFuelEstimate.compute(
            samples: traffic,
            distanceMeters: trafficDistance,
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertGreaterThan(trafficResult.dynamicVolume, smoothResult.dynamicVolume)
    }

    func testLongUnobservedGapDoesNotChargeIdle() {
        let moving = samples(speedsMps: Array(repeating: 50.0 / 3.6, count: 61))
        let resumed = samples(
            speedsMps: Array(repeating: 50.0 / 3.6, count: 61),
            startAt: start.addingTimeInterval(60 + 20 * 60)
        )
        let withGap = moving + resumed
        let distance = zip(withGap.dropFirst(), withGap).reduce(0.0) { partial, pair in
            let dt = pair.0.timestamp.timeIntervalSince(pair.1.timestamp)
            if dt > TripMotionThresholds.maximumAccelIntervalSeconds { return partial }
            return partial + pair.0.location.distance(from: pair.1.location)
        }
        let gapped = TripFuelEstimate.compute(
            samples: withGap,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let continuous = steadyCruise(kmh: 50, seconds: 120)
        let plain = TripFuelEstimate.compute(
            samples: continuous.samples,
            distanceMeters: continuous.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertEqual(gapped.dynamicVolume, plain.dynamicVolume, accuracy: plain.dynamicVolume * 0.12)
        XCTAssertLessThan(gapped.confidence, plain.confidence)
    }

    func testUserPauseStopIsExcludedFromIdle() {
        let before = samples(speedsMps: Array(repeating: 40.0 / 3.6, count: 31))
        let during = samples(
            speedsMps: Array(repeating: 0.2, count: 61),
            startAt: start.addingTimeInterval(30)
        )
        let after = samples(
            speedsMps: Array(repeating: 40.0 / 3.6, count: 31),
            startAt: start.addingTimeInterval(91)
        )
        let route = before + during + after
        let distance = zip(route.dropFirst(), route).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let pause = TripFuelMotionTimeline.ExcludedStop(
            startedAt: start.addingTimeInterval(30),
            duration: 60
        )
        let withPause = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            excludedStops: [pause]
        )
        let withoutPause = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertLessThan(withPause.dynamicVolume, withoutPause.dynamicVolume)
    }

    func testMergeGapDoesNotInflateAccelFuel() {
        let first = samples(speedsMps: Array(repeating: 40.0 / 3.6, count: 61))
        let gapStart = start.addingTimeInterval(60)
        let afterGap = samples(
            speedsMps: Array(repeating: 40.0 / 3.6, count: 61),
            startAt: gapStart.addingTimeInterval(2 * 3_600)
        )
        let route = first + afterGap
        let distance = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            let dt = pair.0.timestamp.timeIntervalSince(pair.1.timestamp)
            if dt > TripFuelEstimate.maximumStopGapSeconds { return partial }
            return partial + pair.0.location.distance(from: pair.1.location)
        }

        let withGap = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let continuous = TripFuelEstimate.compute(
            samples: samples(speedsMps: Array(repeating: 40.0 / 3.6, count: 121)),
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )

        XCTAssertEqual(withGap.dynamicVolume, continuous.dynamicVolume, accuracy: continuous.dynamicVolume * 0.15)
    }

    func testDistanceMismatchPullsTowardCatalogAverage() {
        let route = steadyCruise(kmh: 140, seconds: 600)
        let honest = TripFuelEstimate.compute(
            samples: route.samples,
            distanceMeters: route.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let mismatched = TripFuelEstimate.compute(
            samples: route.samples,
            distanceMeters: route.distance * 4,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertLessThan(mismatched.confidence, honest.confidence)
        let honestRatio = honest.dynamicVolume / honest.avgVolume
        let mismatchRatio = mismatched.dynamicVolume / mismatched.avgVolume
        XCTAssertLessThan(abs(mismatchRatio - 1), abs(honestRatio - 1))
    }

    func testEVIdleMuchLessThanPetrol() {
        var speeds = Array(repeating: 0.2, count: 90)
        speeds += Array(repeating: 40.0 / 3.6, count: 121)
        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            partial + pair.0.location.distance(from: pair.1.location)
        }

        let petrol = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let electric = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .electric
        )
        XCTAssertGreaterThan(petrol.dynamicVolume, electric.dynamicVolume)
        XCTAssertGreaterThan(petrol.dynamicVolume, 0)
        XCTAssertGreaterThan(electric.dynamicVolume, 0)
    }

    func testHybridRegenDoesNotExceedTractionReserve() {
        var speeds: [Double] = Array(repeating: 10.0 / 3.6, count: 5)
        speeds += ramp(fromKmh: 10, toKmh: 80, seconds: 20)
        speeds += ramp(fromKmh: 80, toKmh: 10, seconds: 25)
        speeds += Array(repeating: 10.0 / 3.6, count: 5)
        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let hybrid = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .hybrid
        )
        XCTAssertGreaterThan(hybrid.dynamicVolume, 0)
        XCTAssertGreaterThan(hybrid.dynamicVolume, hybrid.avgVolume * 0.4)
    }

    func testDoubleConsumptionNearlyDoublesDynamicVolume() {
        let trip = steadyCruise(kmh: 70, seconds: 600)
        let base = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: 7.5,
            unitPrice: price,
            fuelType: .petrol
        )
        let double = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: 15,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertEqual(double.dynamicVolume / base.dynamicVolume, 2, accuracy: 0.05)
        XCTAssertEqual(double.avgVolume / base.avgVolume, 2, accuracy: 0.001)
    }

    func testLinearPreviewMatchesRecomputeWithinOnePercent() {
        let trip = steadyCruise(kmh: 85, seconds: 500)
        let stored = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: 7.5,
            unitPrice: 65,
            fuelType: .petrol
        )
        let edited = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: 10,
            unitPrice: 70,
            fuelType: .petrol
        )
        let preview = stored.dynamicCost * (10 / 7.5) * (70 / 65)
        XCTAssertEqual(preview, edited.dynamicCost, accuracy: edited.dynamicCost * 0.01)
    }

    func testSplitAndConcatPreserveTotal() {
        let full = steadyCruise(kmh: 80, seconds: 800)
        let mid = start.addingTimeInterval(400)
        let first = full.samples.filter { $0.timestamp <= mid }
        let second = full.samples.filter { $0.timestamp >= mid }
        let firstDistance = zip(first.dropFirst(), first).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let secondDistance = zip(second.dropFirst(), second).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let whole = TripFuelEstimate.compute(
            samples: full.samples,
            distanceMeters: full.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let partA = TripFuelEstimate.compute(
            samples: first,
            distanceMeters: firstDistance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let partB = TripFuelEstimate.compute(
            samples: second,
            distanceMeters: secondDistance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertEqual(partA.dynamicVolume + partB.dynamicVolume, whole.dynamicVolume, accuracy: whole.dynamicVolume * 0.08)
    }

    func testLongRouteSixThousandSamplesProducesStableDynamicVolume() {
        let started = Date()
        let route = steadyCruise(kmh: 70, seconds: 6_000)
        let result = TripFuelEstimate.compute(
            samples: route.samples,
            distanceMeters: route.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertGreaterThan(result.dynamicVolume, 0)
        XCTAssertGreaterThan(result.avgVolume, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testComputeFromTripPointsMatchesSamples() {
        let trip = steadyCruise(kmh: 80, seconds: 120)
        let fromSamples = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let points: [TripPoint] = trip.samples.enumerated().map { index, sample in
            TripPoint(
                timestamp: sample.timestamp,
                latitude: sample.coordinate.latitude,
                longitude: sample.coordinate.longitude,
                sequence: index,
                speedMps: sample.speedMps
            )
        }
        let fromPoints = TripFuelEstimate.compute(
            points: points,
            distanceMeters: trip.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertEqual(fromPoints.dynamicVolume, fromSamples.dynamicVolume, accuracy: 0.0001)
    }

    func testDieselIdleLowerThanPetrolOnSameStopStretch() {
        var speeds = Array(repeating: 0.2, count: 80)
        speeds += Array(repeating: 30.0 / 3.6, count: 60)
        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let petrol = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let diesel = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .diesel
        )
        XCTAssertLessThan(diesel.dynamicVolume, petrol.dynamicVolume)
    }

    func testObservedIdleCreditRemainsConservativeAfterTenMinutes() {
        XCTAssertEqual(TripFuelMotionTimeline.engineOnProbability(forRunDuration: 60), 0.85, accuracy: 0.001)
        XCTAssertEqual(TripFuelMotionTimeline.engineOnProbability(forRunDuration: 120), 0.85, accuracy: 0.001)
        XCTAssertEqual(TripFuelMotionTimeline.engineOnProbability(forRunDuration: 600), 0.65, accuracy: 0.001)
        XCTAssertEqual(TripFuelMotionTimeline.engineOnProbability(forRunDuration: 45 * 60), 0.20, accuracy: 0.001)
        XCTAssertEqual(
            TripFuelMotionTimeline.idleCreditSeconds(forRunDuration: 60),
            60 * 0.85,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TripFuelMotionTimeline.idleCreditSeconds(forRunDuration: 1_200),
            1_200 * TripFuelMotionTimeline.engineOnProbability(forRunDuration: 1_200),
            accuracy: 0.001
        )
    }

    func testDenseObservedQueueContinuesAddingConservativeIdle() {
        func route(idleSeconds: Int) -> (samples: [RouteSample], distance: Double) {
            var speeds = Array(repeating: 40.0 / 3.6, count: 31)
            speeds += Array(repeating: 0.2, count: idleSeconds)
            speeds += Array(repeating: 40.0 / 3.6, count: 31)
            let route = samples(speedsMps: speeds)
            let distance = zip(route.dropFirst(), route).reduce(0.0) {
                $0 + $1.0.location.distance(from: $1.1.location)
            }
            return (route, distance)
        }
        let short = route(idleSeconds: 60)
        let parked = route(idleSeconds: 600)
        let shortResult = TripFuelEstimate.compute(
            samples: short.samples,
            distanceMeters: short.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let parkedResult = TripFuelEstimate.compute(
            samples: parked.samples,
            distanceMeters: parked.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let extra = parkedResult.dynamicVolume - shortResult.dynamicVolume
        XCTAssertGreaterThan(parkedResult.dynamicVolume, shortResult.dynamicVolume)
        XCTAssertGreaterThan(extra, 0)
        XCTAssertLessThan(parkedResult.dynamicVolume, shortResult.dynamicVolume * 3)
    }

    /// Mirrors the supplied short city trip without fitting to its reported 10 L/100 km:
    /// 3.3 km moving for 6:15, with a 5:50 low-speed interval bounded by valid movement.
    func testShortCityTripWithSparseFiveMinuteStopIsAboveCatalogAverage() {
        let city = shortCityTripRoute()
        let timeline = TripFuelMotionTimeline.build(
            samples: city.samples,
            storedDistanceMeters: city.distance
        )
        let result = TripFuelEstimate.compute(
            samples: city.samples,
            distanceMeters: city.distance,
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertGreaterThan(timeline.observedStopSeconds, 180)
        XCTAssertGreaterThan(result.dynamicVolume, result.avgVolume)
        XCTAssertGreaterThan(result.dynamicVolume / (city.distance / 1_000) * 100, 7)
    }

    /// Auto-detected parking is a Stop pin after 2 minutes below 2 km/h. The recorder also
    /// drops stationary fixes, so that pin sits on the same 5:50 GPS hole as a traffic queue.
    /// Production must not treat the pin as engine-off — that is why Est. sat below Avg.
    func testShortCityTripStaysAboveAverageEvenWithParkingPinOnTheGap() {
        let city = shortCityTripRoute()
        let pin = TripFuelMotionTimeline.ExcludedStop(
            startedAt: start.addingTimeInterval(188),
            duration: 350
        )
        let withPinIgnored = TripFuelEstimate.compute(
            samples: city.samples,
            distanceMeters: city.distance,
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol
        )
        let pinTreatedAsEngineOff = TripFuelEstimate.compute(
            samples: city.samples,
            distanceMeters: city.distance,
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol,
            excludedStops: [pin]
        )

        XCTAssertGreaterThan(withPinIgnored.dynamicVolume, withPinIgnored.avgVolume)
        XCTAssertGreaterThan(withPinIgnored.dynamicVolume, pinTreatedAsEngineOff.dynamicVolume)
    }

    func testTeleportAndDistanceMismatchPullTowardCatalog() {
        let honest = steadyCruise(kmh: 90, seconds: 400)
        var noisy = honest.samples
        let jump = noisy[200]
        noisy[200] = RouteSample(
            coordinate: offset(from: jump.coordinate, metersEast: 8_000),
            timestamp: jump.timestamp,
            speedMps: 80
        )
        let clean = TripFuelEstimate.compute(
            samples: honest.samples,
            distanceMeters: honest.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let warped = TripFuelEstimate.compute(
            samples: noisy,
            distanceMeters: honest.distance * 3,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertLessThan(warped.confidence, clean.confidence)
        let cleanRatio = abs(clean.dynamicVolume / clean.avgVolume - 1)
        let warpedRatio = abs(warped.dynamicVolume / warped.avgVolume - 1)
        XCTAssertLessThan(warpedRatio, cleanRatio + 0.02)
    }

    func testSparseAndDenseSamplingStayClose() {
        let dense = steadyCruise(kmh: 80, seconds: 400)
        let sparseSpeeds = stride(from: 0, through: 400, by: 5).map { _ in 80.0 / 3.6 }
        var travelled = 0.0
        let sparse: [RouteSample] = sparseSpeeds.enumerated().map { index, speed in
            if index > 0 { travelled += speed * 5 }
            return RouteSample(
                coordinate: offset(from: origin, metersEast: travelled),
                timestamp: start.addingTimeInterval(Double(index * 5)),
                speedMps: speed
            )
        }
        let denseResult = TripFuelEstimate.compute(
            samples: dense.samples,
            distanceMeters: dense.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let sparseResult = TripFuelEstimate.compute(
            samples: sparse,
            distanceMeters: 80.0 / 3.6 * 400,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let denseRate = denseResult.dynamicVolume / (dense.distance / 1_000)
        let sparseRate = sparseResult.dynamicVolume / (80.0 / 3.6 * 400 / 1_000)
        XCTAssertEqual(denseRate, sparseRate, accuracy: denseRate * 0.08)
    }

    func testMissingCatalogConsumptionReturnsZeros() {
        let trip = steadyCruise(kmh: 50, seconds: 120)
        let result = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: 0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertEqual(result.avgVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(result.dynamicVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(result.dynamicCost, 0, accuracy: 0.0001)
    }

    func testMixedWarmTripStaysNearCatalogAverage() {
        var speeds: [Double] = []
        speeds += Array(repeating: 40.0 / 3.6, count: 400)
        speeds += Array(repeating: 70.0 / 3.6, count: 400)
        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        let result = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(ratio, 0.95)
        XCTAssertLessThan(ratio, 1.10)
        XCTAssertEqual(result.avgVolume, distance / 1_000 * c0 / 100, accuracy: 0.0001)
    }

    func testTwoKilometreQueueIsOnePointFiveToTwoPointThreeTimesCatalog() {
        let traffic = trafficRoute(targetMeters: 2_000, targetSeconds: 900)
        let result = TripFuelEstimate.compute(
            samples: traffic.samples,
            distanceMeters: traffic.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(result.dynamicVolume, result.avgVolume)
        XCTAssertGreaterThan(ratio, 1.5)
        XCTAssertLessThanOrEqual(ratio, 2.3)
    }

    func testTwoKilometreFlowingColdStartIsAboveCatalog() {
        let flowing = steadyCruise(kmh: 40, seconds: 180)
        let result = TripFuelEstimate.compute(
            samples: flowing.samples,
            distanceMeters: 2_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: coldSoak
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(ratio, 1.3)
        XCTAssertLessThan(ratio, 1.7)
    }

    func testTwentyKilometreCityTrafficIsAboveCatalog() {
        let traffic = trafficRoute(targetMeters: 20_000, targetSeconds: 3_300)
        let result = TripFuelEstimate.compute(
            samples: traffic.samples,
            distanceMeters: traffic.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(ratio, 1.3)
        XCTAssertLessThan(ratio, 1.7)
    }

    func testTwentyKilometreFlowingCityStaysNearCatalog() {
        let city = steadyCruise(kmh: 45, seconds: 1_600)
        let result = TripFuelEstimate.compute(
            samples: city.samples,
            distanceMeters: city.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(ratio, 0.95)
        XCTAssertLessThan(ratio, 1.20)
    }

    func testHundredKilometreHighwayEightyFiveIsBelowCatalog() {
        let highway = steadyCruise(kmh: 85, seconds: 4_235)
        let result = TripFuelEstimate.compute(
            samples: highway.samples,
            distanceMeters: highway.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(ratio, 0.80)
        XCTAssertLessThan(ratio, 0.90)
        XCTAssertEqual(result.avgVolume, highway.distance / 1_000 * c0 / 100, accuracy: 0.0001)
    }

    func testHundredKilometreHighwayOneTwentyIsAboveCatalog() {
        let highway = steadyCruise(kmh: 120, seconds: 3_000)
        let result = TripFuelEstimate.compute(
            samples: highway.samples,
            distanceMeters: highway.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let ratio = (result.ratePer100 ?? 0) / c0
        XCTAssertGreaterThan(ratio, 1.15)
        XCTAssertLessThan(ratio, 1.40)
    }

    func testSameTraceRateOverCatalogIsInvariantToC0() {
        let traffic = trafficRoute(targetMeters: 8_000, targetSeconds: 1_200)
        let low = TripFuelEstimate.compute(
            samples: traffic.samples,
            distanceMeters: traffic.distance,
            consumptionPer100: 5,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let high = TripFuelEstimate.compute(
            samples: traffic.samples,
            distanceMeters: traffic.distance,
            consumptionPer100: 10,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let lowRatio = (low.ratePer100 ?? 0) / 5
        let highRatio = (high.ratePer100 ?? 0) / 10
        XCTAssertEqual(lowRatio, highRatio, accuracy: 0.03)
        XCTAssertEqual(high.dynamicVolume / low.dynamicVolume, 2, accuracy: 0.06)
        XCTAssertEqual(high.avgVolume / low.avgVolume, 2, accuracy: 0.001)
    }

    func testLongerSoakIncreasesColdStartLitres() {
        let short = steadyCruise(kmh: 40, seconds: 180)
        let afterFiveMinutes = TripFuelEstimate.compute(
            samples: short.samples,
            distanceMeters: 2_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: FuelThermalInput(
                previousEndedAt: start.addingTimeInterval(-5 * 60),
                previousMovingMinutes: 40,
                previousDistanceKm: 25,
                tripStartedAt: start,
                hasVehicleContinuity: true
            )
        )
        let afterEightHours = TripFuelEstimate.compute(
            samples: short.samples,
            distanceMeters: 2_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: coldSoak
        )
        XCTAssertGreaterThan(afterEightHours.breakdown.coldStartLitres, afterFiveMinutes.breakdown.coldStartLitres)
        XCTAssertGreaterThan(afterEightHours.dynamicVolume, afterFiveMinutes.dynamicVolume)
    }

    func testStopPinDoesNotRemoveQueueIdle() {
        let city = shortCityTripRoute()
        let pin = TripFuelMotionTimeline.ExcludedStop(
            startedAt: start.addingTimeInterval(188),
            duration: 350
        )
        let production = TripFuelEstimate.compute(
            samples: city.samples,
            distanceMeters: city.distance,
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let pinAsEngineOff = TripFuelEstimate.compute(
            samples: city.samples,
            distanceMeters: city.distance,
            consumptionPer100: 7,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine,
            excludedStops: [pin]
        )
        XCTAssertGreaterThan(production.dynamicVolume, production.avgVolume)
        XCTAssertGreaterThan((production.ratePer100 ?? 0) / 7, 1.0)
        XCTAssertGreaterThan(production.dynamicVolume, pinAsEngineOff.dynamicVolume)
    }

    func testCalibrationBiasAppliesAfterFiveSamples() {
        let trip = steadyCruise(kmh: 70, seconds: 600)
        let identity = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let unused = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine,
            calibration: FuelCalibrationSnapshot(bias: 1.2, acceptedCount: 4)
        )
        let applied = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine,
            calibration: FuelCalibrationSnapshot(bias: 1.2, acceptedCount: 5)
        )
        XCTAssertEqual(unused.dynamicVolume, identity.dynamicVolume, accuracy: 0.0001)
        XCTAssertEqual(applied.dynamicVolume / identity.dynamicVolume, 1.2, accuracy: 0.02)
    }

    func testMoreIdleDoesNotLowerLitres() {
        let short = routeWithIdle(idleSeconds: 60)
        let longIdle = routeWithIdle(idleSeconds: 400)
        let shortResult = TripFuelEstimate.compute(
            samples: short.samples,
            distanceMeters: short.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        let longResult = TripFuelEstimate.compute(
            samples: longIdle.samples,
            distanceMeters: longIdle.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        XCTAssertGreaterThan(longResult.dynamicVolume, shortResult.dynamicVolume)
        XCTAssertEqual(shortResult.avgVolume, longResult.avgVolume, accuracy: 0.05)
    }

    // MARK: - Helpers

    private var warmEngine: FuelThermalInput {
        FuelThermalInput(
            previousEndedAt: start.addingTimeInterval(-5 * 60),
            previousMovingMinutes: 40,
            previousDistanceKm: 25,
            tripStartedAt: start,
            hasVehicleContinuity: true
        )
    }

    private var coldSoak: FuelThermalInput {
        FuelThermalInput(
            previousEndedAt: start.addingTimeInterval(-8 * 3_600),
            previousMovingMinutes: 12,
            previousDistanceKm: 4,
            tripStartedAt: start,
            hasVehicleContinuity: true
        )
    }

    private func trafficRoute(targetMeters: Double, targetSeconds: Int) -> (samples: [RouteSample], distance: Double) {
        let idleFraction = targetMeters <= 2_500 ? 0.62 : 0.48
        let movingSeconds = max(30, Int(Double(targetSeconds) * (1 - idleFraction)))
        let idleSeconds = max(0, targetSeconds - movingSeconds)
        let movingSpeed = (targetMeters / Double(movingSeconds))
        let cycleMoving = max(12, movingSeconds / 12)
        let cycleIdle = max(8, idleSeconds / 12)
        var speeds: [Double] = []
        var remainingMoving = movingSeconds
        var remainingIdle = idleSeconds
        while remainingMoving > 0 || remainingIdle > 0 {
            let move = min(cycleMoving, remainingMoving)
            if move > 0 {
                speeds += ramp(fromKmh: 0, toKmh: movingSpeed * 3.6, seconds: min(6, move))
                let cruise = max(0, move - min(6, move))
                if cruise > 0 {
                    speeds += Array(repeating: movingSpeed, count: cruise)
                }
                remainingMoving -= move
            }
            let idle = min(cycleIdle, remainingIdle)
            if idle > 0 {
                speeds += Array(repeating: 0.15, count: idle)
                remainingIdle -= idle
            }
            if speeds.count > targetSeconds + 20 { break }
        }
        if speeds.isEmpty { speeds = [movingSpeed] }
        let route = samples(speedsMps: speeds)
        return (route, targetMeters)
    }

    private func routeWithIdle(idleSeconds: Int) -> (samples: [RouteSample], distance: Double) {
        var speeds = Array(repeating: 40.0 / 3.6, count: 31)
        speeds += Array(repeating: 0.2, count: idleSeconds)
        speeds += Array(repeating: 40.0 / 3.6, count: 31)
        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) {
            $0 + $1.0.location.distance(from: $1.1.location)
        }
        return (route, distance)
    }

    private func shortCityTripRoute() -> (samples: [RouteSample], distance: Double) {
        let distance = 3_300.0
        let movingSeconds = 375
        let stopSeconds = 350
        let speedMps = distance / Double(movingSeconds)
        let firstMovingSeconds = 188
        let secondMovingSeconds = movingSeconds - firstMovingSeconds
        let before = samples(
            speedsMps: Array(repeating: speedMps, count: firstMovingSeconds + 1)
        )
        let after = samples(
            speedsMps: Array(repeating: speedMps, count: secondMovingSeconds + 1),
            startAt: start.addingTimeInterval(Double(firstMovingSeconds + stopSeconds)),
            startFrom: before.last?.coordinate
        )
        return (before + after, distance)
    }

    private func rate(kmh: Double) -> Double {
        let trip = steadyCruise(kmh: kmh, seconds: 800)
        let result = TripFuelEstimate.compute(
            samples: trip.samples,
            distanceMeters: trip.distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol,
            thermal: warmEngine
        )
        return result.dynamicVolume / (trip.distance / 1_000)
    }

    private func steadyCruise(kmh: Double, seconds: Int) -> (samples: [RouteSample], distance: Double) {
        let speeds = Array(repeating: kmh / 3.6, count: seconds + 1)
        let route = samples(speedsMps: speeds)
        let distance = kmh / 3.6 * Double(seconds)
        return (route, distance)
    }

    private func ramp(fromKmh: Double, toKmh: Double, seconds: Int) -> [Double] {
        guard seconds > 0 else { return [] }
        return (0...seconds).map { step in
            let t = Double(step) / Double(seconds)
            return (fromKmh + (toKmh - fromKmh) * t) / 3.6
        }
    }

    private func samples(
        speedsMps: [Double],
        storeSpeeds: Bool = true,
        startAt: Date? = nil,
        startFrom: CLLocationCoordinate2D? = nil
    ) -> [RouteSample] {
        let originTime = startAt ?? start
        let from = startFrom ?? origin
        var travelled = 0.0
        return speedsMps.enumerated().map { index, speed in
            if index > 0 { travelled += speed }
            return RouteSample(
                coordinate: offset(from: from, metersEast: travelled),
                timestamp: originTime.addingTimeInterval(Double(index)),
                speedMps: storeSpeeds ? speed : nil
            )
        }
    }

    private func offset(from coordinate: CLLocationCoordinate2D, metersEast: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude + metersEast / metersPerDegreeLongitude
        )
    }
}
