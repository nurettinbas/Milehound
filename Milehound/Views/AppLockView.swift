import SwiftUI

struct AppLockView: View {
    @Environment(AppLockService.self) private var appLockService
    @Environment(\.milehoundLayout) private var layout
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            AtmosphericBackground()

            if layout.layoutClass == .duoOpen {
                MilehoundPaneSplit {
                    MilehoundBrandMark(showsWordmark: true, symbolSize: 96)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } focus: {
                    lockCard
                        .milehoundPaneCard()
                }
            } else {
                lockCard
                    .milehoundPaneCard()
            }
        }
    }

    private var lockCard: some View {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .glassAccentForeground()
                Text(L10n.appLockTitle)
                    .font(.title2)
                if !appLockService.canUseDeviceAuthentication {
                    Text(L10n.appLockUnavailable)
                        .font(.caption)
                        .glassSecondaryInk()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button(L10n.appLockUnlock) {
                    Task { @MainActor in
                        _ = await appLockService.authenticateIfNeeded(enabled: settings.appLockEnabled)
                    }
                }
                .milehoundProminentButton()
            }
            .padding(28)
            .glassCard(contentInset: 0)
            .padding(.horizontal, 32)
    }
}
