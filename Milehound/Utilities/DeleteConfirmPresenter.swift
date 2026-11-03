import SwiftUI

enum DeleteConfirmKind {
    case generic
    case vehicle(isActivePaired: Bool)
    case journalRemove
    case category
    case installmentPlan(count: Int)
    case vehiclePhoto
    case notificationsAll

    var title: String {
        switch self {
        case .generic, .category, .notificationsAll:
            L10n.deleteConfirmTitle
        case .vehicle:
            L10n.pairingTabDeleteVehicleTitle
        case .journalRemove:
            L10n.deleteConfirmJournalRemoveTitle
        case .installmentPlan:
            L10n.vehicleExpenseDeletePlanTitle
        case .vehiclePhoto:
            L10n.pairingTabVehiclePhotoDeleteTitle
        }
    }

    var message: String {
        switch self {
        case .generic:
            L10n.deleteConfirmMessage
        case .vehicle(let isActivePaired):
            isActivePaired
                ? L10n.pairingTabDeleteVehicleMessageActive
                : L10n.pairingTabDeleteVehicleMessage
        case .journalRemove:
            L10n.deleteConfirmJournalRemoveMessage
        case .category:
            L10n.deleteConfirmCategoryMessage
        case .installmentPlan:
            L10n.deleteConfirmInstallmentPlanMessage
        case .vehiclePhoto:
            L10n.pairingTabVehiclePhotoDeleteMessage
        case .notificationsAll:
            L10n.deleteConfirmNotificationsAllMessage
        }
    }

    var confirmTitle: String {
        switch self {
        case .generic, .vehicle, .category:
            L10n.delete
        case .journalRemove:
            L10n.journalRemove
        case .installmentPlan(let count):
            L10n.vehicleExpenseDeletePlan(count)
        case .vehiclePhoto:
            L10n.pairingTabVehiclePhotoRemove
        case .notificationsAll:
            L10n.notificationsClearAll
        }
    }
}

/// Confirm overlay chrome: destructive delete vs prominent actions such as trip merge.
enum GlassConfirmRole: Equatable {
    case destructive
    case prominent
}

struct DeleteConfirmRequest {
    var title: String
    var message: String
    var confirmTitle: String
    var role: GlassConfirmRole
    var systemImage: String
    var onConfirm: () -> Void
}

@MainActor
@Observable
final class DeleteConfirmPresenter {
    static let shared = DeleteConfirmPresenter()

    var request: DeleteConfirmRequest?
    /// Blocking progress on the same root host as confirm (trip merge). Independent of
    /// `TripListView` so flipping this flag cannot rebuild the trip list.
    var progressMessage: String?

    var isProgressVisible: Bool { progressMessage != nil }

    var isBlocking: Bool { request != nil || progressMessage != nil }

    func confirm(_ kind: DeleteConfirmKind, perform: @escaping () -> Void) {
        present(
            title: kind.title,
            message: kind.message,
            confirmTitle: kind.confirmTitle,
            perform: perform
        )
    }

    func present(
        title: String,
        message: String,
        confirmTitle: String,
        role: GlassConfirmRole = .destructive,
        systemImage: String? = nil,
        perform: @escaping () -> Void
    ) {
        KeyboardDismiss.dismiss()
        progressMessage = nil
        request = DeleteConfirmRequest(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            role: role,
            systemImage: systemImage ?? Self.defaultSystemImage(for: role),
            onConfirm: perform
        )
        MilehoundHaptics.selection()
    }

    func cancel() {
        request = nil
    }

    func performConfirm() {
        let action = request?.onConfirm
        request = nil
        action?()
    }

    func showProgress(_ message: String) {
        request = nil
        progressMessage = message
    }

    func hideProgress() {
        progressMessage = nil
    }

    private static func defaultSystemImage(for role: GlassConfirmRole) -> String {
        switch role {
        case .destructive: "trash.circle.fill"
        case .prominent: "arrow.triangle.merge"
        }
    }
}

struct DeleteConfirmHostModifier: ViewModifier {
    @Bindable private var presenter = DeleteConfirmPresenter.shared
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isBlocking = presenter.isBlocking
        content
            // Do not implicit-animate the tab/list tree when the dialog appears.
            .animation(nil, value: isBlocking)
            // Swipe-open List rows steal the first tap. Block the tree under the
            // dialog so Cancel/Delete land on the overlay, not the list.
            .allowsHitTesting(!isBlocking)
            .overlay {
                ZStack {
                    if let request = presenter.request {
                        Color.black.opacity(0.46)
                            .ignoresSafeArea()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                DeleteConfirmPresenter.shared.cancel()
                            }
                            .accessibilityLabel(L10n.cancel)
                            .accessibilityAddTraits(.isButton)
                            .transition(.opacity)

                        DeleteConfirmCard(request: request)
                            .transition(cardTransition)
                    } else if let progressMessage = presenter.progressMessage {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                            .transition(.opacity)

                        GlassBlockingProgressCard(message: progressMessage)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.shellPalette, settings.shellPalette)
                .animation(overlayAnimation, value: isBlocking)
            }
    }

    private var overlayAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : MilehoundMotion.cardSpring
    }

    private var cardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.94))
    }
}

private struct DeleteConfirmCard: View {
    let request: DeleteConfirmRequest
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    private let buttonHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: request.systemImage)
                .font(.system(size: 44))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(request.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GlassText.primary(for: colorScheme))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(request.message)
                .font(.subheadline)
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                confirmActionButton(
                    title: L10n.cancel,
                    color: GlassText.primary(for: colorScheme)
                ) {
                    DeleteConfirmPresenter.shared.cancel()
                } chrome: {
                    GlassToolbarControlBackground(shape: Capsule(style: .continuous))
                }

                confirmActionButton(
                    title: request.confirmTitle,
                    color: Color.white
                ) {
                    DeleteConfirmPresenter.shared.performConfirm()
                } chrome: {
                    confirmFill
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 320)
        .glassCard(cornerRadius: GlassTokens.cardRadius, contentInset: 0)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var iconColor: Color {
        switch request.role {
        case .destructive:
            GlassSemantic.notificationBadge
        case .prominent:
            shellPalette.tintColor(for: colorScheme)
        }
    }

    @ViewBuilder
    private var confirmFill: some View {
        switch request.role {
        case .destructive:
            Capsule(style: .continuous)
                .fill(GlassSemantic.notificationBadge)
        case .prominent:
            Capsule(style: .continuous)
                .fill(shellPalette.tintColor(for: colorScheme))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                }
        }
    }

    /// Chrome is the control. `.plain` + Text would otherwise hit-test only the glyphs,
    /// so taps on the capsule padding would land on the card and do nothing.
    private func confirmActionButton<Chrome: View>(
        title: String,
        color: Color,
        action: @escaping () -> Void,
        @ViewBuilder chrome: () -> Chrome
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: buttonHeight)
                .background { chrome() }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.glassPlainHit)
        .contentShape(Capsule(style: .continuous))
    }
}

/// Merge / share-style blocking progress. Lives on the root host so the trip list
/// body is not invalidated when the flag flips.
private struct GlassBlockingProgressCard: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(shellPalette.tintColor(for: colorScheme))
            Text(message)
                .font(.subheadline.weight(.medium))
                .glassPrimaryInk()
        }
        .padding(28)
        .glassCard(cornerRadius: 16, contentInset: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    func deleteConfirmHost() -> some View {
        modifier(DeleteConfirmHostModifier())
    }

    /// Trailing swipe that only presents confirm. Do not use `Button(role: .destructive)`
    /// here — List treats that role as an immediate row delete, so Cancel would leave
    /// the row gone even though the model was not deleted.
    @ViewBuilder
    func confirmingDeleteSwipe(
        _ kind: DeleteConfirmKind = .generic,
        title: String = L10n.delete,
        systemImage: String = "trash",
        allowsFullSwipe: Bool = true,
        enabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        if enabled {
            swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                Button {
                    DeleteConfirmPresenter.shared.confirm(kind, perform: perform)
                } label: {
                    Label(title, systemImage: systemImage)
                }
                .destructiveTint()
            }
        } else {
            self
        }
    }
}
