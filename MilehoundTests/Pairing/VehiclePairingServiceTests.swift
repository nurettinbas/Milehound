import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class VehiclePairingServiceTests: XCTestCase {
    func testSetDefaultVehicleMarksSingleDefault() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")
        context.insert(first)
        context.insert(second)
        first.isDefault = true

        VehiclePairingService.setDefaultVehicle(second, in: context)

        XCTAssertFalse(first.isDefault)
        XCTAssertTrue(second.isDefault)
    }

    func testDeleteVehiclePromotesNextDefault() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")
        context.insert(first)
        context.insert(second)
        first.isDefault = true

        VehiclePairingService.deleteVehicle(first, in: context)

        let remaining = try context.fetch(FetchDescriptor<VehicleProfile>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first?.isDefault == true)
        XCTAssertEqual(remaining.first?.name, "Second")
    }

    func testMigrateLegacyBluetoothAutoStartClearsVehicleBindings() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let vehicle = VehicleProfile(
            name: "Ford Puma",
            autoStartEnabled: true,
            pairedRouteUID: "legacy-uid",
            pairedRouteName: "Ford Puma"
        )
        context.insert(vehicle)
        try context.save()

        VehiclePairingService.migrateLegacyBluetoothAutoStart(in: context)

        XCTAssertFalse(vehicle.autoStartEnabled)
        XCTAssertNil(vehicle.pairedRouteUID)
        XCTAssertNil(vehicle.pairedRouteName)
    }
}

@MainActor
final class VehicleResolverTests: XCTestCase {
    func testResolvePrefersRecordingVehicleIDOverDefault() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "test.milehound.vehicle.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        let defaultVehicle = VehicleProfile(name: "Default", isDefault: true)
        let other = VehicleProfile(name: "Other")
        context.insert(defaultVehicle)
        context.insert(other)
        settings.recordingVehicleID = other.id

        let resolved = VehicleResolver.resolveActiveVehicle(in: context, settings: settings)
        XCTAssertEqual(resolved?.id, other.id)
    }

    /// The fetch-free variant is what views use, so it must match the context-backed one.
    func testResolveFromArrayPrefersRecordingVehicleID() {
        let settings = makeSettings()
        let defaultVehicle = VehicleProfile(name: "Default", isDefault: true)
        let other = VehicleProfile(name: "Other")
        settings.recordingVehicleID = other.id

        let resolved = VehicleResolver.resolveActiveVehicle(
            from: [defaultVehicle, other],
            settings: settings
        )
        XCTAssertEqual(resolved?.id, other.id)
    }

    func testResolveFromArrayFallsBackToDefaultVehicle() {
        let settings = makeSettings()
        let first = VehicleProfile(name: "First")
        let defaultVehicle = VehicleProfile(name: "Default", isDefault: true)

        let resolved = VehicleResolver.resolveActiveVehicle(
            from: [first, defaultVehicle],
            settings: settings
        )
        XCTAssertEqual(resolved?.id, defaultVehicle.id)
    }

    func testResolveFromArrayFallsBackToFirstWhenNoDefault() {
        let settings = makeSettings()
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")

        let resolved = VehicleResolver.resolveActiveVehicle(
            from: [first, second],
            settings: settings
        )
        XCTAssertEqual(resolved?.id, first.id)
    }

    func testResolveFromArrayIgnoresStalePreferredID() {
        let settings = makeSettings()
        let defaultVehicle = VehicleProfile(name: "Default", isDefault: true)
        settings.recordingVehicleID = UUID()

        let resolved = VehicleResolver.resolveActiveVehicle(
            from: [defaultVehicle],
            settings: settings
        )
        XCTAssertEqual(resolved?.id, defaultVehicle.id)
    }

    func testResolveFromEmptyArrayReturnsNil() {
        XCTAssertNil(VehicleResolver.resolveActiveVehicle(from: [], settings: makeSettings()))
    }

    private func makeSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "test.milehound.vehicle.\(UUID().uuidString)")!
        return AppSettings(userDefaults: defaults)
    }
}
