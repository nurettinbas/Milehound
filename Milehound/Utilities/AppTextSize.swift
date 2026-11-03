import SwiftUI
import UIKit

/// In-app text size, relative to the iPhone's Dynamic Type setting.
/// `standard` leaves the system size untouched. Accessibility sizes are never forced downward.
enum AppTextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var step: Int {
        switch self {
        case .small: -1
        case .standard: 0
        case .large: 1
        case .extraLarge: 2
        }
    }

    /// "Aa" drawn inside the picker. Fixed points so the tiles themselves do not grow.
    var samplePointSize: CGFloat {
        switch self {
        case .small: 13
        case .standard: 16
        case .large: 19
        case .extraLarge: 22
        }
    }

    var titleKey: String {
        switch self {
        case .small: "settings.text_size.small"
        case .standard: "settings.text_size.default"
        case .large: "settings.text_size.large"
        case .extraLarge: "settings.text_size.extra_large"
        }
    }

    func resolved(system: DynamicTypeSize) -> DynamicTypeSize {
        let all = Array(DynamicTypeSize.allCases)
        guard let index = all.firstIndex(of: system) else { return system }
        let next = min(max(index + step, 0), all.count - 1)
        return all[next]
    }

    /// System size from the current trait collection, then this setting's step.
    /// SwiftUI's environment override does not change the UIKit trait, so this stays the iPhone size.
    static func resolvedFromTraits(_ size: AppTextSize) -> DynamicTypeSize {
        let category = UITraitCollection.current.preferredContentSizeCategory
        let system = DynamicTypeSize(category) ?? .large
        return size.resolved(system: system)
    }
}

private struct AppTextSizeAppliedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appTextSizeApplied: Bool {
        get { self[AppTextSizeAppliedKey.self] }
        set { self[AppTextSizeAppliedKey.self] = newValue }
    }
}

private struct AppTextSizeScopeModifier: ViewModifier {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dynamicTypeSize) private var systemSize
    @Environment(\.appTextSizeApplied) private var alreadyApplied

    func body(content: Content) -> some View {
        if alreadyApplied {
            content
        } else {
            content
                .environment(\.dynamicTypeSize, settings.textSize.resolved(system: systemSize))
                .environment(\.appTextSizeApplied, true)
        }
    }
}

extension View {
    /// Applies the in-app text size once. A second call (a cover inside the root) does not stack the step.
    func appTextSizeScope() -> some View {
        modifier(AppTextSizeScopeModifier())
    }

    /// Share cards stay at the large size so a user's text-size setting cannot reflow the poster.
    func milehoundShareCaptureEnvironment() -> some View {
        environment(\.locale, SharedLanguage.locale)
            .environment(\.dynamicTypeSize, .large)
    }
}
