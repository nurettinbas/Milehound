import LocalAuthentication
import SwiftUI

@MainActor
@Observable
final class AppLockService {
    private(set) var isUnlocked = true

    var canUseDeviceAuthentication: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticateIfNeeded(enabled: Bool) async -> Bool {
        guard enabled else {
            isUnlocked = true
            return true
        }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = false
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: L10n.appLockReason
            )
            isUnlocked = success
            return success
        } catch {
            isUnlocked = false
            return false
        }
    }

    func lock() {
        isUnlocked = false
    }
}
