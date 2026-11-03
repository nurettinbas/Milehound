import Foundation

public enum SharedL10n {
    public static func text(_ key: String, bundle: Bundle = .main) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: SharedLanguage.localizedBundle(for: bundle)
        )
    }
}

/// App-group language (`system`, `en`, `tr`) resolved once per change.
/// The widget and the app each keep their own cache; `invalidate()` drops the app's after a change.
public enum SharedLanguage {
    public static let storageKey = "app.languageCode"

    private struct Cache {
        var stored: String?
        var source: Bundle
        var bundle: Bundle
        var locale: Locale
    }

    private final class CacheBox: @unchecked Sendable {
        var value: Cache?
    }

    private static let lock = NSLock()
    private static let cache = CacheBox()

    public static func invalidate() {
        lock.lock()
        cache.value = nil
        lock.unlock()
    }

    public static var locale: Locale {
        resolved().locale
    }

    public static func localizedBundle(for bundle: Bundle) -> Bundle {
        resolved(in: bundle).bundle
    }

    /// `en` or `tr` when the iPhone's language is one we ship. Otherwise nil (use the bundle as-is).
    public static func preferredSystemCode() -> String? {
        let globals = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        let list = globals ?? Locale.preferredLanguages
        for raw in list {
            let code = raw.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() }
            if code == "tr" || code == "en" { return code }
        }
        return nil
    }

    private static func resolved(in bundle: Bundle = .main) -> Cache {
        lock.lock()
        defer { lock.unlock() }
        let stored = RecordingControlBridge.sharedDefaults().string(forKey: storageKey)
        if let cached = cache.value, cached.stored == stored, cached.source === bundle {
            return cached
        }
        let code: String? = switch stored {
        case "en", "tr": stored
        default: preferredSystemCode()
        }
        let localized: Bundle
        if let code,
           let path = bundle.path(forResource: code, ofType: "lproj"),
           let match = Bundle(path: path) {
            localized = match
        } else {
            localized = bundle
        }
        let locale: Locale
        if let code {
            let region = Locale.current.region?.identifier
            locale = Locale(identifier: region.map { "\(code)_\($0)" } ?? code)
        } else {
            locale = .current
        }
        let resolved = Cache(stored: stored, source: bundle, bundle: localized, locale: locale)
        cache.value = resolved
        return resolved
    }
}
