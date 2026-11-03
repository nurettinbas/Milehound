import Foundation
import SwiftUI

enum ToastHapticStyle: Equatable {
    case success
    case destructive
    case warning
    case merge
    case automation
    case personalRecord
}

enum ToastSymbolAnimation: Equatable {
    case bounce
    case wiggle
    case pulse
    case rotate
}

enum ToastEmblemTone: Equatable {
    case success
    case destructive
    case warning
    case palette
    case gold

    func fill(scheme: ColorScheme, palette: ShellPalette) -> LinearGradient {
        switch self {
        case .success:
            return LinearGradient(
                colors: [
                    LightGlassPalette.success,
                    LightGlassPalette.success.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .destructive:
            return LinearGradient(
                colors: [
                    LightGlassPalette.destructive,
                    Color(red: 0.86, green: 0.22, blue: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .warning:
            return LinearGradient(
                colors: [
                    LightGlassPalette.paused,
                    Color(red: 0.93, green: 0.48, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .palette:
            let tint = palette.tintColor(for: scheme)
            return LinearGradient(
                colors: [tint.opacity(0.95), tint.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .gold:
            let dark = scheme == .dark
            return LinearGradient(
                colors: [
                    AchievementTheme.hex(dark ? 0xD4A84A : 0xF3D08A),
                    AchievementTheme.hex(dark ? 0x9A6A12 : 0xC48A1A)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    func glow(scheme: ColorScheme, palette: ShellPalette) -> Color {
        switch self {
        case .success:
            LightGlassPalette.success
        case .destructive:
            LightGlassPalette.destructive
        case .warning:
            LightGlassPalette.paused
        case .palette:
            palette.tintColor(for: scheme)
        case .gold:
            AchievementTheme.hex(scheme == .dark ? 0xD4A84A : 0xF3D08A)
        }
    }
}

enum ToastKind: Equatable {
    case saved
    case tipThanks
    case deleted
    case placeSaved
    case vehicleSaved
    case vehicleReminderSaved
    case vehicleExpenseSaved
    case tripSaved
    case journalSaved
    case categoryAdded
    case categoryDeleted
    case orphanSaved
    case tripsMerged
    case shortcutsGuideFinished
    case shortcutsAutomationReached
    case categoryAccepted
    case journalTitleRequired
    case tripNotFound
    case personalRecord(PersonalRecordBreak)

    var message: String {
        switch self {
        case .saved: L10n.toastSaved
        case .tipThanks: L10n.toastTipThanks
        case .deleted: L10n.toastDeleted
        case .placeSaved: L10n.toastPlaceSaved
        case .vehicleSaved: L10n.toastVehicleSaved
        case .vehicleReminderSaved: L10n.toastVehicleReminderSaved
        case .vehicleExpenseSaved: L10n.toastVehicleExpenseSaved
        case .tripSaved: L10n.toastTripSaved
        case .journalSaved: L10n.toastJournalSaved
        case .categoryAdded: L10n.toastCategoryAdded
        case .categoryDeleted: L10n.toastCategoryDeleted
        case .orphanSaved: L10n.toastOrphanSaved
        case .tripsMerged: L10n.toastTripsMerged
        case .shortcutsGuideFinished: L10n.toastShortcutsGuideFinished
        case .shortcutsAutomationReached: L10n.toastShortcutsAutomationReached
        case .categoryAccepted: L10n.toastCategoryAccepted
        case .journalTitleRequired: L10n.journalTitleRequired
        case .tripNotFound: L10n.toastTripNotFound
        case .personalRecord(let payload): payload.accessibilityMessage
        }
    }

    var systemImage: String {
        switch self {
        case .saved:
            "checkmark.circle.fill"
        case .tipThanks:
            "heart.fill"
        case .tripSaved:
            "map.fill"
        case .orphanSaved:
            "flag.checkered"
        case .placeSaved:
            "mappin.and.ellipse"
        case .vehicleSaved:
            "car.fill"
        case .vehicleReminderSaved:
            "bell.badge.fill"
        case .vehicleExpenseSaved:
            "creditcard.fill"
        case .journalSaved:
            "book.closed.fill"
        case .categoryAdded:
            "folder.fill.badge.plus"
        case .categoryAccepted:
            "sparkles"
        case .categoryDeleted, .deleted:
            "trash.fill"
        case .tripsMerged:
            "arrow.triangle.merge"
        case .shortcutsGuideFinished:
            "wand.and.stars"
        case .shortcutsAutomationReached:
            "antenna.radiowaves.left.and.right"
        case .journalTitleRequired, .tripNotFound:
            "exclamationmark.triangle.fill"
        case .personalRecord:
            "trophy.fill"
        }
    }

    var symbolAnimation: ToastSymbolAnimation {
        switch self {
        case .vehicleReminderSaved, .deleted, .categoryDeleted, .journalTitleRequired, .tripNotFound:
            .wiggle
        case .categoryAccepted, .shortcutsGuideFinished, .shortcutsAutomationReached:
            .pulse
        case .personalRecord:
            .bounce
        default:
            .bounce
        }
    }

    var emblemTone: ToastEmblemTone {
        switch self {
        case .deleted, .categoryDeleted:
            .destructive
        case .journalTitleRequired, .tripNotFound:
            .warning
        case .tripSaved, .vehicleSaved, .vehicleReminderSaved, .journalSaved, .categoryAccepted, .tripsMerged, .shortcutsGuideFinished, .shortcutsAutomationReached, .tipThanks:
            .palette
        case .personalRecord:
            .gold
        default:
            .success
        }
    }

    var hapticStyle: ToastHapticStyle {
        switch self {
        case .deleted, .categoryDeleted:
            .destructive
        case .journalTitleRequired, .tripNotFound:
            .warning
        case .tripsMerged:
            .merge
        case .shortcutsAutomationReached:
            .automation
        case .personalRecord:
            .personalRecord
        default:
            .success
        }
    }

    var dwellSeconds: TimeInterval {
        switch self {
        case .personalRecord: 2.8
        default: 2
        }
    }
}

@MainActor
@Observable
final class ToastPresenter {
    static let shared = ToastPresenter()

    var kind: ToastKind?
    var isPresented = false

    private var dismissTask: Task<Void, Never>?
    private var clearKindTask: Task<Void, Never>?
    private var creditsQueuedKind: ToastKind?
    private var creditsFallbackTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?

    func show(_ kind: ToastKind, playHaptic: Bool = true) {
        followTask?.cancel()
        followTask = nil
        dismissTask?.cancel()
        clearKindTask?.cancel()
        self.kind = kind
        withAnimation(MilehoundMotion.toastSpring) {
            isPresented = true
        }
        if playHaptic, !UITestSupport.isEnabled {
            MilehoundHaptics.playToast(kind.hapticStyle)
        }
        let dwell = kind.dwellSeconds
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(MilehoundMotion.toastDismiss) {
            isPresented = false
        }
        // Keep `kind` until the exit transition finishes so removal isn't abrupt.
        clearKindTask?.cancel()
        clearKindTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isPresented else { return }
                self.kind = nil
            }
        }
    }

    func queueAfterRecordingCredits(_ kind: ToastKind) {
        creditsFallbackTask?.cancel()
        creditsQueuedKind = kind
        creditsFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.flushRecordingCreditsQueue()
            }
        }
    }

    func flushRecordingCreditsQueue() {
        creditsFallbackTask?.cancel()
        creditsFallbackTask = nil
        guard let kind = creditsQueuedKind else { return }
        creditsQueuedKind = nil
        show(kind)
    }

    func queueFollowingCurrent(_ kind: ToastKind) {
        followTask?.cancel()
        followTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.show(kind)
            }
        }
    }
}

struct ToastHostModifier: ViewModifier {
    var clearsTabBar: Bool = false
    var extraBottomPadding: CGFloat = 0

    @Bindable private var presenter = ToastPresenter.shared
    @Bindable private var chrome = SideColumnChromeState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if presenter.isPresented, let kind = presenter.kind {
                        toastContent(for: kind)
                            .padding(.horizontal, GlassTokens.panelHorizontalInset)
                            .padding(.bottom, bottomPadding(in: proxy))
                            .frame(maxWidth: .infinity)
                            .transition(MilehoundMotion.toastTransition(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .zIndex(999)
        }
    }

    private func bottomPadding(in proxy: GeometryProxy) -> CGFloat {
        let safeBottom = proxy.safeAreaInsets.bottom
        if clearsTabBar, let lift = tabBarLift(windowHeight: proxy.size.height) {
            return lift + extraBottomPadding
        }
        if clearsTabBar, chrome.tabBarFrame == nil {
            return safeBottom + GlassTokens.toastTabBarFallbackClearance + extraBottomPadding
        }
        return max(safeBottom, 16) + extraBottomPadding
    }

    /// Distance from the window bottom to just above a bottom tab platter.
    private func tabBarLift(windowHeight: CGFloat) -> CGFloat? {
        guard let bar = chrome.tabBarFrame, bar.width > 1, bar.height > 1 else { return nil }
        guard !SideColumnChromeResolver.isSideTabBar(bar) else { return nil }
        let height = chrome.windowSize.height > 1 ? chrome.windowSize.height : windowHeight
        guard height > 1 else {
            return bar.height + GlassTokens.toastTabBarGap
        }
        return max(0, height - bar.minY) + GlassTokens.toastTabBarGap
    }

    @ViewBuilder
    private func toastContent(for kind: ToastKind) -> some View {
        if case .personalRecord(let payload) = kind {
            RecordToastView(payload: payload)
        } else {
            ToastView(kind: kind)
        }
    }
}

extension View {
    func toastHost(clearsTabBar: Bool = false, extraBottomPadding: CGFloat = 0) -> some View {
        modifier(ToastHostModifier(clearsTabBar: clearsTabBar, extraBottomPadding: extraBottomPadding))
    }
}
