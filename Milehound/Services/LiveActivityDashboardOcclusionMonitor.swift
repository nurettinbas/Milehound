import AVFoundation
import CallKit
import Foundation

/// Watches CarPlay phone calls so Live Activity can pause snapshot pushes and
/// refresh once when the dashboard tile comes back.
@MainActor
final class LiveActivityDashboardOcclusionMonitor: NSObject, CXCallObserverDelegate {
    static let shared = LiveActivityDashboardOcclusionMonitor()

    private let callObserver = CXCallObserver()
    private var onChange: ((Bool) -> Void)?
    private var lastOccluded = false
    private var didStart = false

    func start(onChange: @escaping (Bool) -> Void) {
        guard !didStart else { return }
        didStart = true
        self.onChange = onChange
        callObserver.setDelegate(self, queue: .main)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        publishIfNeeded()
    }

    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        dispatchDashboardOcclusionCheckToMainActor()
    }

    @objc nonisolated private func routeChanged(_ notification: Notification) {
        dispatchDashboardOcclusionCheckToMainActor()
    }

    static func handleChangeFromBackground() {
        shared.publishIfNeeded()
    }

    private func publishIfNeeded() {
        let occluded = LiveActivityDashboardPublishPolicy.isCarPlayCallOcclusion(
            hasActiveCall: callObserver.calls.contains { !$0.hasEnded },
            isCarAudioRoute: Self.isCarAudioConnected
        )
        guard occluded != lastOccluded else { return }
        lastOccluded = occluded
        onChange?(occluded)
    }

    static var isCarAudioConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
    }
}

private nonisolated func dispatchDashboardOcclusionCheckToMainActor() {
    Task { @MainActor in
        LiveActivityDashboardOcclusionMonitor.handleChangeFromBackground()
    }
}
