import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum VehiclePhotoCaptureMode: Equatable, Hashable {
    case gallery
    case camera
}

enum VehiclePhotoSourceAction: Equatable {
    case library
    case camera
    case cancel
}

/// Single sheet identity so source → capture expands in place (no dismiss / re-present).
enum VehiclePhotoSheetRoute: Identifiable, Equatable {
    case flow

    var id: String { "vehicle-photo-flow" }
}

enum VehiclePhotoFlowPhase: Equatable {
    case source
    case capture(VehiclePhotoCaptureMode)
}

/// Detent sizes for the unified vehicle photo sheet.
enum VehiclePhotoFlowDetents {
    static func sourceHeight(cameraAvailable: Bool) -> CGFloat {
        cameraAvailable ? 340 : 280
    }

    static var captureFraction: CGFloat { 0.72 }

    static func source(cameraAvailable: Bool) -> PresentationDetent {
        .height(sourceHeight(cameraAvailable: cameraAvailable))
    }

    static var capture: PresentationDetent { .fraction(captureFraction) }
}

/// Maps the atmospheric source dialog choice to the capture overlay mode.
enum VehiclePhotoCaptureHandoff {
    static func pendingMode(after action: VehiclePhotoSourceAction) -> VehiclePhotoCaptureMode? {
        switch action {
        case .library: return .gallery
        case .camera: return .camera
        case .cancel: return nil
        }
    }
}

/// Unified source → capture sheet.
/// Opens at source height (no empty 72% host). Content always fills the sheet so detent
/// stretch + camera/gallery are one surface — never a tall blank layer behind a short card.
struct VehiclePhotoFlowSheet: View {
    var copy: PhotoSourceCopy = .vehicle
    var onPicked: (UIImage) -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: VehiclePhotoFlowPhase = .source
    @State private var selectedDetent: PresentationDetent
    @State private var isCaptureProcessing = false
    /// Kept mounted after first expand so the preview isn't a second growing layer.
    @State private var captureMode: VehiclePhotoCaptureMode?

    private var canUseCamera: Bool { VehicleInlineCameraView.isCameraAvailable }
    private var sourceDetent: PresentationDetent {
        VehiclePhotoFlowDetents.source(cameraAvailable: canUseCamera)
    }
    private var captureDetent: PresentationDetent { VehiclePhotoFlowDetents.capture }
    private var isSource: Bool {
        if case .source = phase { return true }
        return false
    }

    init(
        copy: PhotoSourceCopy = .vehicle,
        onPicked: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.copy = copy
        self.onPicked = onPicked
        self.onCancel = onCancel
        let camera = VehicleInlineCameraView.isCameraAvailable
        _selectedDetent = State(
            initialValue: VehiclePhotoFlowDetents.source(cameraAvailable: camera)
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            sheetChrome

            if let captureMode {
                VehiclePhotoCaptureSheet(
                    initialMode: captureMode,
                    onPicked: onPicked,
                    onCancel: shrinkToSource,
                    isProcessing: $isCaptureProcessing
                )
                // Identity follows Library vs Camera so @State mode can't stick on the wrong pane.
                .id(captureMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isSource ? 0 : 1)
                .allowsHitTesting(!isSource)
            }

            VehiclePhotoSourceSheet(
                copy: copy,
                canUseCamera: canUseCamera,
                onLibrary: { expand(to: .gallery) },
                onCamera: { expand(to: .camera) },
                onCancel: onCancel
            )
            .opacity(isSource ? 1 : 0)
            .allowsHitTesting(isSource)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([sourceDetent, captureDetent], selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground { sheetChrome }
        .interactiveDismissDisabled(isCaptureProcessing)
        .onChange(of: selectedDetent) { _, newValue in
            syncPhase(with: newValue)
        }
    }

    private var sheetChrome: some View {
        ZStack {
            AtmosphericBackground(style: .full)
                .opacity(isSource ? 1 : 0)
            Color.black.opacity(0.92)
                .opacity(isSource ? 0 : 1)
        }
        .ignoresSafeArea()
    }

    private func expand(to mode: VehiclePhotoCaptureMode) {
        captureMode = mode

        if reduceMotion {
            selectedDetent = captureDetent
            phase = .capture(mode)
            return
        }

        withAnimation(MilehoundMotion.photoSheetExpand) {
            selectedDetent = captureDetent
            phase = .capture(mode)
        }
    }

    private func shrinkToSource() {
        isCaptureProcessing = false

        if reduceMotion {
            phase = .source
            selectedDetent = sourceDetent
            captureMode = nil
            return
        }

        withAnimation(MilehoundMotion.photoSheetExpand) {
            phase = .source
            selectedDetent = sourceDetent
        }
        // Tear down after shrink so the next Library/Camera expand mounts the correct pane.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard case .source = phase else { return }
            captureMode = nil
        }
    }

    /// Drag must not leave an empty tall sheet over the source dialog.
    private func syncPhase(with detent: PresentationDetent) {
        switch (isSource, detent == captureDetent) {
        case (true, true):
            // Expand only via Library / Camera.
            selectedDetent = sourceDetent
        case (false, false):
            if reduceMotion {
                phase = .source
            } else {
                withAnimation(MilehoundMotion.photoSheetExpand) {
                    phase = .source
                }
            }
        default:
            break
        }
    }
}

/// ~72% capture content: recent grid + All Photos + inline camera (hosted inside `VehiclePhotoFlowSheet`).
struct VehiclePhotoCaptureSheet: View {
    var initialMode: VehiclePhotoCaptureMode
    var onPicked: (UIImage) -> Void
    var onCancel: () -> Void
    @Binding var isProcessing: Bool

    @StateObject private var loader = VehiclePhotoLibraryLoader()
    @State private var mode: VehiclePhotoCaptureMode
    /// Mode the sheet was opened with (controls Back on the camera pane).
    @State private var entryMode: VehiclePhotoCaptureMode
    @State private var isPhotosPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?

    private var canUseCamera: Bool { VehicleInlineCameraView.isCameraAvailable }

    init(
        initialMode: VehiclePhotoCaptureMode = .gallery,
        onPicked: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void,
        isProcessing: Binding<Bool> = .constant(false)
    ) {
        self.initialMode = initialMode
        self.onPicked = onPicked
        self.onCancel = onCancel
        _isProcessing = isProcessing
        _mode = State(initialValue: initialMode)
        _entryMode = State(initialValue: initialMode)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            Group {
                switch mode {
                case .gallery:
                    VehiclePhotoLibraryGrid(
                        loader: loader,
                        canUseCamera: canUseCamera,
                        onSelectAsset: { id in
                            Task { await pickAsset(id) }
                        },
                        onOpenCamera: {
                            MilehoundHaptics.selection()
                            mode = .camera
                        },
                        onAllPhotos: {
                            MilehoundHaptics.selection()
                            isPhotosPickerPresented = true
                        },
                        onBack: {
                            MilehoundHaptics.selection()
                            onCancel()
                        },
                        onOpenSettings: openSettings
                    )
                case .camera:
                    VehicleInlineCameraView(
                        isActive: mode == .camera,
                        onCapture: { image in
                            finish(with: image)
                        },
                        onBack: {
                            MilehoundHaptics.selection()
                            if entryMode == .camera {
                                onCancel()
                            } else {
                                mode = .gallery
                            }
                        },
                        onOpenLibrary: {
                            mode = .gallery
                        },
                        onPermissionDenied: {}
                    )
                }
            }

            if isProcessing {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            }
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $photoPickerItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await importPickerItem(item) }
        }
        .onChange(of: initialMode) { _, newMode in
            mode = newMode
            entryMode = newMode
        }
        // Photos auth only for gallery — Take Photo must not prompt the library dialog.
        .task(id: mode) {
            guard mode == .gallery else { return }
            await loader.prepare()
        }
        .onDisappear {
            loader.tearDown()
        }
    }

    private func pickAsset(_ localIdentifier: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        guard let image = await loader.requestFullImage(localIdentifier: localIdentifier) else {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
            return
        }
        finish(with: image)
    }

    private func importPickerItem(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer {
            isProcessing = false
            photoPickerItem = nil
        }
        do {
            guard let picked = try await item.loadTransferable(type: VehiclePickedImage.self),
                  let image = UIImage(data: picked.data) else {
                AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
                return
            }
            finish(with: image)
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
        }
    }

    private func finish(with image: UIImage) {
        MilehoundHaptics.selection()
        onPicked(image)
    }

    private func openSettings() {
        SystemSettingsLink.openAppPage()
    }
}

struct VehiclePickedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            VehiclePickedImage(data: data)
        }
    }
}

/// Host photo sheets on a NavigationStack root (not inside a List row) so the first tap sticks.
struct VehiclePhotoFlowSheetModifier: ViewModifier {
    @Binding var photoSheet: VehiclePhotoSheetRoute?
    @Binding var pendingFramingImage: UIImage?

    func body(content: Content) -> some View {
        content
            .sheet(item: $photoSheet) { _ in
                VehiclePhotoFlowSheet(
                    onPicked: { image in
                        pendingFramingImage = image
                        photoSheet = nil
                    },
                    onCancel: {
                        photoSheet = nil
                    }
                )
            }
    }
}

extension View {
    func vehiclePhotoFlowSheets(
        photoSheet: Binding<VehiclePhotoSheetRoute?>,
        pendingFramingImage: Binding<UIImage?>
    ) -> some View {
        modifier(
            VehiclePhotoFlowSheetModifier(
                photoSheet: photoSheet,
                pendingFramingImage: pendingFramingImage
            )
        )
    }
}
