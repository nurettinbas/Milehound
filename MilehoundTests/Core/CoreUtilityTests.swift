import CoreLocation
import SwiftData
import SwiftUI
import XCTest
@testable import Milehound

final class DistanceCalculatorTests: XCTestCase {
    func testTotalDistanceWithTwoPoints() {
        let a = CLLocation(latitude: 0, longitude: 0)
        let b = CLLocation(latitude: 0, longitude: 0.01)
        let distance = DistanceCalculator.totalDistance(for: [a, b])
        XCTAssertGreaterThan(distance, 0)
    }

    func testSimplifyReducesPoints() {
        let points = (0..<20).map { index in
            CLLocationCoordinate2D(latitude: Double(index) * 0.001, longitude: Double(index) * 0.001)
        }
        let simplified = DistanceCalculator.simplify(coordinates: points)
        XCTAssertLessThan(simplified.count, points.count)
    }

    func testMeterToleranceKeepsDeviationsAboveIt() {
        // 100 m eastward leg with a ~20 m northward bulge in the middle.
        let latitude = 38.42
        let metersPerDegreeLatitude: Double = 111_132
        let metersPerDegreeLongitude = 111_320 * cos(latitude * .pi / 180)
        let points = [
            CLLocationCoordinate2D(latitude: latitude, longitude: 27.0),
            CLLocationCoordinate2D(
                latitude: latitude + 20 / metersPerDegreeLatitude,
                longitude: 27.0 + 50 / metersPerDegreeLongitude
            ),
            CLLocationCoordinate2D(latitude: latitude, longitude: 27.0 + 100 / metersPerDegreeLongitude)
        ]

        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 5).count, 3)
        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 40).count, 2)
    }

    func testMeterToleranceMeasuresLongitudeInMetersNotDegrees() {
        // Same 20 m bulge, but expressed eastward. A degree-space tolerance would judge this
        // deviation ~27% smaller at this latitude; the meter-based one must not.
        let latitude = 38.42
        let metersPerDegreeLatitude: Double = 111_132
        let metersPerDegreeLongitude = 111_320 * cos(latitude * .pi / 180)
        let points = [
            CLLocationCoordinate2D(latitude: latitude, longitude: 27.0),
            CLLocationCoordinate2D(
                latitude: latitude + 50 / metersPerDegreeLatitude,
                longitude: 27.0 + 20 / metersPerDegreeLongitude
            ),
            CLLocationCoordinate2D(latitude: latitude + 100 / metersPerDegreeLatitude, longitude: 27.0)
        ]

        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 15).count, 3)
        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 25).count, 2)
    }

    func testSimplifiedIndicesKeepEndpoints() {
        let points = (0..<50).map { index in
            CLLocationCoordinate2D(latitude: 38.42, longitude: 27.0 + Double(index) * 0.0001)
        }
        let indices = DistanceCalculator.simplifiedIndices(coordinates: points, toleranceMeters: 3)

        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, points.count - 1)
        XCTAssertEqual(indices, indices.sorted())
    }
}

final class RoutePrivacyClipperTests: XCTestCase {
    func testClipsStartAndEndWithinRadius() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let mid = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        let end = CLLocationCoordinate2D(latitude: 41.02, longitude: 29.02)
        let nearStart = CLLocationCoordinate2D(latitude: 41.0001, longitude: 29.0001)
        let nearEnd = CLLocationCoordinate2D(latitude: 41.0199, longitude: 29.0199)
        let clipped = RoutePrivacyClipper.clip(
            [start, nearStart, mid, nearEnd, end],
            privacyRadiusMeters: 500
        )
        XCTAssertLessThan(clipped.count, 5)
        XCTAssertGreaterThanOrEqual(clipped.count, 2)
    }
}

final class TripDateGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    func testGroupsTodayTrip() {
        let trip = Trip(startedAt: Date(), endedAt: Date())
        let sections = TripDateGrouping.groupedSections(from: [trip])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.section, .today)
    }

    func testThisWeekFilterIncludesToday() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 15))!
        XCTAssertEqual(TripDateGrouping.section(for: now, calendar: calendar, now: now), .today)
        XCTAssertTrue(TripDateGrouping.matches(.today, date: now, calendar: calendar, now: now))
        XCTAssertTrue(TripDateGrouping.matches(.thisWeek, date: now, calendar: calendar, now: now))
        XCTAssertTrue(TripDateGrouping.matches(.thisMonth, date: now, calendar: calendar, now: now))
        XCTAssertFalse(TripDateGrouping.matches(.yesterday, date: now, calendar: calendar, now: now))
        XCTAssertFalse(TripDateGrouping.matches(.older, date: now, calendar: calendar, now: now))
    }

    func testThisWeekFilterIncludesEarlierDayInSameWeek() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 15))! // Wed
        let monday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9))!
        XCTAssertEqual(TripDateGrouping.section(for: monday, calendar: calendar, now: now), .thisWeek)
        XCTAssertTrue(TripDateGrouping.matches(.thisWeek, date: monday, calendar: calendar, now: now))
        XCTAssertTrue(TripDateGrouping.matches(.thisMonth, date: monday, calendar: calendar, now: now))
        XCTAssertFalse(TripDateGrouping.matches(.today, date: monday, calendar: calendar, now: now))
    }

    func testThisMonthFilterIncludesEarlierWeekInSameMonth() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))! // Wed
        let earlyAugust = calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 10))!
        XCTAssertEqual(TripDateGrouping.section(for: earlyAugust, calendar: calendar, now: now), .thisMonth)
        XCTAssertTrue(TripDateGrouping.matches(.thisMonth, date: earlyAugust, calendar: calendar, now: now))
        XCTAssertFalse(TripDateGrouping.matches(.thisWeek, date: earlyAugust, calendar: calendar, now: now))
    }
}

@MainActor
final class TabSelectionTests: XCTestCase {
    func testOpenPairingSelectsPairingTab() {
        let tabs = TabSelection.shared
        tabs.selectedTab = .trips
        tabs.openPairing()
        XCTAssertEqual(tabs.selectedTab, .pairing)
    }

    func testOpenVehicleCareSetsPendingID() {
        let tabs = TabSelection.shared
        tabs.selectedTab = .trips
        let id = UUID()
        tabs.openVehicleCare(vehicleID: id)
        XCTAssertEqual(tabs.selectedTab, .pairing)
        XCTAssertEqual(tabs.consumePendingVehicleCareID(), id)
        XCTAssertNil(tabs.consumePendingVehicleCareID())
    }

    func testOpenStatsAchievementsAndRecap() {
        let tabs = TabSelection.shared
        tabs.selectedTab = .trips
        tabs.openStats(anchor: .achievements)
        XCTAssertEqual(tabs.selectedTab, .year)
        XCTAssertEqual(tabs.consumePendingStatsAnchor(), .achievements)
        tabs.openStats(anchor: .recap)
        XCTAssertEqual(tabs.selectedTab, .year)
        XCTAssertEqual(tabs.consumePendingStatsAnchor(), .recap)
        tabs.openStats(anchor: .forecast)
        XCTAssertEqual(tabs.selectedTab, .year)
        XCTAssertEqual(tabs.consumePendingStatsAnchor(), .forecast)
        tabs.openStats(anchor: .routes)
        XCTAssertEqual(tabs.selectedTab, .year)
        XCTAssertEqual(tabs.consumePendingStatsAnchor(), .routes)
    }

    func testOpenStatsGoalStaysOnStatistics() {
        let tabs = TabSelection.shared
        tabs.selectedTab = .trips
        tabs.openStats(anchor: .goal)
        XCTAssertEqual(tabs.selectedTab, .stats)
        XCTAssertEqual(tabs.consumePendingStatsAnchor(), .goal)
    }

    func testOpenTripSetsPendingID() {
        let tabs = TabSelection.shared
        tabs.selectedTab = .stats
        let id = UUID()
        tabs.openTrip(id: id)
        XCTAssertEqual(tabs.selectedTab, .trips)
        XCTAssertEqual(tabs.consumePendingTripID(), id)
        XCTAssertNil(tabs.consumePendingTripID())
    }

    func testShowFinishedTripReplacesTheStackWithOneTrip() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let trip = Trip(endedAt: Date())
        container.mainContext.insert(trip)
        let tabs = TabSelection.shared
        tabs.tripsPath = NavigationPath()
        tabs.showFinishedTrip(trip)
        tabs.showFinishedTrip(trip)
        XCTAssertEqual(tabs.tripsPath.count, 1)
        tabs.tripsPath = NavigationPath()
    }
}

@MainActor
final class TripDeepLinkResolverTests: XCTestCase {
    func testFinishedRecordingUnfinishedAndMissing() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let finished = Trip(endedAt: Date())
        let live = Trip()
        context.insert(finished)
        context.insert(live)

        XCTAssertEqual(
            TripDeepLinkResolver.resolve(tripID: finished.id, in: context, activeTripID: nil),
            .finished(finished)
        )
        XCTAssertEqual(
            TripDeepLinkResolver.resolve(tripID: live.id, in: context, activeTripID: live.id),
            .recording
        )
        XCTAssertEqual(
            TripDeepLinkResolver.resolve(tripID: live.id, in: context, activeTripID: nil),
            .unfinished
        )
        XCTAssertEqual(
            TripDeepLinkResolver.resolve(tripID: UUID(), in: context, activeTripID: nil),
            .missing
        )
    }
}

final class DeviceTestChecklistTests: XCTestCase {
    func testChecklistCoversLongTripDetailPerformance() {
        XCTAssertGreaterThanOrEqual(DeviceTestChecklist.items.count, 9)
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("colorSegs") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("disk cache") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("Shortcuts: Start trip Vehicle") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("Live follow map") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("Reduce Motion") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("3D/2D") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("hold-back") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("growing tail tip") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("same thickness in 2D and 3D") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("recenter") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("overview") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("chevron sharp tip") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("camera pulls back") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("CarPlay Live Activity tile") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("CarPlay phone call") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("Travel time") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("Avg fuel calculate") }))
        XCTAssertTrue(DeviceTestChecklist.items.contains(where: { $0.contains("period % chips") }))
    }
}

@MainActor
final class AppSettingsLiveFollowMapTests: XCTestCase {
    func testLiveFollowMap3DDefaultsOnAndPersists() {
        let suiteName = "test.milehound.liveFollowMap3D.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        XCTAssertTrue(settings.liveFollowMap3DEnabled)

        settings.liveFollowMap3DEnabled = false
        XCTAssertFalse(settings.liveFollowMap3DEnabled)
        XCTAssertEqual(defaults.object(forKey: "recording.liveFollowMap3DEnabled") as? Bool, false)

        let reloaded = AppSettings(userDefaults: defaults)
        XCTAssertFalse(reloaded.liveFollowMap3DEnabled)

        reloaded.liveFollowMap3DEnabled = true
        XCTAssertTrue(reloaded.liveFollowMap3DEnabled)
    }
}

@MainActor
final class AppSettingsAppearanceModeTests: XCTestCase {
    func testAppearanceDefaultsToSystemAndPersists() {
        let suiteName = "test.milehound.appearanceMode.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertNil(settings.appearanceMode.preferredColorScheme)

        settings.appearanceMode = .dark
        XCTAssertEqual(settings.appearanceMode, .dark)
        XCTAssertEqual(settings.appearanceMode.preferredColorScheme, .dark)
        XCTAssertEqual(defaults.string(forKey: "appearanceMode"), "dark")

        let reloaded = AppSettings(userDefaults: defaults)
        XCTAssertEqual(reloaded.appearanceMode, .dark)

        reloaded.appearanceMode = .light
        XCTAssertEqual(reloaded.appearanceMode.preferredColorScheme, .light)

        reloaded.appearanceMode = .system
        XCTAssertNil(reloaded.appearanceMode.preferredColorScheme)
    }

    func testShellPaletteDefaultsToSkyAndPersists() {
        let suiteName = "test.milehound.shellPalette.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        XCTAssertEqual(settings.shellPalette, .sky)

        settings.shellPalette = .orange
        XCTAssertEqual(settings.shellPalette, .orange)
        XCTAssertEqual(defaults.string(forKey: ShellPalette.storageKey), "orange")

        let reloaded = AppSettings(userDefaults: defaults)
        XCTAssertEqual(reloaded.shellPalette, .orange)
    }
}

final class FuelCostCalculatorTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "group.com.milehound.app") ?? .standard
        defaults.removeObject(forKey: "fuelCurrency")
    }

    override func tearDown() {
        defaults.removeObject(forKey: "fuelCurrency")
        super.tearDown()
    }

    func testEstimateCostPositive() {
        defaults.set(10.0, forKey: "fuelLitersPer100km")
        defaults.set(40.0, forKey: "fuelPricePerLiter")
        let cost = FuelCostCalculator.estimateCost(distanceMeters: 100_000)
        XCTAssertEqual(cost, 400, accuracy: 0.1)
    }

    func testElectricVehicleUsesKWhPrice() {
        let vehicle = VehicleProfile(name: "EV", fuelType: .electric, consumption: 20, chargePricePerKWh: 10)
        let cost = FuelCostCalculator.estimateCost(distanceMeters: 100_000, vehicle: vehicle)
        XCTAssertEqual(cost, 200, accuracy: 0.1)
    }

    func testTripOverridesBeatVehicleAndSettings() {
        defaults.set(10.0, forKey: "fuelLitersPer100km")
        defaults.set(40.0, forKey: "fuelPricePerLiter")
        let vehicle = VehicleProfile(name: "Car", fuelType: .petrol, consumption: 8)
        let cost = FuelCostCalculator.estimateCost(
            distanceMeters: 100_000,
            vehicle: vehicle,
            consumptionPer100: 12,
            unitPrice: 50
        )
        // 100 km × 12 L/100 × 50 = 600
        XCTAssertEqual(cost, 600, accuracy: 0.1)
    }

    func testElectricTripUnitPriceOverride() {
        let vehicle = VehicleProfile(name: "EV", fuelType: .electric, consumption: 20, chargePricePerKWh: 10)
        let cost = FuelCostCalculator.estimateCost(
            distanceMeters: 50_000,
            vehicle: vehicle,
            consumptionPer100: 18,
            unitPrice: 5
        )
        // 50 km × 18 kWh/100 × 5 = 45
        XCTAssertEqual(cost, 45, accuracy: 0.1)
    }

    func testApplyEstimateSnapshotsInputs() {
        let trip = Trip(distanceMeters: 100_000)
        let vehicle = VehicleProfile(name: "Car", fuelType: .diesel, consumption: 6.5)
        defaults.set(55.0, forKey: "fuelPricePerLiter")
        FuelCostCalculator.applyEstimate(to: trip, distanceMeters: 100_000, vehicle: vehicle)
        XCTAssertEqual(trip.fuelConsumptionPer100 ?? 0, 6.5, accuracy: 0.01)
        XCTAssertEqual(trip.fuelUnitPrice ?? 0, 55, accuracy: 0.01)
        XCTAssertEqual(trip.estimatedFuelCost ?? 0, 357.5, accuracy: 0.1)
    }

    func testResolvedConsumptionPrefersTripThenVehicleThenSettings() {
        defaults.set(10.0, forKey: "fuelLitersPer100km")
        let vehicle = VehicleProfile(name: "Car", fuelType: .petrol, consumption: 8)
        XCTAssertEqual(
            FuelCostCalculator.resolvedConsumption(tripConsumption: 6, vehicle: vehicle),
            6,
            accuracy: 0.01
        )
        XCTAssertEqual(
            FuelCostCalculator.resolvedConsumption(vehicle: vehicle),
            8,
            accuracy: 0.01
        )
        XCTAssertEqual(FuelCostCalculator.resolvedConsumption(), 10, accuracy: 0.01)
    }

    func testResolvedUnitPriceElectricFallsBackWithoutVehicle() {
        defaults.set(9.25, forKey: "evChargePricePerKWh")
        defaults.set(65.0, forKey: "fuelPricePerLiter")
        let price = FuelCostCalculator.resolvedUnitPrice(fuelType: .electric)
        XCTAssertEqual(price, 9.25, accuracy: 0.01)
    }

    func testResolvedUnitPriceLpgIgnoresPetrolAndEvPrices() {
        defaults.set(65.0, forKey: "fuelPricePerLiter")
        defaults.set(9.25, forKey: "evChargePricePerKWh")
        defaults.set(28.0, forKey: "lpgPricePerLiter")
        defer { defaults.removeObject(forKey: "lpgPricePerLiter") }

        let price = FuelCostCalculator.resolvedUnitPrice(fuelType: .lpg)
        XCTAssertEqual(price, 28, accuracy: 0.01)

        let vehicle = VehicleProfile(name: "LPG", fuelType: .lpg, consumption: 10, chargePricePerKWh: 9.25)
        let cost = FuelCostCalculator.estimateCost(distanceMeters: 100_000, vehicle: vehicle)
        // 100 km × 10 L/100 × 28 = 280. Petrol 65 or the EV kWh price must not apply.
        XCTAssertEqual(cost, 280, accuracy: 0.1)

        defaults.removeObject(forKey: "lpgPricePerLiter")
        XCTAssertEqual(FuelCostCalculator.resolvedUnitPrice(fuelType: .lpg), 35, accuracy: 0.01)
    }

    func testDieselUsesSharedLiterPriceUntilItsOwnIsSet() {
        defaults.set(55.0, forKey: "fuelPricePerLiter")
        defaults.removeObject(forKey: "dieselPricePerLiter")
        XCTAssertEqual(FuelCostCalculator.resolvedUnitPrice(fuelType: .diesel), 55, accuracy: 0.01)

        defaults.set(48.0, forKey: "dieselPricePerLiter")
        defer { defaults.removeObject(forKey: "dieselPricePerLiter") }
        XCTAssertEqual(FuelCostCalculator.resolvedUnitPrice(fuelType: .diesel), 48, accuracy: 0.01)
        XCTAssertEqual(FuelCostCalculator.resolvedUnitPrice(fuelType: .petrol), 55, accuracy: 0.01)
    }

    func testFuelPriceRowsFollowSavedVehicleTypes() {
        XCTAssertEqual(FuelPriceRows.types(in: []), [.petrol])
        XCTAssertEqual(FuelPriceRows.types(in: [.petrol, .petrol]), [.petrol])
        XCTAssertEqual(FuelPriceRows.types(in: [.lpg, .petrol]), [.petrol, .lpg])
        XCTAssertEqual(FuelPriceRows.types(in: [.electric]), [.electric])
    }

    func testLpgSpeedShapeMatchesPetrol() {
        let petrol = PowertrainFuelProfile.profile(for: .petrol)
        let lpg = PowertrainFuelProfile.profile(for: .lpg)
        XCTAssertEqual(lpg.kTransient, petrol.kTransient, accuracy: 0.001)
        XCTAssertEqual(lpg.regenCap, petrol.regenCap, accuracy: 0.001)
        for kmh in [50.0, 120.0] {
            XCTAssertEqual(lpg.shape(kmh), petrol.shape(kmh), accuracy: 0.0001)
        }
        XCTAssertEqual(lpg.idleLitresPerHour(c0: 8), petrol.idleLitresPerHour(c0: 8), accuracy: 0.0001)
        XCTAssertEqual(lpg.maxColdLitres(c0: 8), petrol.maxColdLitres(c0: 8), accuracy: 0.0001)
    }

    func testResolvedCurrencyCodeDefaultsToTRY() {
        XCTAssertEqual(FuelCostCalculator.resolvedCurrencyCode(defaults: defaults), "TRY")
    }

    func testFormatCostUsesExplicitCurrencyCode() {
        let tryText = FuelCostCalculator.formatCost(100, currencyCode: "TRY")
        let eurText = FuelCostCalculator.formatCost(100, currencyCode: "EUR")
        let usdText = FuelCostCalculator.formatCost(100, currencyCode: "USD")

        XCTAssertTrue(tryText.contains("₺") || tryText.contains("TRY") || tryText.contains("TL"))
        XCTAssertTrue(eurText.contains("€") || eurText.contains("EUR"))
        XCTAssertTrue(usdText.contains("$") || usdText.contains("USD"))
        XCTAssertNotEqual(tryText, eurText)
        XCTAssertNotEqual(eurText, usdText)
    }

    func testFormatCostReadsStoredFuelCurrency() {
        defaults.set("EUR", forKey: "fuelCurrency")
        let text = FuelCostCalculator.formatCost(42)
        XCTAssertTrue(text.contains("€") || text.contains("EUR"))
    }

    func testFormatCostTurkishLocaleUsesGroupingWithoutFraction() {
        let tr = Locale(identifier: "tr_TR")
        let tenThousand = FuelCostCalculator.formatCost(10_000, currencyCode: "TRY", locale: tr)
        let hundredThousand = FuelCostCalculator.formatCost(100_000, currencyCode: "TRY", locale: tr)
        let million = FuelCostCalculator.formatCost(1_000_000, currencyCode: "TRY", locale: tr)

        XCTAssertTrue(tenThousand.contains("10.000"), tenThousand)
        XCTAssertTrue(hundredThousand.contains("100.000"), hundredThousand)
        XCTAssertTrue(million.contains("1.000.000"), million)
        XCTAssertTrue(tenThousand.contains("₺"), tenThousand)
        XCTAssertFalse(tenThousand.contains(","), tenThousand)
        XCTAssertFalse(tenThousand.contains(".50"), tenThousand)
    }

    func testFormatVolumeUsesLitresAndkWh() {
        let tr = Locale(identifier: "tr_TR")
        XCTAssertEqual(
            FuelCostCalculator.formatVolume(cost: 19.5, unitPrice: 65, isElectric: false, locale: tr),
            "0,3 L"
        )
        XCTAssertEqual(
            FuelCostCalculator.formatVolume(cost: 42, unitPrice: 8.5, isElectric: true, locale: tr),
            "4,94 kWh"
        )
        XCTAssertNil(FuelCostCalculator.formatVolume(cost: 10, unitPrice: 0, isElectric: false))
    }

    func testTripEditFuelCopyUsesAvgFuelNames() {
        let section = L10n.tripEditFuelSection
        XCTAssertTrue(
            section.contains("Avg fuel") || section.contains("Ort. yakıt"),
            section
        )
        let preview = L10n.tripEditFuelPreview("₺ 19")
        XCTAssertTrue(preview.contains("₺ 19"), preview)
        XCTAssertTrue(
            preview.contains("Avg fuel calculation") || preview.contains("Ort. yakıt hesaplama"),
            preview
        )
        XCTAssertFalse(L10n.tripEditFuelHelpTitle.isEmpty)
        XCTAssertFalse(L10n.tripEditFuelHelpBody.isEmpty)
        XCTAssertFalse(L10n.journalAddHelpTitle.isEmpty)
        XCTAssertFalse(L10n.journalAddHelpBody.isEmpty)
    }
}

@MainActor
final class AppSettingsFuelCurrencyTests: XCTestCase {
    func testFuelCurrencyDefaultsToTRYAndRoundTrips() {
        let suiteName = "group.com.milehound.app.tests.fuelCurrency.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(userDefaults: defaults)
        XCTAssertEqual(settings.fuelCurrency, .tryCurrency)

        settings.fuelCurrency = .eur
        XCTAssertEqual(settings.fuelCurrency, .eur)
        XCTAssertEqual(defaults.string(forKey: "fuelCurrency"), "EUR")

        settings.fuelCurrency = .usd
        XCTAssertEqual(settings.fuelCurrency, .usd)

        settings.fuelCurrency = .tryCurrency
        XCTAssertEqual(settings.fuelCurrency, .tryCurrency)
    }

    func testMonthlyGoalLocksPerCalendarMonth() {
        let suiteName = "test.milehound.monthlyGoal.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        let now = Date()
        let previousMonth = StatsViewModel.shiftMonth(now, by: -1)
        let currentKey = settings.goalMonthKey(for: now)

        XCTAssertTrue(settings.isGoalEditable(forMonthContaining: now))
        XCTAssertFalse(settings.isGoalEditable(forMonthContaining: previousMonth))
        XCTAssertEqual(settings.monthlyGoalsByMonth[currentKey] ?? -1, settings.monthlyDistanceGoalMeters, accuracy: 0.1)

        settings.setMonthlyGoalMeters(750_000, forMonthContaining: now, now: now)
        XCTAssertEqual(settings.monthlyDistanceGoalMeters, 750_000, accuracy: 0.1)
        XCTAssertEqual(settings.goalMeters(forMonthContaining: now), 750_000, accuracy: 0.1)
        XCTAssertEqual(settings.monthlyGoalsByMonth[currentKey] ?? -1, 750_000, accuracy: 0.1)

        // Past months refuse writes; fallback to live value when no history exists.
        settings.setMonthlyGoalMeters(100_000, forMonthContaining: previousMonth, now: now)
        XCTAssertEqual(settings.monthlyDistanceGoalMeters, 750_000, accuracy: 0.1)
        XCTAssertEqual(settings.goalMeters(forMonthContaining: previousMonth), 750_000, accuracy: 0.1)

        // A frozen past entry wins over the live target.
        defaults.set(
            [settings.goalMonthKey(for: previousMonth): 400_000.0, currentKey: 750_000.0],
            forKey: "monthlyGoalsByMonth"
        )
        let reloaded = AppSettings(userDefaults: defaults)
        XCTAssertEqual(reloaded.goalMeters(forMonthContaining: previousMonth), 400_000, accuracy: 0.1)
        XCTAssertEqual(reloaded.goalMeters(forMonthContaining: now), 750_000, accuracy: 0.1)
        XCTAssertFalse(reloaded.isGoalEditable(forMonthContaining: previousMonth))
    }
}

final class MapSnapshotAppearanceTests: XCTestCase {
    func testLightAndDarkFileNamesDiffer() {
        let tripID = UUID()
        let light = MapSnapshotAppearance.light.fileName(for: tripID)
        let dark = MapSnapshotAppearance.dark.fileName(for: tripID)
        XCTAssertNotEqual(light, dark)
        XCTAssertTrue(light.hasSuffix("-light.jpg"))
        XCTAssertTrue(dark.hasSuffix("-dark.jpg"))
        XCTAssertTrue(light.contains(tripID.uuidString))
        XCTAssertTrue(dark.contains(tripID.uuidString))
    }

    func testRemovalFileNamesCoverBothAppearances() {
        let tripID = UUID()
        let names = Set(MapSnapshotAppearance.fileNames(for: tripID))
        XCTAssertEqual(names, [
            MapSnapshotAppearance.light.fileName(for: tripID),
            MapSnapshotAppearance.dark.fileName(for: tripID)
        ])
    }

    func testAppearanceMapsFromColorScheme() {
        XCTAssertEqual(MapSnapshotAppearance(.light), .light)
        XCTAssertEqual(MapSnapshotAppearance(.dark), .dark)
    }

    func testLegacyUnstyledFileNamesAreBareUUIDs() {
        let tripID = UUID()
        XCTAssertTrue(MapSnapshotAppearance.isLegacyUnstyledFileName("\(tripID.uuidString).jpg"))
        XCTAssertFalse(MapSnapshotAppearance.isLegacyUnstyledFileName(
            MapSnapshotAppearance.light.fileName(for: tripID)
        ))
        XCTAssertFalse(MapSnapshotAppearance.isLegacyUnstyledFileName(
            MapSnapshotAppearance.dark.fileName(for: tripID)
        ))
        XCTAssertFalse(MapSnapshotAppearance.isLegacyUnstyledFileName("not-a-uuid.jpg"))
    }
}
