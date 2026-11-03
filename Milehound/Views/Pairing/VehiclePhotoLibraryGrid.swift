import Photos
import SwiftUI
import UIKit

struct VehiclePhotoLibraryGrid: View {
    @ObservedObject var loader: VehiclePhotoLibraryLoader
    var canUseCamera: Bool
    var onSelectAsset: (String) -> Void
    var onOpenCamera: () -> Void
    var onAllPhotos: () -> Void
    var onBack: () -> Void
    var onOpenSettings: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        GeometryReader { geo in
            let side = max((geo.size.width - 4) / 3, 1)
            ZStack(alignment: .bottom) {
                content(cellSide: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomChrome
            }
            .onAppear {
                loader.setThumbnailSide(side, scale: UIScreen.main.scale)
            }
            .onChange(of: side) { _, newSide in
                loader.setThumbnailSide(newSide, scale: UIScreen.main.scale)
            }
        }
    }

    @ViewBuilder
    private func content(cellSide: CGFloat) -> some View {
        switch loader.authorization {
        case .undetermined:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            permissionDenied
        case .authorized:
            if loader.assetLocalIdentifiers.isEmpty && !loader.isLoading {
                emptyLibrary
            } else {
                assetGrid(cellSide: cellSide)
            }
        }
    }

    private func assetGrid(cellSide: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(loader.assetLocalIdentifiers, id: \.self) { id in
                    VehiclePhotoLibraryThumbCell(
                        localIdentifier: id,
                        side: cellSide,
                        loader: loader,
                        onTap: { onSelectAsset(id) }
                    )
                    .onAppear {
                        loader.updateVisibleCache(identifiers: nearbyIdentifiers(around: id))
                    }
                }
            }
            .padding(.bottom, 88)
        }
    }

    private var bottomChrome: some View {
        HStack(spacing: 12) {
            circularControl(systemImage: "chevron.left", accessibility: L10n.cancel, action: onBack)

            if canUseCamera {
                circularControl(
                    systemImage: "camera.fill",
                    accessibility: L10n.pairingTabVehiclePhotoCamera,
                    action: onOpenCamera
                )
            }

            Spacer(minLength: 0)

            Button(action: onAllPhotos) {
                Text(L10n.pairingTabVehiclePhotoAllPhotos)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        GlassToolbarControlBackground(shape: Capsule(style: .continuous))
                    }
            }
            .buttonStyle(VehiclePhotoPressStyle())
            .accessibilityLabel(L10n.pairingTabVehiclePhotoAllPhotos)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var permissionDenied: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle.weight(.semibold))
                .glassSecondaryInk()
            Text(L10n.pairingTabVehiclePhotoLibraryDeniedTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(L10n.pairingTabVehiclePhotoLibraryDeniedMessage)
                .font(.subheadline)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
            Button(L10n.pairingTabVehiclePhotoOpenSettings, action: onOpenSettings)
                .milehoundProminentButton()
                .tint(MilehoundBrandColors.brandBottom)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .glassSecondaryInk()
            Text(L10n.pairingTabVehiclePhotoLibraryEmpty)
                .font(.subheadline)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func circularControl(
        systemImage: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    GlassToolbarControlBackground(shape: Circle())
                }
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .accessibilityLabel(accessibility)
    }

    private func nearbyIdentifiers(around id: String) -> [String] {
        guard let index = loader.assetLocalIdentifiers.firstIndex(of: id) else { return [id] }
        let start = max(index - 18, 0)
        let end = min(index + 18, loader.assetLocalIdentifiers.count)
        return Array(loader.assetLocalIdentifiers[start..<end])
    }
}

private struct VehiclePhotoLibraryThumbCell: View {
    let localIdentifier: String
    let side: CGFloat
    @ObservedObject var loader: VehiclePhotoLibraryLoader
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color.primary.opacity(0.08)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: side, height: side)
            .clipped()
        }
        .buttonStyle(.glassPlainHit)
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
    }

    private func load() {
        cancel()
        requestID = loader.requestThumbnail(localIdentifier: localIdentifier) { result in
            Task { @MainActor in
                image = result
            }
        }
    }

    private func cancel() {
        loader.cancelRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}
