import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = false
    var onConnected: (() -> Void)?

    private init() {
        ConnectivityChangeRelay.shared.install()
    }

    func startIfNeeded() {
        NetworkConnectivityProbe.activate()
    }

    static func applyConnectivityChangeFromBackground(_ connected: Bool) {
        shared.applyConnectivityChange(connected)
    }

    private func applyConnectivityChange(_ connected: Bool) {
        let wasConnected = isConnected
        isConnected = connected
        if connected && !wasConnected {
            onConnected?()
        }
    }
}

private extension Notification.Name {
    static let milehoundNetworkConnectivityChanged = Notification.Name("milehound.networkConnectivityChanged")
}

private enum NetworkConnectivityProbe {
    private static let queue = DispatchQueue(label: "com.milehound.network")
    nonisolated(unsafe) private static var isActive = false
    private static let monitor = NWPathMonitor()

    static func activate() {
        guard !isActive else { return }
        isActive = true

        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .milehoundNetworkConnectivityChanged,
                    object: connected
                )
            }
        }
        monitor.start(queue: queue)
    }
}

private final class ConnectivityChangeRelay: NSObject {
    nonisolated(unsafe) static let shared = ConnectivityChangeRelay()
    private var isInstalled = false

    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onConnectivityChanged(_:)),
            name: .milehoundNetworkConnectivityChanged,
            object: nil
        )
    }

    @objc nonisolated private func onConnectivityChanged(_ notification: Notification) {
        guard let connected = notification.object as? Bool else { return }
        Task { @MainActor in
            NetworkMonitor.applyConnectivityChangeFromBackground(connected)
        }
    }
}
