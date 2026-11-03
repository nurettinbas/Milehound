import SwiftUI
import UIKit

/// Restores the system edge-swipe pop when the SwiftUI back control is custom
/// (`navigationBarBackButtonHidden(true)`). Used on iOS 17–18 detail screens and on the
/// vehicle editor, which must block the pop while there are unsaved edits.
///
/// iOS 26 detail screens use the system back button and must not install this. A hidden
/// back button turns off the edge swipe and the full-screen content pop, and replacing
/// their delegate breaks the content pop. The vehicle screen therefore keeps the system
/// back button until there are unsaved edits, and only then installs this with
/// `disabled: true`. On iOS 26 it only disables the system pop gestures — it does not
/// replace their delegate.
struct NavigationInteractivePopEnabler: UIViewControllerRepresentable {
    var disabled: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(disabled: disabled)
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        context.coordinator.disabled = disabled
        uiViewController.coordinator = context.coordinator
        uiViewController.attachInteractivePopIfNeeded()
    }

    final class Controller: UIViewController {
        var coordinator: Coordinator?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachInteractivePopIfNeeded()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            coordinator?.restoreSystemGestures()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil {
                coordinator?.restoreSystemGestures()
            } else {
                attachInteractivePopIfNeeded()
            }
        }

        func attachInteractivePopIfNeeded() {
            guard let navigationController else { return }
            coordinator?.attach(to: navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var disabled: Bool
        private weak var navigationController: UINavigationController?
        private weak var installedGesture: UIGestureRecognizer?
        /// Gesture callbacks are not MainActor-isolated. The pointer is only swapped on the main thread.
        nonisolated(unsafe) private weak var originalDelegate: UIGestureRecognizerDelegate?

        init(disabled: Bool) {
            self.disabled = disabled
        }

        func attach(to navigationController: UINavigationController) {
            self.navigationController = navigationController
            if #available(iOS 26.0, *) {
                applySystemEnabled(on: navigationController)
                return
            }
            guard let gesture = navigationController.interactivePopGestureRecognizer else { return }
            let canPop = !disabled && navigationController.viewControllers.count > 1
            gesture.isEnabled = canPop
            guard installedGesture !== gesture else { return }
            if gesture.delegate !== self {
                originalDelegate = gesture.delegate
            }
            gesture.delegate = self
            installedGesture = gesture
        }

        /// Pop finished or this screen left. Hand the gesture back. Do not leave it disabled.
        func restoreSystemGestures() {
            if #available(iOS 26.0, *) {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = true
                navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = true
            }
            if let gesture = installedGesture, gesture.delegate === self {
                gesture.delegate = originalDelegate
            }
            installedGesture = nil
            originalDelegate = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let canPop = !disabled && (navigationController?.viewControllers.count ?? 0) > 1
            guard canPop else { return false }
            return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return originalDelegate?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let originalDelegate, originalDelegate.responds(to: aSelector) {
                return originalDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }

        @available(iOS 26.0, *)
        private func applySystemEnabled(on navigationController: UINavigationController) {
            let canPop = !disabled && navigationController.viewControllers.count > 1
            navigationController.interactivePopGestureRecognizer?.isEnabled = canPop
            navigationController.interactiveContentPopGestureRecognizer?.isEnabled = canPop
        }
    }
}

/// Fires only after a pop that stuck. A cancelled swipe calls `viewWillDisappear` and then
/// returns, and never reaches `viewDidDisappear`, so the detail session stays loaded.
struct NavigationDismissProbe: UIViewControllerRepresentable {
    var onDidPop: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onDidPop = onDidPop
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.onDidPop = onDidPop
    }

    final class Controller: UIViewController {
        var onDidPop: () -> Void = {}

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            guard isMovingFromParent || isBeingDismissed else { return }
            onDidPop()
        }
    }
}
