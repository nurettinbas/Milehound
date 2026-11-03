import SwiftUI
import UIKit

extension View {
    /// Reports keyboard overlap height for this view’s window bounds.
    /// Local only — does not broadcast to other screens.
    func onKeyboardOverlap(
        _ overlap: Binding<CGFloat>,
        animationDuration: Binding<TimeInterval> = .constant(0)
    ) -> some View {
        background(
            KeyboardOverlapInstaller(
                overlap: overlap,
                animationDuration: animationDuration
            )
        )
    }
}

private struct KeyboardOverlapInstaller: UIViewRepresentable {
    @Binding var overlap: CGFloat
    @Binding var animationDuration: TimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator(overlap: $overlap, animationDuration: $animationDuration)
    }

    func makeUIView(context: Context) -> KeyboardOverlapUIView {
        let view = KeyboardOverlapUIView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: KeyboardOverlapUIView, context: Context) {
        context.coordinator.overlap = $overlap
        context.coordinator.animationDuration = $animationDuration
        uiView.coordinator = context.coordinator
    }

    static func dismantleUIView(_ uiView: KeyboardOverlapUIView, coordinator: Coordinator) {
        uiView.uninstall()
    }

    @MainActor
    final class Coordinator {
        var overlap: Binding<CGFloat>
        var animationDuration: Binding<TimeInterval>

        init(overlap: Binding<CGFloat>, animationDuration: Binding<TimeInterval>) {
            self.overlap = overlap
            self.animationDuration = animationDuration
        }

        func apply(overlap value: CGFloat, duration: TimeInterval) {
            animationDuration.wrappedValue = duration
            overlap.wrappedValue = max(0, value)
        }
    }
}

/// Selector-based observers avoid `@Sendable` closures that cannot take non-Sendable `Notification`
/// (Swift 6 language mode).
private final class KeyboardOverlapUIView: UIView {
    weak var coordinator: KeyboardOverlapInstaller.Coordinator?
    private var isObserving = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            installIfNeeded()
        } else {
            uninstall()
        }
    }

    func uninstall() {
        guard isObserving else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        isObserving = false
    }

    private func installIfNeeded() {
        guard !isObserving else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        isObserving = true
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        handle(notification, forcingHidden: false)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        handle(notification, forcingHidden: true)
    }

    private func handle(_ notification: Notification, forcingHidden: Bool) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
            .doubleValue ?? 0.25

        let endFrame = forcingHidden
            ? nil
            : notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect

        // NotificationCenter delivers keyboard notifications on the main thread.
        MainActor.assumeIsolated {
            apply(endFrame: endFrame, duration: duration)
        }
    }

    @MainActor
    private func apply(endFrame: CGRect?, duration: TimeInterval) {
        guard let endFrame, let window else {
            coordinator?.apply(overlap: 0, duration: duration)
            return
        }

        let selfInWindow = convert(bounds, to: window)
        let overlap = TripDetailKeyboardLayout.keyboardOverlap(
            endFrame: endFrame,
            in: selfInWindow
        )
        coordinator?.apply(overlap: overlap, duration: duration)
    }
}
