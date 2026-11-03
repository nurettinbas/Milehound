import SwiftData
import UIKit
import XCTest
@testable import Milehound

/// In-process capture → framing → draft apply path (no Photos UI / AVCapture).
@MainActor
final class VehiclePhotoCapturePipelineTests: XCTestCase {
    func testPrepareForCropShrinksHugeImage() {
        let huge = makeSolidImage(width: 4096, height: 3072)
        let prepared = VehiclePhotoCropMath.prepareForCrop(huge, maxEdge: 1024)
        let longest = max(prepared.size.width, prepared.size.height)
        XCTAssertLessThanOrEqual(longest, 1024 + 0.5)
    }

    func testCapturePipelineWritesThenClearsPhoto() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Pipeline Car")
        context.insert(vehicle)
        try context.save()

        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-pipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let photoStore = VehiclePhotoStore(directory: photoDirectory)

        let defaults = UserDefaults(suiteName: "test.milehound.capture.pipeline.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        // Mimic sheet pick → beginInlineFraming → applyFraming → save.
        let picked = makeSolidImage(width: 1600, height: 1200)
        let prepared = VehiclePhotoCropMath.prepareForCrop(picked)
        let cropped = try XCTUnwrap(
            VehiclePhotoCropMath.renderSquare(
                image: prepared,
                cropSide: 132,
                userScale: VehiclePhotoCropMath.defaultUserScale,
                offset: .zero
            )
        )
        let thumb = try await VehiclePhotoStore.makeThumbnail(from: cropped)

        var draft = VehicleEditorDraft(from: vehicle)
        draft.photoEdit = .newThumb(thumb)
        try await draft.apply(
            to: vehicle,
            allVehicles: [vehicle],
            in: context,
            settings: settings,
            photoStore: photoStore
        )

        let savedName = try XCTUnwrap(vehicle.photoFileName)
        let savedURL = photoStore.fileURL(for: savedName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))

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

        // Disk delete is async on the store queue — wait briefly (same as VehiclePhotoStoreTests).
        let deadline = Date().addingTimeInterval(1)
        while FileManager.default.fileExists(atPath: savedURL.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV12.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeSolidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
