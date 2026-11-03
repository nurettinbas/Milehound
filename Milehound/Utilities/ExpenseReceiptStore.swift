import SwiftData
import UIKit

/// Disk + memory store for expense receipt photos. SwiftData keeps only the file name
/// (`VehicleExpense.receiptFileName`); the JPEG lives in Application Support and never leaves the device.
@MainActor
final class ExpenseReceiptStore {
    static let shared = ExpenseReceiptStore()

    /// Long edge in pixels. Big enough for small receipt type to stay legible to Vision and the eye.
    nonisolated static let maxPixelSize: CGFloat = 1600
    nonisolated static let jpegQuality: CGFloat = 0.8
    nonisolated static let thumbnailPixelSize: CGFloat = 240

    private var imageCache: [String: UIImage] = [:]
    private var thumbnailCache: [String: UIImage] = [:]
    let directory: URL

    private nonisolated static let diskQueue = DispatchQueue(
        label: "com.milehound.ExpenseReceiptStore.disk",
        qos: .utility
    )

    init(directory: URL? = nil) {
        let fileManager = FileManager.default
        if let directory {
            self.directory = directory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("ExpenseReceipts", isDirectory: true)
        }
        if !fileManager.fileExists(atPath: self.directory.path) {
            try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        }
    }

    func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    /// Downsamples to `maxPixelSize`, writes a protected JPEG, returns the new file name.
    func save(_ image: UIImage) async throws -> String {
        let data = try await Self.encode(image)
        let fileName = "\(UUID().uuidString).jpg"
        let url = fileURL(for: fileName)
        try await Self.write(data, to: url)
        if let decoded = UIImage(data: data) {
            imageCache[fileName] = decoded
        }
        return fileName
    }

    func cachedImage(fileName: String) -> UIImage? {
        imageCache[fileName]
    }

    func image(fileName: String) async -> UIImage? {
        if let cached = imageCache[fileName] { return cached }
        guard let image = await Self.readImage(at: fileURL(for: fileName)) else { return nil }
        imageCache[fileName] = image
        return image
    }

    func cachedThumbnail(fileName: String) -> UIImage? {
        thumbnailCache[fileName]
    }

    func thumbnail(fileName: String) async -> UIImage? {
        if let cached = thumbnailCache[fileName] { return cached }
        guard let full = await image(fileName: fileName) else { return nil }
        let thumb = await Self.render(full, maxPixel: Self.thumbnailPixelSize)
        thumbnailCache[fileName] = thumb
        return thumb
    }

    func remove(fileName: String) {
        imageCache.removeValue(forKey: fileName)
        thumbnailCache.removeValue(forKey: fileName)
        let url = fileURL(for: fileName)
        Self.diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes the file only when no `VehicleExpense` still points at it (installment siblings share one).
    func removeIfUnreferenced(fileName: String?, in context: ModelContext) {
        guard let fileName, !fileName.isEmpty else { return }
        if Self.referenceCount(of: fileName, in: context) == 0 {
            remove(fileName: fileName)
        }
    }

    static func referenceCount(of fileName: String, in context: ModelContext) -> Int {
        let target: String? = fileName
        let descriptor = FetchDescriptor<VehicleExpense>(
            predicate: #Predicate { $0.receiptFileName == target }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func clearMemory() {
        imageCache.removeAll()
        thumbnailCache.removeAll()
    }

    // MARK: - Image processing

    nonisolated static func encode(_ image: UIImage) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            diskQueue.async {
                let output = downsample(image, maxPixel: maxPixelSize)
                guard let data = output.jpegData(compressionQuality: jpegQuality) else {
                    continuation.resume(throwing: ReceiptStoreError.encodeFailed)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    nonisolated private static func render(_ image: UIImage, maxPixel: CGFloat) async -> UIImage {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                continuation.resume(returning: downsample(image, maxPixel: maxPixel))
            }
        }
    }

    /// Draws upright at scale 1 so EXIF orientation is baked in before Vision reads the pixels.
    nonisolated static func downsample(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let pixelWidth = max(1, image.size.width * image.scale)
        let pixelHeight = max(1, image.size.height * image.scale)
        let longest = max(pixelWidth, pixelHeight)
        let ratio = longest > maxPixel ? maxPixel / longest : 1
        if ratio == 1, image.scale == 1, image.imageOrientation == .up {
            return image
        }
        let newSize = CGSize(
            width: max(1, (pixelWidth * ratio).rounded(.down)),
            height: max(1, (pixelHeight * ratio).rounded(.down))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func readImage(at url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(data: data))
            }
        }
    }

    private static func write(_ data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            diskQueue.async {
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    enum ReceiptStoreError: Error {
        case encodeFailed
    }
}
