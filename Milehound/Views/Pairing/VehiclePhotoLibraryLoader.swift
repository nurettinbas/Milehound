import Photos
import UIKit

/// Loads a capped recent-photo list and serves thumbnails via `PHCachingImageManager`.
@MainActor
final class VehiclePhotoLibraryLoader: ObservableObject {
    nonisolated static let fetchLimit = 120

    enum AuthorizationState: Equatable {
        case undetermined
        case authorized
        case denied
    }

    @Published private(set) var authorization: AuthorizationState = .undetermined
    @Published private(set) var assetLocalIdentifiers: [String] = []
    @Published private(set) var isLoading = false

    private let imageManager = PHCachingImageManager()
    private var assetsByID: [String: PHAsset] = [:]
    private var orderedAssets: [PHAsset] = []
    private var cachedIDs = Set<String>()
    private var thumbnailPixelSize: CGSize = .zero

    func prepare() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            let next = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            applyAuthorization(next)
        default:
            applyAuthorization(status)
        }
        guard authorization == .authorized else {
            clearAssets()
            return
        }
        reloadAssets()
    }

    func setThumbnailSide(_ side: CGFloat, scale: CGFloat) {
        let px = max(side * scale, 1)
        let next = CGSize(width: px, height: px)
        guard next != thumbnailPixelSize else { return }
        thumbnailPixelSize = next
        stopCachingAll()
    }

    func updateVisibleCache(identifiers: [String]) {
        guard thumbnailPixelSize != .zero else { return }
        let next = Set(identifiers)
        let toStop = cachedIDs.subtracting(next)
        let toStart = next.subtracting(cachedIDs)
        if !toStop.isEmpty {
            let assets = toStop.compactMap { assetsByID[$0] }
            imageManager.stopCachingImages(
                for: assets,
                targetSize: thumbnailPixelSize,
                contentMode: .aspectFill,
                options: Self.thumbnailOptions
            )
        }
        if !toStart.isEmpty {
            let assets = toStart.compactMap { assetsByID[$0] }
            imageManager.startCachingImages(
                for: assets,
                targetSize: thumbnailPixelSize,
                contentMode: .aspectFill,
                options: Self.thumbnailOptions
            )
        }
        cachedIDs = next
    }

    @discardableResult
    func requestThumbnail(
        localIdentifier: String,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        guard let asset = assetsByID[localIdentifier], thumbnailPixelSize != .zero else {
            completion(nil)
            return PHInvalidImageRequestID
        }
        return imageManager.requestImage(
            for: asset,
            targetSize: thumbnailPixelSize,
            contentMode: .aspectFill,
            options: Self.thumbnailOptions
        ) { image, info in
            if (info?[PHImageResultIsDegradedKey] as? Bool) == true, image != nil {
                completion(image)
                return
            }
            completion(image)
        }
    }

    func cancelRequest(_ id: PHImageRequestID) {
        guard id != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(id)
    }

    func requestFullImage(localIdentifier: String) async -> UIImage? {
        guard let asset = assetsByID[localIdentifier] else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            var finished = false
            let finish: (UIImage?) -> Void = { image in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: image)
            }
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    finish(nil)
                    return
                }
                if info?[PHImageErrorKey] != nil {
                    finish(nil)
                    return
                }
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                finish(image)
            }
        }
    }

    func tearDown() {
        stopCachingAll()
        clearAssets()
    }

    // MARK: - Private

    private func applyAuthorization(_ status: PHAuthorizationStatus) {
        authorization = VehiclePhotoLibraryAuthMapping.state(from: status)
    }

    /// Recent-image fetch configuration (testable without hitting the photo library).
    nonisolated static func makeRecentImagesFetchOptions(limit: Int = fetchLimit) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return options
    }

    private func reloadAssets() {
        isLoading = true
        defer { isLoading = false }

        let options = Self.makeRecentImagesFetchOptions()
        let result = PHAsset.fetchAssets(with: options)
        var ordered: [PHAsset] = []
        var byID: [String: PHAsset] = [:]
        ordered.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            ordered.append(asset)
            byID[asset.localIdentifier] = asset
        }
        orderedAssets = ordered
        assetsByID = byID
        assetLocalIdentifiers = ordered.map(\.localIdentifier)
    }

    private func clearAssets() {
        orderedAssets = []
        assetsByID = [:]
        assetLocalIdentifiers = []
    }

    private func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
        cachedIDs.removeAll()
    }

    private static var thumbnailOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }
}

/// Maps Photos authorization into loader UI states (testable without Photos UI).
enum VehiclePhotoLibraryAuthMapping {
    static func state(from status: PHAuthorizationStatus) -> VehiclePhotoLibraryLoader.AuthorizationState {
        switch status {
        case .authorized, .limited: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }
}
