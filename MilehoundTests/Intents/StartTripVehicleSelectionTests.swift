import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class StartTripVehicleSelectionTests: XCTestCase {
    func testVehicleEntityMapsFromProfile() {
        let profile = VehicleProfile(name: "Motor")
        let entity = VehicleEntity.from(profile)
        XCTAssertEqual(entity.id, profile.id)
        XCTAssertEqual(entity.name, "Motor")
    }

    func testFetchSortedEntitiesOrdersByName() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        context.insert(VehicleProfile(name: "Zebra"))
        context.insert(VehicleProfile(name: "Alpha"))
        try context.save()

        let entities = VehicleEntityQuery.fetchSortedEntities(from: context)
        XCTAssertEqual(entities.map(\.name), ["Alpha", "Zebra"])
    }

    func testApplyShortcutVehicleThenExternalStartAssignsSelectedVehicle() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.shortcut.vehicle.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.confirmExternalRecordingStart = false

        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let car = VehicleProfile(name: "Car", isDefault: true)
        let bike = VehicleProfile(name: "Bike")
        context.insert(car)
        context.insert(bike)
        try context.save()
        settings.recordingVehicleID = car.id

        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: context)

        ShortcutStartVehicleSelection.apply(vehicleID: bike.id, using: recordingService)
        settings.pendingStartRecordingRequest = true
        recordingService.processExternalStartRequest()
        defer { recordingService.stopManualRecording() }

        XCTAssertEqual(settings.recordingVehicleID, bike.id)
        XCTAssertEqual(recordingService.state, .recording)
        XCTAssertEqual(recordingService.activeRecordingVehicleID(in: context), bike.id)
    }

    func testApplyNilShortcutVehicleKeepsExistingRecordingVehicle() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.shortcut.vehicle.nil.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.confirmExternalRecordingStart = false

        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let car = VehicleProfile(name: "Car", isDefault: true)
        let bike = VehicleProfile(name: "Bike")
        context.insert(car)
        context.insert(bike)
        try context.save()
        settings.recordingVehicleID = car.id

        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: context)

        ShortcutStartVehicleSelection.apply(vehicleID: nil, using: recordingService)
        settings.pendingStartRecordingRequest = true
        recordingService.processExternalStartRequest()
        defer { recordingService.stopManualRecording() }

        XCTAssertEqual(settings.recordingVehicleID, car.id)
        XCTAssertEqual(recordingService.activeRecordingVehicleID(in: context), car.id)
    }

    func testApplyUnknownShortcutVehicleIDDoesNotChangeSelection() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.shortcut.vehicle.unknown.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.confirmExternalRecordingStart = false

        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let car = VehicleProfile(name: "Car", isDefault: true)
        context.insert(car)
        try context.save()
        settings.recordingVehicleID = car.id

        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: context)

        ShortcutStartVehicleSelection.apply(vehicleID: UUID(), using: recordingService)
        settings.pendingStartRecordingRequest = true
        recordingService.processExternalStartRequest()
        defer { recordingService.stopManualRecording() }

        XCTAssertEqual(settings.recordingVehicleID, car.id)
        XCTAssertEqual(recordingService.activeRecordingVehicleID(in: context), car.id)
    }
}
