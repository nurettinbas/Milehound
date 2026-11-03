import Foundation
import SwiftUI

@MainActor
@Observable
final class AppErrorPresenter {
    static let shared = AppErrorPresenter()

    var message: String?
    var alertTitle = L10n.errorTitle
    var isPresented = false

    func present(_ message: String) {
        alertTitle = L10n.errorTitle
        self.message = message
        isPresented = true
    }

    func presentInfo(_ message: String) {
        alertTitle = L10n.infoTitle
        self.message = message
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        message = nil
    }
}

struct AppErrorAlertModifier: ViewModifier {
    @Bindable private var presenter = AppErrorPresenter.shared

    func body(content: Content) -> some View {
        content.alert(presenter.alertTitle, isPresented: $presenter.isPresented) {
            Button(L10n.ok, role: .cancel) { presenter.dismiss() }
        } message: {
            Text(presenter.message ?? "")
        }
    }
}

extension View {
    func appErrorAlert() -> some View {
        modifier(AppErrorAlertModifier())
    }
}
