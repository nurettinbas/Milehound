import UIKit

enum VehiclePhotoThumbFormat: String, Equatable, Sendable {
    case jpeg
    case png

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}

struct VehiclePhotoThumb: Equatable, Sendable {
    let data: Data
    let format: VehiclePhotoThumbFormat
}

/// Disk + memory store for vehicle avatar thumbnails (never full-resolution gallery assets).
@MainActor
final class VehiclePhotoStore {
    static let shared = VehiclePhotoStore()

    nonisolated static let maxPixelSize: CGFloat = 256
    nonisolated static let jpegQuality: CGFloat = 0.72

    private var memoryCache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL

    private nonisolated static let diskQueue = DispatchQueue(
        label: "com.milehound.VehiclePhotoStore.disk",
        qos: .utility
    )

    init(directory: URL? = nil) {
        let fileManager = FileManager.default
        if let directory {
            self.directory = directory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("VehiclePhotos", isDirectory: true)
        }
        if !fileManager.fileExists(atPath: self.directory.path) {
            try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        }
    }

    /// Memory hit only — safe while scrolling.
    func cachedImage(fileName: String) -> UIImage? {
        memoryCache[fileName]
    }

    /// Sync warm for Live Activity mark encoding (cache → disk). Prefer `image(fileName:)` on UI paths.
    func imageSync(fileName: String) -> UIImage? {
        if let cached = memoryCache[fileName] {
            return cached
        }
        let url = fileURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        memoryCache[fileName] = image
        return image
    }

    func image(fileName: String) async -> UIImage? {
        if let cached = memoryCache[fileName] {
            return cached
        }
        if let existing = inFlight[fileName] {
            return await existing.value
        }
        let task = Task<UIImage?, Never> { @MainActor in
            defer { inFlight[fileName] = nil }
            let url = fileURL(for: fileName)
            guard let image = await Self.readImage(at: url) else { return nil }
            memoryCache[fileName] = image
            return image
        }
        inFlight[fileName] = task
        return await task.value
    }

    func saveThumbnail(
        from image: UIImage,
        replacingFileName: String? = nil
    ) async throws -> String {
        let thumb = try await Self.makeThumbnail(from: image)
        return try await saveThumbnail(thumb, replacingFileName: replacingFileName)
    }

    func saveThumbnail(
        _ thumb: VehiclePhotoThumb,
        replacingFileName: String? = nil
    ) async throws -> String {
        let fileName = "\(UUID().uuidString).\(thumb.format.fileExtension)"
        let url = fileURL(for: fileName)
        try await Self.write(thumb.data, to: url)
        if let decoded = UIImage(data: thumb.data) {
            memoryCache[fileName] = decoded
        }
        if let replacingFileName, replacingFileName != fileName {
            remove(fileName: replacingFileName)
        }
        return fileName
    }

    /// Legacy entry used by older call sites — routes through alpha-aware encode.
    func saveThumbnailJPEG(
        _ data: Data,
        replacingFileName: String? = nil
    ) async throws -> String {
        try await saveThumbnail(
            VehiclePhotoThumb(data: data, format: .jpeg),
            replacingFileName: replacingFileName
        )
    }

    func remove(fileName: String) {
        memoryCache.removeValue(forKey: fileName)
        inFlight[fileName]?.cancel()
        inFlight.removeValue(forKey: fileName)
        RecordingVehicleMarkSnapshot.clearCompactPNGCache(fileName: fileName)
        let url = fileURL(for: fileName)
        Self.diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func clearMemory() {
        memoryCache.removeAll()
    }

    /// Warm the memory cache for upcoming identity surfaces (road scene, chips, pickers).
    /// Skips names already cached; coalesces in-flight reads via `image(fileName:)`.
    func prefetch(fileNames: [String]) async {
        var seen = Set<String>()
        for fileName in fileNames {
            let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            if memoryCache[trimmed] != nil { continue }
            _ = await image(fileName: trimmed)
        }
    }

    func prefetch(vehicles: [VehicleProfile]) async {
        await prefetch(fileNames: vehicles.compactMap { $0.photoFileName })
    }

    /// Stable `.task(id:)` token when vehicle photo filenames change.
    static func prefetchTaskID(for vehicles: [VehicleProfile]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(vehicles.count)
        for vehicle in vehicles {
            parts.append(vehicle.id.uuidString)
            parts.append(vehicle.photoFileName ?? "")
        }
        return parts.joined(separator: "|")
    }

    func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    // MARK: - Image processing

    static func makeThumbnail(from image: UIImage) async throws -> VehiclePhotoThumb {
        try await withCheckedThrowingContinuation { continuation in
            diskQueue.async {
                do {
                    continuation.resume(returning: try downsample(image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func makeThumbnail(from rawData: Data) async throws -> VehiclePhotoThumb {
        try await withCheckedThrowingContinuation { continuation in
            diskQueue.async {
                guard let image = UIImage(data: rawData) else {
                    continuation.resume(throwing: PhotoStoreError.invalidImage)
                    return
                }
                do {
                    continuation.resume(returning: try downsample(image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Back-compat for call sites that still expect JPEG bytes only.
    static func makeThumbnailJPEG(from image: UIImage) async throws -> Data {
        let thumb = try await makeThumbnail(from: image)
        return thumb.data
    }

    static func makeThumbnailJPEG(from rawData: Data) async throws -> Data {
        let thumb = try await makeThumbnail(from: rawData)
        return thumb.data
    }

    /// Display helper for road scene: punch near-white studio plates to clear.
    nonisolated static func markImageByRemovingLightBackdrop(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Soft punch: near-white / very light grey plates → clear (avoid eating light vehicles).
        let hard: UInt8 = 248
        let soft: UInt8 = 228
        var i = 0
        while i < pixels.count {
            let r = pixels[i]
            let g = pixels[i + 1]
            let b = pixels[i + 2]
            let a = pixels[i + 3]
            if a > 0 {
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let chroma = Int(maxC) - Int(minC)
                if maxC >= hard, chroma < 18 {
                    pixels[i] = 0
                    pixels[i + 1] = 0
                    pixels[i + 2] = 0
                    pixels[i + 3] = 0
                } else if maxC >= soft, chroma < 22 {
                    let t = Double(maxC - soft) / Double(hard - soft)
                    let keep = max(0, min(1, 1 - t))
                    let fade = UInt8(max(0, min(255, Int(Double(a) * keep))))
                    if fade == 0 {
                        pixels[i] = 0
                        pixels[i + 1] = 0
                        pixels[i + 2] = 0
                        pixels[i + 3] = 0
                    } else {
                        // Premultiplied: scale RGB with alpha so edges don't flash white.
                        pixels[i] = UInt8(Int(r) * Int(fade) / Int(a))
                        pixels[i + 1] = UInt8(Int(g) * Int(fade) / Int(a))
                        pixels[i + 2] = UInt8(Int(b) * Int(fade) / Int(a))
                        pixels[i + 3] = fade
                    }
                }
            }
            i += bytesPerPixel
        }

        guard let out = context.makeImage() else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Fraction of pixels with meaningful alpha (0…1). Used to drop over-punched marks.
    nonisolated static func opaquePixelCoverage(_ image: UIImage, alphaThreshold: UInt8 = 32) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return 0 }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var opaque = 0
        let total = width * height
        var i = 3
        while i < pixels.count {
            if pixels[i] > alphaThreshold { opaque += 1 }
            i += bytesPerPixel
        }
        return Double(opaque) / Double(total)
    }

    /// True when punch (or a blank asset) left almost nothing visible — prefer SF Symbol.
    nonisolated static func markImageIsVisuallyEmpty(_ image: UIImage) -> Bool {
        opaquePixelCoverage(image) < 0.02
    }

    /// Road scene: cutout PNGs keep the large sit-on-road layout; full plates use the smaller sticker layout.
    /// Call once when the thumb changes — never inside TimelineView ticks.
    nonisolated static func isRoadCutoutMark(_ image: UIImage) -> Bool {
        imageHasAlpha(image)
            && opaquePixelCoverage(image) < MilehoundRoadVehicleMarkLayout.cutoutMaxOpaqueCoverage
    }

    /// Road scene mark: punch the light plate, but never hand back an unusable image.
    /// A light-coloured vehicle can be eaten by the punch — then the original photo is better
    /// than an empty frame (rule: photo when there is a photo, symbol only when there is none).
    /// Do not use for Live Activity — punch turns light cars into silhouettes on lock screen blur.
    nonisolated static func markImageForDisplay(_ image: UIImage) -> UIImage {
        let punched = markImageByRemovingLightBackdrop(image)
        return markImageIsVisuallyEmpty(punched) ? image : punched
    }

    /// True only when the bitmap can hold alpha *and* at least one sampled pixel is translucent.
    /// (UIKit often tags fully opaque renders as premultipliedLast.)
    nonisolated static func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        switch cgImage.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        case .alphaOnly:
            return true
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return containsTranslucentPixel(cgImage)
        @unknown default:
            return containsTranslucentPixel(cgImage)
        }
    }

    nonisolated private static func containsTranslucentPixel(_ cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return false }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        let stepX = max(1, width / 16)
        let stepY = max(1, height / 16)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
                context.draw(
                    cgImage,
                    in: CGRect(x: -x, y: -y, width: width, height: height)
                )
                if pixel[3] < 250 {
                    return true
                }
                x += stepX
            }
            y += stepY
        }
        return false
    }

    nonisolated private static func downsample(_ image: UIImage) throws -> VehiclePhotoThumb {
        let preservesAlpha = imageHasAlpha(image)
        let pixelWidth = max(1, image.size.width * image.scale)
        let pixelHeight = max(1, image.size.height * image.scale)
        let longest = max(pixelWidth, pixelHeight)
        let output: UIImage
        if longest > maxPixelSize {
            let ratio = maxPixelSize / longest
            let newSize = CGSize(
                width: max(1, (pixelWidth * ratio).rounded(.down)),
                height: max(1, (pixelHeight * ratio).rounded(.down))
            )
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = !preservesAlpha
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            output = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else if image.scale != 1 {
            let newSize = CGSize(width: pixelWidth, height: pixelHeight)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = !preservesAlpha
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            output = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            output = image
        }

        if preservesAlpha || imageHasAlpha(output) {
            guard let data = output.pngData() else { throw PhotoStoreError.encodeFailed }
            return VehiclePhotoThumb(data: data, format: .png)
        }
        guard let data = output.jpegData(compressionQuality: jpegQuality) else {
            throw PhotoStoreError.encodeFailed
        }
        return VehiclePhotoThumb(data: data, format: .jpeg)
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
                    try data.write(to: url, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    enum PhotoStoreError: Error {
        case invalidImage
        case encodeFailed
    }
}
