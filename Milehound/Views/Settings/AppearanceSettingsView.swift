import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                AppearancePreviewCard()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } footer: {
                Text(L10n.settingsAppearanceSubtitle)
            }

            Section {
                ThemeModeHeroRow()
                    .glassRow(position: .first)
                ThemeMatchSystemToggle()
                    .glassRow(position: .last)
            }

            Section {
                ShellPalettePicker(selection: $settings.shellPalette)
                    .glassRow(position: .only)
            } footer: {
                Text(L10n.settingsShellPaletteHint)
            }

            Section {
                GlassTextSizePicker(selection: $settings.textSize)
                    .glassRow(position: .only)
            }
        }
        .navigationTitle(L10n.settingsAppearanceSection)
        .navigationBarTitleDisplayMode(.inline)
        .sideColumnDetailBack()
        .glassListChrome()
    }
}

/// Static trip row so a theme, palette, or text-size change is visible on this page. No SwiftData.
private struct AppearancePreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.settingsAppearancePreviewTitle)
                .font(.body.weight(.semibold))
                .glassPrimaryInk()
            Text(L10n.settingsAppearancePreviewDetail)
                .font(.subheadline)
                .glassSecondaryInk()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.appearance.preview")
    }
}

struct ShellPalettePicker: View {
    @Binding var selection: ShellPalette
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ShellPalette.allCases) { palette in
                Button {
                    selection = palette
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: palette.gradientColors(for: colorScheme),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        if selection == palette {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2.5)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityLabel(L10n.shellPaletteName(palette))
                .accessibilityAddTraits(selection == palette ? .isSelected : [])
                .accessibilityIdentifier("settings.shellPalette.\(palette.rawValue)")
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("settings.shellPalette")
        .accessibilityElement(children: .contain)
    }
}
