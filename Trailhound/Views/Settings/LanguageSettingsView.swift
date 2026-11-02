import SwiftData
import SwiftUI

struct LanguageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var store = AppLanguageStore.shared

    var body: some View {
        let rows = AppLanguage.allCases
        Form {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, language in
                    Button {
                        select(language)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: language))
                                    .font(.body.weight(.semibold))
                                    .glassPrimaryInk()
                                if let subtitle = subtitle(for: language) {
                                    Text(subtitle)
                                        .font(.footnote)
                                        .glassSecondaryInk()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            LanguageRadio(isSelected: store.language == language)
                        }
                    }
                    .buttonStyle(.glassPlainHit)
                    .glassRow(position: GlassRowPosition.index(index, in: rows.count))
                    .accessibilityAddTraits(store.language == language ? .isSelected : [])
                    .accessibilityIdentifier("settings.language.\(language.rawValue)")
                }
            }
        }
        .navigationTitle(L10n.settingsLanguageSection)
        .navigationBarTitleDisplayMode(.inline)
        .glassListChrome()
        .accessibilityIdentifier("settings.language.list")
    }

    private func title(for language: AppLanguage) -> String {
        switch language {
        case .system: L10n.settingsLanguageSystem
        case .en, .tr: language.nativeName
        }
    }

    private func subtitle(for language: AppLanguage) -> String? {
        switch language {
        case .system:
            SharedLanguage.preferredSystemCode() == "tr" ? "Türkçe" : "English"
        case .en:
            nil
        case .tr:
            language.englishName
        }
    }

    private func select(_ language: AppLanguage) {
        guard store.language != language else { return }
        let context = modelContext
        AppearanceTransitionCoordinator.shared.perform(reduceMotion: reduceMotion) {
            store.select(language)
            guard !UITestSupport.shouldSkipExternalEffects else { return }
            VehicleCareNotificationScheduler.rescheduleAll(in: context)
            RecapNotificationScheduler.reschedule(in: context)
        }
    }
}

private struct LanguageRadio: View {
    var isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    shellPalette.tintColor(for: colorScheme).opacity(isSelected ? 0 : 0.45),
                    lineWidth: 1.5
                )
            if isSelected {
                Circle()
                    .fill(shellPalette.tintColor(for: colorScheme))
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
        .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: isSelected)
        .accessibilityHidden(true)
    }
}
