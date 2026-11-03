import UIKit

/// Opens Settings when location was denied.
///
/// On iOS 27 a third-party app cannot open its own Location page. `app-prefs:` and
/// `settings-navigation:` are refused (`open` returns false). `app-settings:` opens the
/// Settings root. While status is When In Use, ask for Always with
/// `CLLocationManager.requestAlwaysAuthorization()` instead of sending the user here.
enum SystemSettingsLink {
    static var publicAppSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    @MainActor
    static func openLocationPermission() {
        openAppPage()
    }

    @MainActor
    static func openAppPage() {
        guard let url = publicAppSettingsURL else { return }
        UIApplication.shared.open(url)
    }
}
