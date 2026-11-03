import AVFoundation
import SwiftUI
import UIKit

/// Sheet-embedded camera: preview + shutter. Session starts/stops with `isActive`.
struct VehicleInlineCameraView: View {
    var isActive: Bool
    var onCapture: (UIImage) -> Void
    var onBack: () -> Void
    var onOpenLibrary: () -> Void
    var onPermissionDenied: () -> Void

    @StateObject private var model = VehicleInlineCameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOverflow = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VehicleCameraPreviewRepresentable(session: model.captureSession)
                .ignoresSafeArea()

            if model.authorization == .denied {
                VStack(spacing: 12) {
                    Text(L10n.pairingTabVehiclePhotoCameraDeniedTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(L10n.pairingTabVehiclePhotoCameraDeniedMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.55))
            }

            bottomChrome
        }
        .task(id: isActive) {
            await syncSession()
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .active, isActive {
                    await syncSession()
                } else {
                    await model.stop()
                }
            }
        }
        .onChange(of: model.authorization) { _, auth in
            if auth == .denied {
                onPermissionDenied()
            }
        }
        .onDisappear {
            Task { await model.stop() }
        }
        .confirmationDialog(
            L10n.pairingTabVehiclePhoto,
            isPresented: $showOverflow,
            titleVisibility: .hidden
        ) {
            Button(L10n.pairingTabVehiclePhotoChoose, action: onOpenLibrary)
            Button(L10n.cancel, role: .cancel) {}
        }
    }

    private var bottomChrome: some View {
        HStack {
            circularControl(systemImage: "chevron.left", accessibility: L10n.cancel, action: onBack)

            Spacer()

            Button {
                MilehoundHaptics.selection()
                Task {
                    if let image = await model.capturePhoto() {
                        onCapture(image)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 58, height: 58)
                }
            }
            .buttonStyle(VehiclePhotoPressStyle())
            .disabled(model.authorization != .authorized || !model.isRunning)
            .accessibilityLabel(L10n.pairingTabVehiclePhotoShutter)

            Spacer()

            circularControl(
                systemImage: "ellipsis",
                accessibility: L10n.pairingTabVehiclePhotoMore,
                action: { showOverflow = true }
            )
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
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

    private func syncSession() async {
        guard isActive else {
            await model.stop()
            return
        }
        await model.start()
    }

    static var isCameraAvailable: Bool {
        VehicleInlineCameraAvailability.isAvailable(
            hasBackCamera: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil,
            hasAnyVideoCamera: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) != nil
        )
    }
}

enum VehicleInlineCameraAvailability {
    static func isAvailable(hasBackCamera: Bool, hasAnyVideoCamera: Bool) -> Bool {
        hasBackCamera || hasAnyVideoCamera
    }
}

// MARK: - Model

@MainActor
final class VehicleInlineCameraModel: ObservableObject {
    enum Authorization: Equatable {
        case undetermined
        case authorized
        case denied
    }

    @Published private(set) var authorization: Authorization = .undetermined
    @Published private(set) var isRunning = false

    let captureSession = AVCaptureSession()
    private let engine: VehicleInlineCameraEngine

    init() {
        engine = VehicleInlineCameraEngine(session: captureSession)
    }

    func start() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            authorization = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
            guard granted else { return }
        default:
            authorization = .denied
            return
        }

        await engine.start()
        isRunning = true
    }

    func stop() async {
        await engine.stop()
        isRunning = false
    }

    func capturePhoto() async -> UIImage? {
        guard isRunning else { return nil }
        return await engine.capturePhoto()
    }
}

/// Runs AVCapture work off the main actor.
private final class VehicleInlineCameraEngine: NSObject, @unchecked Sendable {
    private let session: AVCaptureSession
    private let sessionQueue = DispatchQueue(label: "com.milehound.VehicleInlineCamera")
    private let photoOutput = AVCapturePhotoOutput()
    private var didConfigure = false
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    init(session: AVCaptureSession) {
        self.session = session
    }

    func start() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                configureIfNeeded()
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                captureContinuation = continuation
                let settings = AVCapturePhotoSettings()
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureIfNeeded() {
        guard !didConfigure else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()
        didConfigure = true
    }
}

extension VehicleInlineCameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage? = {
            guard error == nil, let data = photo.fileDataRepresentation() else { return nil }
            return UIImage(data: data)
        }()
        sessionQueue.async { [self] in
            captureContinuation?.resume(returning: image)
            captureContinuation = nil
        }
    }
}

// MARK: - Preview

private struct VehicleCameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
