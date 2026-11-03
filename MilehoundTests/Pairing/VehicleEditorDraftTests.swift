import SwiftData
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class VehicleEditorDraftTests: XCTestCase {
    func testInitFromVehicleCopiesFields() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vehicle = VehicleProfile(
            name: "Roadster",
            fuelType: .electric,
            consumption: 18.5,
            chargePricePerKWh: 9.2,
            isDefault: true,
            iconName: VehicleIconOption.electric.rawValue,
            photoFileName: "car.jpg"
        )
        context.insert(vehicle)

        let draft = VehicleEditorDraft(from: vehicle)

        XCTAssertEqual(draft.name, "Roadster")
        XCTAssertEqual(draft.fuelType, .electric)
        XCTAssertEqual(draft.consumption, 18.5)
        XCTAssertEqual(draft.chargePricePerKWh, 9.2)
        XCTAssertEqual(draft.iconName, VehicleIconOption.electric.rawValue)
        XCTAssertTrue(draft.wantsDefault)
        XCTAssertEqual(draft.existingPhotoFileName, "car.jpg")
        XCTAssertEqual(draft.photoEdit, .unchanged)
        XCTAssertTrue(draft.hasDisplayPhoto)
    }

    func testApplyWritesModelWithoutChangingID() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Before", fuelType: .petrol, consumption: 7.0)
        context.insert(vehicle)
        try context.save()
        let originalID = vehicle.id

        var draft = VehicleEditorDraft(from: vehicle)
        draft.name = "After"
        draft.fuelType = .diesel
        draft.consumption = 6.2
        // Icon picker is gone — even a draft iconName must not persist as a custom mark.
        draft.iconName = VehicleIconOption.suv.rawValue

        let defaults = UserDefaults(suiteName: "test.milehound.draft.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        try await draft.apply(to: vehicle, allVehicles: [vehicle], in: context, settings: settings)

        XCTAssertEqual(vehicle.id, originalID)
        XCTAssertEqual(vehicle.name, "After")
        XCTAssertEqual(vehicle.fuelType, .diesel)
        XCTAssertEqual(vehicle.consumption, 6.2)
        XCTAssertEqual(vehicle.iconName, VehicleIconOption.default.rawValue)
    }

    func testApplyDefaultVehicleCallsPairingServiceBehavior() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")
        context.insert(first)
        context.insert(second)
        first.isDefault = true
        try context.save()

        let defaults = UserDefaults(suiteName: "test.milehound.draft.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        var draft = VehicleEditorDraft(from: second)
        draft.wantsDefault = true
        try await draft.apply(to: second, allVehicles: [first, second], in: context, settings: settings)

        XCTAssertFalse(first.isDefault)
        XCTAssertTrue(second.isDefault)
        XCTAssertEqual(settings.recordingVehicleID, second.id)
    }

    func testApplySetsAndClearsPhotoFileName() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Photo Car")
        context.insert(vehicle)
        try context.save()

        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-photo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let photoStore = VehiclePhotoStore(directory: photoDirectory)

        let thumb = try await VehiclePhotoStore.makeThumbnail(from: makeSolidImage())
        var draft = VehicleEditorDraft(from: vehicle)
        draft.photoEdit = .newThumb(thumb)

        let defaults = UserDefaults(suiteName: "test.milehound.draft.photo.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        try await draft.apply(
            to: vehicle,
            allVehicles: [vehicle],
            in: context,
            settings: settings,
            photoStore: photoStore
        )

        let savedName = try XCTUnwrap(vehicle.photoFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoStore.fileURL(for: savedName).path))

        var clearDraft = VehicleEditorDraft(from: vehicle)
        clearDraft.photoEdit = .removed
        try await clearDraft.apply(
            to: vehicle,
            allVehicles: [vehicle],
            in: context,
            settings: settings,
            photoStore: photoStore
        )
        XCTAssertNil(vehicle.photoFileName)
    }

    func testOdometerTextRejectsBadInputAndApplySetsTheAnchor() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Vespa")
        context.insert(vehicle)
        var draft = VehicleEditorDraft(from: vehicle)
        XCTAssertTrue(draft.odometerInputIsValid)
        draft.odometerKmText = "-4"
        XCTAssertFalse(draft.odometerInputIsValid)
        draft.odometerKmText = "4000"
        XCTAssertTrue(draft.odometerInputIsValid)

        let defaults = UserDefaults(suiteName: "test.milehound.draft.odo.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        try await draft.apply(to: vehicle, allVehicles: [vehicle], in: context, settings: settings)
        XCTAssertEqual(vehicle.odometerAnchorKm, 4_000)
        XCTAssertEqual(vehicle.currentOdometerKm, 4_000)

        let unchanged = VehicleEditorDraft(from: vehicle)
        let anchorAt = vehicle.odometerAnchorAt
        try await unchanged.apply(to: vehicle, allVehicles: [vehicle], in: context, settings: settings)
        XCTAssertEqual(vehicle.odometerAnchorAt, anchorAt)

        var cleared = VehicleEditorDraft(from: vehicle)
        cleared.odometerKmText = ""
        try await cleared.apply(to: vehicle, allVehicles: [vehicle], in: context, settings: settings)
        XCTAssertNil(vehicle.currentOdometerKm)
        XCTAssertNil(vehicle.odometerAnchorKm)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV12.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeSolidImage() -> UIImage {
        let size = CGSize(width: 120, height: 80)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
