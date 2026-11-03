import UIKit
import XCTest
@testable import Milehound

@MainActor
final class VehiclePhotoStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: VehiclePhotoStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VehiclePhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = VehiclePhotoStore(directory: tempDirectory)
    }

    override func tearDown() async throws {
        store.clearMemory()
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        tempDirectory = nil
        try await super.tearDown()
    }

    func testDownsampleProducesJPEGUnderMaxEdge() async throws {
        let source = makeSolidImage(width: 1200, height: 800)
        let jpeg = try await VehiclePhotoStore.makeThumbnailJPEG(from: source)
        XCTAssertFalse(jpeg.isEmpty)
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        let longest = max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale)
        XCTAssertLessThanOrEqual(longest, VehiclePhotoStore.maxPixelSize + 1)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let source = makeSolidImage(width: 400, height: 300)
        let fileName = try await store.saveThumbnail(from: source)
        XCTAssertTrue(fileName.hasSuffix(".jpg"))
        XCTAssertNotNil(store.cachedImage(fileName: fileName))

        store.clearMemory()
        let loaded = await store.image(fileName: fileName)
        XCTAssertNotNil(loaded)
    }

    func testReplaceRemovesOldFile() async throws {
        let first = try await store.saveThumbnail(from: makeSolidImage(width: 200, height: 200))
        let firstURL = store.fileURL(for: first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        let second = try await store.saveThumbnail(
            from: makeSolidImage(width: 220, height: 180),
            replacingFileName: first
        )
        XCTAssertNotEqual(first, second)

        // Disk delete is async on the store queue — wait briefly.
        let deadline = Date().addingTimeInterval(1)
        while FileManager.default.fileExists(atPath: firstURL.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: second).path))
    }

    func testMissingFileReturnsNil() async {
        let image = await store.image(fileName: "does-not-exist.jpg")
        XCTAssertNil(image)
    }

    func testPrefetchWarmsMemoryCache() async throws {
        let fileName = try await store.saveThumbnail(from: makeSolidImage(width: 200, height: 200))
        store.clearMemory()
        XCTAssertNil(store.cachedImage(fileName: fileName))

        await store.prefetch(fileNames: [fileName, fileName, "missing.jpg"])
        XCTAssertNotNil(store.cachedImage(fileName: fileName))
    }

    func testTransparentImageSavesAsPNGPreservingAlpha() async throws {
        let source = makeTransparentImage(size: 200)
        XCTAssertTrue(VehiclePhotoStore.imageHasAlpha(source))
        let thumb = try await VehiclePhotoStore.makeThumbnail(from: source)
        XCTAssertEqual(thumb.format, .png)
        let fileName = try await store.saveThumbnail(thumb)
        XCTAssertTrue(fileName.hasSuffix(".png"))

        store.clearMemory()
        let loaded = await store.image(fileName: fileName)
        let image = try XCTUnwrap(loaded)
        XCTAssertTrue(VehiclePhotoStore.imageHasAlpha(image))
    }

    func testMarkImageRemovesNearWhiteStudioPlate() {
        let source = makeCarOnWhitePlate(size: 64)
        XCTAssertFalse(VehiclePhotoStore.imageHasAlpha(source))
        let punched = VehiclePhotoStore.markImageByRemovingLightBackdrop(source)
        XCTAssertTrue(VehiclePhotoStore.imageHasAlpha(punched))
        XCTAssertFalse(VehiclePhotoStore.markImageIsVisuallyEmpty(punched))
        XCTAssertGreaterThan(VehiclePhotoStore.opaquePixelCoverage(punched), 0.04)
    }

    func testFullyWhiteImageIsVisuallyEmptyAfterPunch() {
        let white = makeSolidColorImage(width: 64, height: 64, color: .white)
        let punched = VehiclePhotoStore.markImageByRemovingLightBackdrop(white)
        XCTAssertTrue(VehiclePhotoStore.markImageIsVisuallyEmpty(punched))
    }

    /// A light vehicle can be eaten by the punch — the display mark must still show a photo.
    func testDisplayMarkFallsBackToOriginalWhenPunchEatsEverything() {
        let white = makeSolidColorImage(width: 64, height: 64, color: .white)
        let mark = VehiclePhotoStore.markImageForDisplay(white)
        XCTAssertFalse(VehiclePhotoStore.markImageIsVisuallyEmpty(mark))
    }

    func testLiveActivityMarkStoreWriteReadRoundTripPreservesAlpha() throws {
        let markDir = tempDirectory.appendingPathComponent("LiveActivityMark", isDirectory: true)
        try FileManager.default.createDirectory(at: markDir, withIntermediateDirectories: true)
        LiveActivityVehicleMarkStore.directoryOverride = markDir
        defer {
            LiveActivityVehicleMarkStore.clear()
            LiveActivityVehicleMarkStore.directoryOverride = nil
        }

        let source = makeTransparentImage(size: VehiclePhotoStore.maxPixelSize)
        let revision = try XCTUnwrap(LiveActivityVehicleMarkStore.write(source))
        XCTAssertFalse(revision.isEmpty)

        // Second write refreshes the file and memory cache; asking for the prior revision
        // forces a disk read (cache miss) while still loading the same PNG bytes.
        let revision2 = try XCTUnwrap(LiveActivityVehicleMarkStore.write(source))
        XCTAssertNotEqual(revision, revision2)
        let loaded = try XCTUnwrap(LiveActivityVehicleMarkStore.image(revision: revision))
        XCTAssertTrue(VehiclePhotoStore.imageHasAlpha(loaded))
        let longest = max(loaded.size.width * loaded.scale, loaded.size.height * loaded.scale)
        XCTAssertEqual(longest, VehiclePhotoStore.maxPixelSize, accuracy: 1)
    }

    func testLiveActivityMarkStoreKeepsStudioPlateOpaque() throws {
        let markDir = tempDirectory.appendingPathComponent("LiveActivityMarkOpaque", isDirectory: true)
        try FileManager.default.createDirectory(at: markDir, withIntermediateDirectories: true)
        LiveActivityVehicleMarkStore.directoryOverride = markDir
        defer {
            LiveActivityVehicleMarkStore.clear()
            LiveActivityVehicleMarkStore.directoryOverride = nil
        }

        let source = makeCarOnWhitePlate(size: VehiclePhotoStore.maxPixelSize)
        // Road punch would eat most of a light plate; Live Activity must keep the filled thumb.
        let punched = VehiclePhotoStore.markImageByRemovingLightBackdrop(source)
        XCTAssertLessThan(VehiclePhotoStore.opaquePixelCoverage(punched), 0.5)

        let revision = try XCTUnwrap(LiveActivityVehicleMarkStore.write(source))
        let loaded = try XCTUnwrap(LiveActivityVehicleMarkStore.image(revision: revision))
        XCTAssertGreaterThan(VehiclePhotoStore.opaquePixelCoverage(loaded), 0.9)
    }

    func testLiveActivityMarkStoreNilRevisionReturnsNil() {
        XCTAssertNil(LiveActivityVehicleMarkStore.image(revision: nil))
        XCTAssertNil(LiveActivityVehicleMarkStore.image(revision: ""))
    }

    func testMakeCachedWithoutPhotoUsesFixedFallback() {
        let mark = RecordingVehicleMarkSnapshot.makeCached(for: nil)
        XCTAssertEqual(mark.systemImage, RecordingVehicleMarkSnapshot.fallback.systemImage)
        XCTAssertEqual(mark.symbolScaleX, RecordingVehicleMarkSnapshot.fallback.symbolScaleX)
        XCTAssertNil(mark.photoRevision)
    }

    func testMakeCachedIgnoresVehicleIconName() {
        let vehicle = VehicleProfile(
            name: "Truck",
            iconName: VehicleIconOption.truck.rawValue
        )
        let mark = RecordingVehicleMarkSnapshot.makeCached(for: vehicle)
        XCTAssertEqual(mark.systemImage, "car.side.fill")
        XCTAssertEqual(mark.symbolScaleX, -1)
        XCTAssertNil(mark.photoRevision)
    }

    func testDisplayMarkKeepsPunchWhenVehicleSurvives() {
        let source = makeCarOnWhitePlate(size: 64)
        let mark = VehiclePhotoStore.markImageForDisplay(source)
        XCTAssertTrue(VehiclePhotoStore.imageHasAlpha(mark))
        XCTAssertFalse(VehiclePhotoStore.markImageIsVisuallyEmpty(mark))
    }

    private func makeTransparentImage(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.systemBlue.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size * 0.2, y: size * 0.2, width: size * 0.6, height: size * 0.6))
        }
    }

    private func makeSolidImage(width: CGFloat, height: CGFloat) -> UIImage {
        makeSolidColorImage(width: width, height: height, color: .systemBlue)
    }

    private func makeSolidColorImage(width: CGFloat, height: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeCarOnWhitePlate(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.darkGray.setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: size * 0.2, y: size * 0.35, width: size * 0.6, height: size * 0.3)
            )
        }
    }
}
