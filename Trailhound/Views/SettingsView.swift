import AppIntents
import MessageUI
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case recording
    case places
    case categories
    case smartCategory
    case appearance
    case language
    case fuel
    case privacy
    case permissions
    case backup
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: L10n.settingsRecordingSection
        case .places: L10n.settingsFavoritePlaces
        case .categories: L10n.categorySection
        case .smartCategory: L10n.settingsSmartCategorySection
        case .appearance: L10n.settingsAppearanceSection
        case .language: L10n.settingsLanguageSection
        case .fuel: L10n.settingsFuelSection
        case .privacy: L10n.settingsPrivacySection
        case .permissions: L10n.settingsPermissionsSection
        case .backup: L10n.settingsBackupSection
        case .about: L10n.settingsAboutSection
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocationService.self) private var locationService
    @Environment(TripRecordingService.self) private var tripRecordingService
    @Environment(GeocodingRetryService.self) private var geocodingRetryService
    @Environment(AppLockService.self) private var appLockService
    @Query private var places: [SavedPlace]
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \VehicleProfile.name) private var vehicles: [VehicleProfile]
    @Bindable private var settings = AppSettings.shared

    @State private var exportURL: URL?
    @State private var showShortcutsAutomationGuide = false
    @State private var showExportSheet = false
    @State private var isExporting = false
    @State private var showAppLockUnavailableAlert = false
    @State private var showAddPlacePicker = false
    @State private var showReportProblem = false
    @State private var tipJarSourceHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMailComposer = false
    @State private var showReportShareSheet = false
    @State private var showReportShareFailed = false
    @State private var reportFileURL: URL?
    @FocusState private var focusedField: SettingsFocusedField?

    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.trailhoundLayout) private var layout
    @State private var settingsPane: SettingsPane = .recording
    @State private var settingsSectionTracker = StickySectionTracker<SettingsPane>(
        order: SettingsPane.allCases,
        initial: .recording
    )
    @State private var settingsScrollRequest = 0

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// One price row per fuel type on the saved vehicles. Empty garage keeps petrol, the new-car default.
    private var pricedFuelTypes: [VehicleFuelType] {
        FuelPriceRows.types(in: vehicles.map(\.fuelType))
    }

    private func unitPriceBinding(for fuelType: VehicleFuelType) -> Binding<Double> {
        Binding(
            get: { settings.unitPrice(for: fuelType) },
            set: { settings.setUnitPrice($0, for: fuelType) }
        )
    }

    var body: some View {
        switch layout.settingsChrome {
        case .form:
            settingsForm
        case .split:
            TrailhoundPaneSplit(
                leadingFraction: TrailhoundLayoutResolver.settingsLeadingFraction(
                    isPhoneBook: layout.isPhoneBook,
                    layoutClass: layout.layoutClass,
                    isLandscape: layout.isLandscape,
                    hingeFullyOpen: TrailhoundHingeMonitor.shared.isFullyOpen
                )
            ) {
                settingsIndex
            } focus: {
                settingsForm
            }
        }
    }

    private var settingsIndex: some View {
        let panes = SettingsPane.allCases
        return List {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                Button {
                    selectSettingsPane(pane)
                } label: {
                    HStack {
                        Text(pane.title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .glassPrimaryInk()
                        Spacer()
                        if settingsPane == pane {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .glassAccentForeground()
                        }
                    }
                }
                .buttonStyle(.glassPlainHit)
                .glassCompactRow(position: GlassRowPosition.index(index, in: panes.count))
            }
        }
        .listStyle(.insetGrouped)
        .glassListChrome(showsAtmosphere: false)
        .glassCompactIndexList()
    }

    private func settingsSectionAnchor(_ pane: SettingsPane) -> some View {
        EmptyView()
            .id(pane)
            .stickySectionMarker(pane, tracker: $settingsSectionTracker)
            .accessibilityHidden(true)
    }

    private func selectSettingsPane(_ pane: SettingsPane) {
        settingsSectionTracker.beginTapScroll(to: pane)
        settingsPane = pane
        settingsScrollRequest += 1
        if reduceMotion {
            settingsSectionTracker.endTapScroll()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            settingsSectionTracker.endTapScroll()
        }
    }

    private var settingsForm: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                LocationPermissionBanner()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section(L10n.settingsRecordingSection) {
                settingsSectionAnchor(.recording)
                Toggle(L10n.settingsRecordingSounds, isOn: $settings.recordingSoundsEnabled)
                    .glassToggleStyle()
                    .accessibilityIdentifier("settings.recordingSounds")
                    .glassRow(position: .first)
                Text(L10n.settingsSiriShortcutsHint)
                    .font(.footnote)
                    .glassSecondaryInk()
                    .glassRow(position: .middle)
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .accessibilityLabel(L10n.settingsSiriShortcutsLink)
                    .glassRow(position: .middle)
                Button {
                    showShortcutsAutomationGuide = true
                } label: {
                    Label(L10n.settingsShortcutsAutomationGuide, systemImage: "bolt.horizontal.circle")
                }
                .glassRow(position: .last)
            }

            Section {
                settingsSectionAnchor(.places)
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

            CategoryManagementView(
                focusedField: $focusedField,
                settingsSectionTracker: $settingsSectionTracker
            )

            Section {
                settingsSectionAnchor(.smartCategory)
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

            Section {
                ThemeModeHeroRow()
                    .glassRow(position: .first)
                settingsSectionAnchor(.appearance)
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    GlassFeaturedRowLabel(
                        systemImage: "paintpalette.fill",
                        title: L10n.settingsAppearanceSection,
                        subtitle: appearanceSummary
                    )
                }
                .glassHidesNavigationLinkIndicator()
                .accessibilityIdentifier("settings.appearance")
                .glassRow(position: .middle)
                settingsSectionAnchor(.language)
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    GlassFeaturedRowLabel(
                        systemImage: "globe",
                        title: L10n.settingsLanguageSection,
                        subtitle: languageSummary
                    )
                }
                .glassHidesNavigationLinkIndicator()
                .accessibilityIdentifier("settings.language")
                .glassRow(position: .last)
            } header: {
                Text(L10n.settingsPersonalizationSection)
            }

            Section(L10n.settingsFuelSection) {
                settingsSectionAnchor(.fuel)
                let fuelTypes = pricedFuelTypes
                ForEach(Array(fuelTypes.enumerated()), id: \.element) { index, type in
                    LabeledContent(type.displayName) {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            TextField(
                                settings.fuelCurrency.symbol,
                                value: unitPriceBinding(for: type),
                                format: .number
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .focused($focusedField, equals: .fuelPrice(type))
                            .glassInputField()
                            .frame(width: 96)
                            if index == 0 {
                                Picker(selection: $settings.fuelCurrency) {
                                    ForEach(FuelCurrency.allCases) { currency in
                                        Text(currency.symbol).tag(currency)
                                    }
                                } label: {
                                    Text(L10n.settingsFuelCurrency)
                                }
                                .glassMenuPicker()
                                .accessibilityLabel(L10n.settingsFuelCurrency)
                            }
                        }
                    }
                    .glassRow(position: index == 0 ? .first : .middle)
                }
                Text(L10n.settingsFuelHint)
                    .font(.footnote)
                    .glassSecondaryInk()
                    .glassRow(position: .last)
            }

            Section(L10n.settingsPrivacySection) {
                settingsSectionAnchor(.privacy)
                Toggle(L10n.settingsAppLock, isOn: appLockEnabledBinding)
                    .glassToggleStyle()
                    .glassRow(position: .first)
                Toggle(L10n.settingsConfirmExternalStart, isOn: $settings.confirmExternalRecordingStart)
                    .glassToggleStyle()
                    .glassRow(position: .middle)
                LabeledContent(L10n.settingsPrivacyRadius) {
                    TextField(L10n.settingsPrivacyRadiusUnit, value: $settings.privacyRadiusMeters, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .privacyRadius)
                        .glassInputField()
                }
                .glassRow(position: .middle)
                Toggle(L10n.settingsBlurExport, isOn: $settings.blurExportCoordinates)
                    .glassToggleStyle()
                    .glassRow(position: .middle)
                Toggle(L10n.string("settings.widget.route_preview"), isOn: $settings.widgetShowRoutePreview)
                    .glassToggleStyle()
                    .glassRow(position: .middle)
                    .onChange(of: settings.widgetShowRoutePreview) { _, _ in
                        TripStore.syncWidgetWeekDistance(in: modelContext)
                    }
                LabeledContent(L10n.settingsAutoDelete) {
                    Picker(L10n.settingsAutoDelete, selection: $settings.autoDeleteDays) {
                        Text(L10n.settingsAutoDeleteNever).tag(0)
                        Text(L10n.settingsAutoDeleteDays(30)).tag(30)
                        Text(L10n.settingsAutoDeleteDays(90)).tag(90)
                        Text(L10n.settingsAutoDeleteDays(365)).tag(365)
                    }
                    .glassMenuPicker()
                }
                .glassRow(position: .last)
            }

            Section(L10n.settingsPermissionsSection) {
                settingsSectionAnchor(.permissions)
                LabeledContent(L10n.settingsLocationPermission) {
                    LocationPermissionBadge(state: locationService.authorizationState)
                }
                .glassRow(position: .first)

                LabeledContent(L10n.settingsNotificationsPermission) {
                    NotificationPermissionBadge(status: notificationAuthorization)
                }
                .glassRow(position: .middle)

                if !locationService.canRecordInBackground {
                    Text(L10n.settingsBackgroundLocationHint)
                        .font(.footnote)
                        .glassSecondaryInk()
                        .glassRow(position: .middle)
                }

                Button(L10n.settingsRequestLocationPermission) { locationService.requestPermission() }
                    .glassRow(position: .middle)

                if notificationAuthorization == .notDetermined {
                    Button(L10n.settingsRequestNotificationsPermission) {
                        requestNotificationPermission()
                    }
                    .accessibilityIdentifier("settings.permissions.requestNotifications")
                    .glassRow(position: .middle)
                }

                Button(L10n.settingsOpenSystemSettings) {
                    SystemSettingsLink.openLocationPermission()
                }
                .glassRow(position: .last)
            }

            Section(L10n.settingsBackupSection) {
                settingsSectionAnchor(.backup)
                Button(L10n.settingsExportJSON) { export(format: .json) }
                    .disabled(isExporting)
                    .accessibilityIdentifier("settings.export.json")
                    .glassRow(position: .first)
                Button(L10n.settingsExportCSV) { export(format: .csv) }
                    .disabled(isExporting)
                    .glassRow(position: .middle)
                Button(L10n.settingsExportGPX) { export(format: .gpx) }
                    .disabled(isExporting)
                    .glassRow(position: .middle)
                Button(L10n.settingsExportKML) { export(format: .kml) }
                    .disabled(isExporting)
                    .glassRow(position: .last)
            }

            Section(L10n.settingsAboutSection) {
                settingsSectionAnchor(.about)
                LabeledContent(L10n.settingsVersion, value: appVersion)
                    .glassRow(position: .first)
                Button(L10n.settingsPlayLaunchIntro) {
                    LaunchIntroSession.shared.replay()
                }
                .accessibilityIdentifier("settings.playLaunchIntro")
                .glassRow(position: .middle)
                Button(L10n.settingsReportProblem) {
                    showReportProblem = true
                }
                .accessibilityIdentifier("settings.reportProblem")
                .glassRow(position: .middle)
                Button {
                    openTipJar()
                } label: {
                    GlassFeaturedRowLabel(
                        systemImage: "heart.fill",
                        title: L10n.settingsTipJar,
                        subtitle: L10n.settingsTipJarSubtitle
                    )
                    .glassMorphPanelSource(isHidden: tipJarSourceHidden)
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityIdentifier("settings.tipJar")
                .glassRow(position: .middle)
                Link(L10n.settingsPrivacyPolicy, destination: SupportMail.privacyPolicyURL)
                    .accessibilityIdentifier("settings.privacyPolicy")
                    .glassRow(position: .middle)
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    HStack {
                        Text(L10n.settingsAcknowledgements)
                        Spacer(minLength: 8)
                        GlassDisclosureChevron()
                    }
                }
                .glassHidesNavigationLinkIndicator()
                .accessibilityIdentifier("settings.acknowledgements")
                .glassRow(position: .middle)
                Text(L10n.settingsAboutPrivacy)
                    .font(.footnote)
                    .glassSecondaryInk()
                    .glassRow(position: .middle)
                Text(L10n.settingsDevelopedBy(DeveloperInfo.name))
                    .font(.footnote)
                    .glassSecondaryInk()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("settings.developedBy")
                    .glassRow(position: .last)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        .onChange(of: settingsPane) { _, pane in
            if settingsSectionTracker.isTapScrolling {
                proxy.scrollTo(pane, anchor: .top)
            }
        }
        .onChange(of: settingsScrollRequest) { _, _ in
            proxy.scrollTo(settingsPane, anchor: .top)
        }
        .onChange(of: settingsSectionTracker.visibleSection) { _, pane in
            if let pane, !settingsSectionTracker.isTapScrolling {
                settingsPane = pane
            }
        }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showAddPlacePicker) {
            PlacePickerView()
        }
        // The split already paints the shell. A second atmosphere clipped to this
        // pane is a different-colored plate behind the form.
        .glassListChrome(showsAtmosphere: !layout.isPhoneBook)
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
        .onAppear {
            runCleanupIfNeeded()
            refreshNotificationAuthorization()
            Task { await geocodingRetryService.retryPendingTrips(in: modelContext) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshNotificationAuthorization()
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let exportURL {
                ExportActivityShareSheet(items: [exportURL])
            }
        }
        .sheet(isPresented: $showShortcutsAutomationGuide) {
            PairingShortcutsAutomationGuideView()
        }
        .alert(
            L10n.settingsReportProblemTitle,
            isPresented: $showReportProblem
        ) {
            Button(L10n.settingsReportProblemOpenMail) {
                prepareDiagnosticReport()
            }
            Button(L10n.settingsReportProblemClearLog, role: .destructive) {
                DeleteConfirmPresenter.shared.confirm(.generic) {
                    DevLog.shared.clear()
                    ToastPresenter.shared.show(.deleted)
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsReportProblemDisclosure)
        }
        .sheet(isPresented: $showMailComposer, onDismiss: cleanupReportFile) {
            MailComposeView(
                recipients: [SupportMail.to],
                subject: diagnosticMailSubject,
                body: L10n.settingsReportProblemMailBody,
                attachmentURL: reportFileURL,
                onFinish: { _ in
                    showMailComposer = false
                }
            )
        }
        .sheet(isPresented: $showReportShareSheet, onDismiss: cleanupReportFile) {
            if let reportFileURL {
                ExportActivityShareSheet(
                    items: [
                        L10n.settingsReportProblemShareHint(SupportMail.to),
                        reportFileURL
                    ]
                )
            }
        }
        .alert(L10n.appLockUnavailableTitle, isPresented: $showAppLockUnavailableAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.appLockUnavailable)
        }
        .alert(L10n.settingsReportProblemFailedTitle, isPresented: $showReportShareFailed) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.settingsReportProblemFailedMessage)
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(L10n.settingsExportPreparing)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .glassCard(cornerRadius: 16, contentInset: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExporting)
    }

    private var appearanceSummary: String {
        "\(L10n.shellPaletteName(settings.shellPalette)) · \(L10n.string(settings.textSize.titleKey))"
    }

    private var languageSummary: String {
        let language = AppLanguageStore.shared.language
        switch language {
        case .system:
            let name = SharedLanguage.preferredSystemCode() == "tr"
                ? AppLanguage.tr.nativeName
                : AppLanguage.en.nativeName
            return L10n.settingsLanguageSystemSubtitle(name)
        case .en, .tr:
            return language.nativeName
        }
    }

    private var favoritePlacesRowCount: Int {
        (places.isEmpty ? 1 : 0) + places.count + 1
    }

    private func refreshNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                notificationAuthorization = status
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status = settings.authorizationStatus
                Task { @MainActor in
                    notificationAuthorization = status
                }
            }
        }
    }

    private var diagnosticMailSubject: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let os = UIDevice.current.systemVersion
        return "Trailhound \(version) · iOS \(os)"
    }

    private func prepareDiagnosticReport() {
        do {
            UIPasteboard.general.string = SupportMail.to
            let url = try DevLog.shared.makeReportFile()
            reportFileURL = url
            if MFMailComposeViewController.canSendMail() {
                showMailComposer = true
            } else {
                showReportShareSheet = true
            }
        } catch {
            cleanupReportFile()
            showReportShareFailed = true
        }
    }

    private func cleanupReportFile() {
        if let reportFileURL {
            try? FileManager.default.removeItem(at: reportFileURL)
        }
        reportFileURL = nil
    }

    private func favoritePlacePosition(placeIndex: Int) -> GlassRowPosition {
        GlassRowPosition.index(placeIndex + 1, in: favoritePlacesRowCount)
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private enum ExportFormat {
        case json, csv, gpx, kml

        var fileExtension: String {
            switch self {
            case .json: "json"
            case .csv: "csv"
            case .gpx: "gpx"
            case .kml: "kml"
            }
        }

        var exportFileFormat: ExportService.FileFormat {
            switch self {
            case .json: .json
            case .csv: .csv
            case .gpx: .gpx
            case .kml: .kml
            }
        }
    }

    private func export(format: ExportFormat) {
        guard !isExporting else { return }

        isExporting = true
        let completed = trips.filter { $0.endedAt != nil }
        let blurCoordinates = settings.blurExportCoordinates
        let privacyRadius = settings.privacyRadiusMeters
        let savedPlaces = places
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailhound-export.\(format.fileExtension)")

        Task { @MainActor in
            let snapshots = ExportService.snapshots(
                from: completed,
                blurCoordinates: blurCoordinates,
                places: savedPlaces,
                privacyRadius: privacyRadius
            )

            do {
                try await Task.detached(priority: .userInitiated) {
                    try ExportService.write(
                        snapshots: snapshots,
                        format: format.exportFileFormat,
                        to: url
                    )
                }.value
                exportURL = url
                showExportSheet = true
            } catch {
                AppErrorPresenter.shared.present(error.localizedDescription)
            }
            isExporting = false
        }
    }

    private func deletePlace(_ place: SavedPlace) {
        modelContext.delete(place)
        try? modelContext.save()
        ToastPresenter.shared.show(.deleted)
    }

    /// The row dissolves, then the root panel grows; the row sharpens back while the panel shrinks.
    private func openTipJar() {
        guard !tipJarSourceHidden else { return }
        let motion = reduceMotion
        withAnimation(TrailhoundMotion.glassPanelSourceDissolve(reduceMotion: motion)) {
            tipJarSourceHidden = true
        }
        GlassMorphPanelPresenter.shared.present(
            accessibilityID: TipJarView.panelAccessibilityID,
            onWillDismiss: {
                withAnimation(TrailhoundMotion.glassPanelSourceDissolve(reduceMotion: motion)) {
                    tipJarSourceHidden = false
                }
            },
            onDismissed: {
                tipJarSourceHidden = false
            }
        ) {
            TipJarView()
        }
    }

    private func runCleanupIfNeeded() {
        let days = settings.autoDeleteDays
        guard days > 0 else { return }
        _ = try? TripCleanupService.cleanupOldTrips(in: modelContext, olderThanDays: days)
    }

    private var appLockEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.appLockEnabled },
            set: { newValue in
                if newValue, !appLockService.canUseDeviceAuthentication {
                    settings.appLockEnabled = false
                    showAppLockUnavailableAlert = true
                } else {
                    settings.appLockEnabled = newValue
                }
            }
        )
    }
}

struct ExportActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(PreviewData.shared.container)
        .environment(LocationService())
        .environment(PreviewData.shared.recordingService)
        .environment(GeocodingRetryService(geocodingService: GeocodingService()))
        .environment(AppLockService())
}
