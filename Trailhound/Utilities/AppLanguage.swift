import SwiftUI
import WidgetKit

/// Languages that ship fully translated. System follows the iPhone.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case tr

    var id: String { rawValue }

    /// Endonym. Not localized: the row must stay recognizable in every language.
    var nativeName: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .tr: "Türkçe"
        }
    }

    /// English name, shown as the secondary line when it differs from the endonym.
    var englishName: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .tr: "Turkish"
        }
    }
}

@MainActor
@Observable
final class AppLanguageStore {
    static let shared = AppLanguageStore()

    private(set) var language: AppLanguage
    /// Bumped on every change so the root view rebuilds strings and dates.
    private(set) var revision = 0

    var locale: Locale {
        _ = revision
        return SharedLanguage.locale
    }

    private let defaults: UserDefaults

    init(userDefaults: UserDefaults? = nil) {
        let resolved = userDefaults ?? RecordingControlBridge.sharedDefaults()
        defaults = resolved
        if let raw = resolved.string(forKey: SharedLanguage.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else {
            language = .system
        }
    }

    func select(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: SharedLanguage.storageKey)
        switch language {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .en, .tr:
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        SharedLanguage.invalidate()
        revision += 1
        guard !UITestSupport.shouldSkipExternalEffects else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Reads the language revision and rebuilds its content so every `L10n` call picks up the new bundle.
struct AppLanguageRefresh<Content: View>: View {
    @Bindable private var store = AppLanguageStore.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        let _ = store.revision
        content()
            .environment(\.locale, store.locale)
    }
}
