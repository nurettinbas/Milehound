import SwiftData
import SwiftUI

/// Favorite places, categories, and smart categories. Kept off the Settings root so that list stays short.
struct PlacesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.trailhoundLayout) private var layout
    @Query private var places: [SavedPlace]
    @Bindable private var settings = AppSettings.shared
    @Bindable private var sideColumnChrome = SideColumnChromeState.shared
    @FocusState private var focusedField: SettingsFocusedField?
    @State private var showAddPlacePicker = false

    /// The Duo side column already holds the bell. The bar’s back control lands beside it.
    private var parksBackUnderBell: Bool {
        sideColumnChrome.rootClear
            && sideColumnChrome.uprightDuoCapsuleFrame(buttonCount: 1, layout: layout) != nil
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showAddPlacePicker = true
                } label: {
                    Label(L10n.settingsAddPlace, systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .glassPrimaryInk()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPlainHit)
                .glassRow(position: .first)

                if places.isEmpty {
                    Text(L10n.settingsFavoritePlacesEmpty)
                        .font(.subheadline)
                        .glassSecondaryInk()
                        .glassRow(position: .last)
                }

                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    NavigationLink {
                        PlacePickerView(editingPlace: place)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: place.kind.systemImage)
                                .font(.subheadline)
                                .glassSecondaryInk()
                                .frame(width: 18)
                            Text(place.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(place.kind.displayName)
                                .font(.caption2)
                                .glassSecondaryInk()
                            GlassDisclosureChevron()
                        }
                    }
                    .glassHidesNavigationLinkIndicator()
                    .glassRow(position: favoritePlacePosition(placeIndex: index))
                    .listRowInsets(
                        EdgeInsets(
                            top: 7,
                            leading: GlassTokens.listContentHorizontalInset,
                            bottom: 7,
                            trailing: GlassTokens.listContentHorizontalInset
                        )
                    )
                    .confirmingDeleteSwipe {
                        deletePlace(place)
                    }
                }
            } header: {
                Text(L10n.settingsFavoritePlaces)
            } footer: {
                Text(L10n.settingsFavoritePlacesHint)
            }

            CategoryManagementView(focusedField: $focusedField)

            Section {
                Toggle(L10n.settingsSmartCategoryToggle, isOn: $settings.smartCategorySuggestionsEnabled)
                    .glassToggleStyle()
                    .accessibilityIdentifier("settings.smartCategory")
                    .glassRow(position: settings.smartCategorySuggestionsEnabled ? .first : .only)
                if settings.smartCategorySuggestionsEnabled {
                    LabeledContent(L10n.settingsSmartCategoryWorkStart) {
                        Picker(L10n.settingsSmartCategoryWorkStart, selection: $settings.workHourStart) {
                            ForEach(Array(0..<24), id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .glassMenuPicker()
                    }
                    .accessibilityIdentifier("settings.smartCategory.workStart")
                    .glassRow(position: .middle)
                    LabeledContent(L10n.settingsSmartCategoryWorkEnd) {
                        Picker(L10n.settingsSmartCategoryWorkEnd, selection: $settings.workHourEnd) {
                            ForEach(Array(0..<24), id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .glassMenuPicker()
                    }
                    .accessibilityIdentifier("settings.smartCategory.workEnd")
                    .glassRow(position: .last)
                }
            } header: {
                Text(L10n.settingsSmartCategorySection)
            } footer: {
                Text(L10n.settingsSmartCategoryHint)
            }
        }
        .navigationTitle(L10n.settingsPlacesSection)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(parksBackUnderBell)
        .onAppear { syncSideColumnBack() }
        .onDisappear { sideColumnChrome.releaseSettingsDetailBack() }
        .onChange(of: parksBackUnderBell) { _, _ in syncSideColumnBack() }
        .glassListChrome()
        .dismissKeyboardOnTap(focus: $focusedField)
        .dismissKeyboardOnScroll()
        .fieldKeyboardAccessory(
            title: focusedField?.title ?? "",
            focusID: focusedField.map { AnyHashable($0) },
            onDone: {
                focusedField = nil
                KeyboardDismiss.dismiss()
            }
        )
        .navigationDestination(isPresented: $showAddPlacePicker) {
            PlacePickerView()
        }
    }

    private func syncSideColumnBack() {
        if parksBackUnderBell {
            sideColumnChrome.claimSettingsDetailBack { dismiss() }
        } else {
            sideColumnChrome.releaseSettingsDetailBack()
        }
    }

    private var favoritePlacesRowCount: Int {
        (places.isEmpty ? 1 : 0) + places.count + 1
    }

    private func favoritePlacePosition(placeIndex: Int) -> GlassRowPosition {
        GlassRowPosition.index(placeIndex + 1, in: favoritePlacesRowCount)
    }

    private func deletePlace(_ place: SavedPlace) {
        modelContext.delete(place)
        try? modelContext.save()
        ToastPresenter.shared.show(.deleted)
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
