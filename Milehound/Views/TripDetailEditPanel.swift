import CoreLocation
import SwiftData
import SwiftUI
import UIKit

enum TripSummaryMetricCardLayout {
    static let titleRowHeight: CGFloat = 16
    static let titleValueSpacing: CGFloat = 4
    static let helpButtonSide: CGFloat = 16
    static let minHeight: CGFloat = 52
}

/// Same glass metric tile as trip detail. Share rasters use `frozen` / no help.
struct TripSummaryMetricTile: View {
    let metric: TripSummaryMetric
    var progress: Double = 1
    var frozen: Bool = true
    var showsHelp: Bool = false

    @Environment(\.milehoundLayout) private var layout

    /// Upright Duo sheet is much wider than a phone. The phone point size reads large there.
    private var duoSheet: Bool {
        layout.layoutClass == .duoOpen && layout.tripDetailStyle == .overlay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TripSummaryMetricCardLayout.titleValueSpacing) {
            HStack(alignment: .center, spacing: 4) {
                Label(metric.title, systemImage: metric.icon)
                    .font(.system(size: duoSheet ? 8 : 10, weight: .medium))
                    .glassSecondaryInk()
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsHelp, metric.showsHelp, let helpTitle = metric.helpTitle, let helpBody = metric.helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: TripSummaryMetricCardLayout.helpButtonSide
                    )
                }
            }
            .frame(height: TripSummaryMetricCardLayout.titleRowHeight)

            Text(metric.formatted(progress: progress))
                .font(.caption.weight(.semibold))
                .glassPrimaryInk()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            minHeight: TripSummaryMetricCardLayout.minHeight,
            alignment: .topLeading
        )
        .glassChrome(cornerRadius: 10, frozen: frozen)
    }
}

private enum JournalPickerValue: Hashable {
    case none
    case journal(UUID)
    case createNew
}

private struct FavoritePlaceSheetItem: Identifiable {
    enum Endpoint {
        case start
        case end
    }

    enum Mode {
        case create(PlaceDraft)
        case edit(UUID)
    }

    let mode: Mode
    let endpoint: Endpoint

    var id: String {
        switch mode {
        case .create(let draft):
            return "create-\(endpoint)-\(draft.id.uuidString)"
        case .edit(let placeID):
            return "edit-\(endpoint)-\(placeID.uuidString)"
        }
    }
}

/// Bottom edit sheet for trip detail. Owns keyboard / typing state so MapKit
/// in the parent is not invalidated on every keystroke or keyboard frame.
struct TripDetailEditPanel: View {
    @Bindable var trip: Trip
    let viewModel: TripDetailViewModel
    let glassFrozen: Bool
    let panelRisen: Bool
    let restHeight: CGFloat
    let mapPeek: CGFloat
    /// Phone overlay keeps the sheet handle. A full page hides it so the pane does not look closable.
    var showsGrabber: Bool = true
    let reduceMotion: Bool
    let statCountProgress: [String: Double]
    let speedChartRevealProgress: Double
    @Binding var recordedPointCount: Int
    /// Parent bumps this to clear focus (map tap / fullscreen).
    @Binding var keyboardDismissSignal: Int
    var onDisplayRefresh: () -> Void
    var onRouteInvalidated: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.milehoundLayout) private var layout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var places: [SavedPlace]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query(sort: \TravelJournal.endedOn, order: .reverse) private var journals: [TravelJournal]
    @Bindable private var settings = AppSettings.shared

    @State private var noteText: String = ""
    @State private var selectedCategoryID: String = BuiltInCategory.personalID.uuidString
    @State private var selectedVehicleID: UUID?
    @State private var editedFuelConsumption: Double = 7.5
    @State private var fuelConsumptionAtOpen: Double = 7.5
    @State private var editedFuelUnitPrice: Double = 65
    @State private var startAddressText: String = ""
    @State private var endAddressText: String = ""
    @State private var startPlaceNameText: String = ""
    @State private var endPlaceNameText: String = ""
    @State private var originalNoteText: String = ""
    @State private var editedStartedAt: Date = Date()
    @State private var editedEndedAt: Date = Date()
    @State private var trimHeadCount: Int = 0
    @State private var trimTailCount: Int = 0
    @State private var favoritePlaceSheet: FavoritePlaceSheetItem?
    @State private var journalEditor: TravelJournalEditorDraft?
    /// Keeps the edit sheet from jumping the first time a travel menu choice saves.
    @State private var menuScrollHold = TripDetailMenuScrollHold()
    @State private var keyboardOverlap: CGFloat = 0
    @State private var keyboardAnimationDuration: TimeInterval = 0.25
    @FocusState private var focusedField: TripDetailFocusedField?

    private var isEditing: Bool {
        focusedField != nil || keyboardOverlap > 0.5
    }

    private var containerHeight: CGFloat {
        // Parent lays out by restHeight; recover full height for editing math.
        guard TripDetailKeyboardLayout.restHeightFraction > 0 else { return restHeight }
        return restHeight / TripDetailKeyboardLayout.restHeightFraction
    }

    private var panelHeight: CGFloat {
        TripDetailKeyboardLayout.panelHeight(
            containerHeight: containerHeight,
            isEditing: isEditing,
            mapPeek: mapPeek
        )
    }

    private var scrollBottomInset: CGFloat {
        let standard = TripDetailKeyboardLayout.scrollBottomInset(keyboardOverlap: keyboardOverlap)
        guard !showsGrabber, keyboardOverlap <= 0 else { return standard }
        return max(Self.keyWindowSafeBottom + 12, GlassTokens.paneVerticalRhythm)
    }

    private static var keyWindowSafeBottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.bottom ?? 0
    }

    private var sortedStops: [TripStop] {
        trip.stops.sorted { $0.startedAt < $1.startedAt }
    }

    private var sortedDetailVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: sortedDetailVehicles)
    }

    private var selectedDetailVehicle: VehicleProfile? {
        selectedVehicleID.flatMap { id in
            sortedDetailVehicles.first(where: { $0.id == id })
        }
    }

    private var selectedCategoryDisplayName: String {
        categories.first(where: { $0.id.uuidString == selectedCategoryID })?.name ?? ""
    }

    private var selectedVehicleDisplayName: String {
        selectedDetailVehicle?.name ?? L10n.string("trip.edit.vehicle_none")
    }

    /// Light glass wells use the white type hierarchy.
    private var fieldInk: Color {
        GlassText.primary(for: colorScheme)
    }

    private var fieldSecondaryInk: Color {
        GlassText.secondary(for: colorScheme)
    }

    private var previewFuelCost: Double {
        FuelCostCalculator.estimateCost(
            distanceMeters: trip.distanceMeters,
            vehicle: selectedDetailVehicle,
            consumptionPer100: editedFuelConsumption,
            unitPrice: editedFuelUnitPrice
        )
    }

    /// Cheap keyboard preview: scale stored dynamic by ΔC₀ × Δprice without walking points.
    private var previewDynamicFuelCost: Double? {
        guard let stored = trip.dynamicFuelCost, stored > 0 else { return nil }
        let baseC0 = trip.fuelConsumptionPer100 ?? editedFuelConsumption
        let basePrice = trip.fuelUnitPrice ?? editedFuelUnitPrice
        guard baseC0 > 0, basePrice > 0, editedFuelConsumption > 0, editedFuelUnitPrice > 0 else {
            return stored
        }
        return stored * (editedFuelConsumption / baseC0) * (editedFuelUnitPrice / basePrice)
    }

    private var consumptionFieldTitle: String {
        selectedDetailVehicle?.consumptionLabel ?? L10n.fuelUnitLPer100km
    }

    private var fuelPriceFieldTitle: String {
        fuelUnitPriceLabel(for: selectedDetailVehicle)
    }

    private var focusedFieldTitle: String {
        guard let focusedField else { return "" }
        return focusedField.title(
            consumptionLabel: consumptionFieldTitle,
            fuelPriceLabel: fuelPriceFieldTitle
        )
    }

    private var maxTrimHead: Int {
        max(0, recordedPointCount - trimTailCount - 2)
    }

    private var maxTrimTail: Int {
        max(0, recordedPointCount - trimHeadCount - 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsGrabber {
                panelGrabber
            }

            if panelRisen {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        detailPanelContent
                            .background(alignment: .top) {
                                TripDetailMenuScrollHoldAnchor(hold: menuScrollHold)
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .modifier(FullPageVerticalBleed(enabled: !showsGrabber))
                    .contentMargins(.bottom, 0, for: .scrollIndicators)
                    .dismissKeyboardOnScroll()
                    .onChange(of: focusedField) { _, field in
                        scrollToFocusedField(field, proxy: proxy)
                    }
                    .onChange(of: keyboardOverlap) { _, _ in
                        scrollToFocusedField(focusedField, proxy: proxy)
                    }
                    .onChange(of: panelHeight) { _, _ in
                        scrollToFocusedField(focusedField, proxy: proxy)
                    }
                }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        .onKeyboardOverlap($keyboardOverlap, animationDuration: $keyboardAnimationDuration)
        .animation(panelHeightAnimation, value: panelHeight)
        .animation(panelHeightAnimation, value: scrollBottomInset)
        .dismissKeyboardOnTap(focus: $focusedField)
        .fieldKeyboardAccessory(
            title: focusedFieldTitle,
            focusID: focusedField.map { AnyHashable($0) },
            onDone: { dismissKeyboard() }
        )
        .sheet(item: $favoritePlaceSheet) { item in
            NavigationStack {
                favoritePlacePicker(for: item)
            }
        }
        .sheet(item: $journalEditor) { draft in
            TravelJournalEditorSheet(draft: draft)
        }
        .onAppear {
            loadEditStateFromTrip()
        }
        .onChange(of: keyboardDismissSignal) { _, _ in
            dismissKeyboard()
        }
        .onChange(of: trip.id) { _, _ in
            loadEditStateFromTrip()
        }
        .environment(\.dynamicTypeSize, duoSheetTypeSize)
    }

    private var duoSheet: Bool {
        layout.layoutClass == .duoOpen && layout.tripDetailStyle == .overlay
    }

    /// Section labels such as Trip times. Subheadline is too heavy on the wide Duo card.
    private var sectionTitleFont: Font {
        duoSheet ? .caption.weight(.semibold) : .subheadline.weight(.semibold)
    }

    /// Two steps under the reader's size, only on the upright Duo sheet.
    /// The phone point size reads large on that wide card. Accessibility sizes stay put.
    private var duoSheetTypeSize: DynamicTypeSize {
        guard layout.layoutClass == .duoOpen, layout.tripDetailStyle == .overlay else {
            return dynamicTypeSize
        }
        guard !dynamicTypeSize.isAccessibilitySize else { return dynamicTypeSize }
        let sizes = Array(DynamicTypeSize.allCases)
        guard let index = sizes.firstIndex(of: dynamicTypeSize) else { return dynamicTypeSize }
        return sizes[max(0, index - 2)]
    }

    private var panelHeightAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeOut(duration: max(0.15, keyboardAnimationDuration))
    }

    private func scrollToFocusedField(
        _ field: TripDetailFocusedField?,
        proxy: ScrollViewProxy
    ) {
        guard let field else { return }
        let action = {
            proxy.scrollTo(field, anchor: UnitPoint(x: 0.5, y: 0.24))
        }
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeOut(duration: 0.22), action)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        KeyboardDismiss.dismiss()
    }

    private func loadEditStateFromTrip() {
        noteText = trip.note ?? ""
        originalNoteText = noteText
        selectedCategoryID = trip.categoryID
        selectedVehicleID = trip.vehicleID
        loadFuelEditDefaults(for: selectedVehicleID, preferTripSnapshot: true)
        startAddressText = trip.startAddress ?? ""
        endAddressText = trip.endAddress ?? ""
        startPlaceNameText = trip.startPlaceName ?? ""
        endPlaceNameText = trip.endPlaceName ?? ""
        editedStartedAt = trip.startedAt
        editedEndedAt = trip.endedAt ?? Date()
        trimHeadCount = 0
        trimTailCount = 0
    }

    /// The phone sheet already reaches the screen bottom, under the tab bar.
    /// A second safe-area inset leaves a gap, so the scroll stops short of that edge.
    /// Full-page panes also skip the status band.
    private struct FullPageVerticalBleed: ViewModifier {
        var enabled: Bool

        func body(content: Content) -> some View {
            if enabled {
                content.ignoresSafeArea(edges: .vertical)
            } else {
                content.ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var panelGrabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var detailPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            tripHeader

            statsStrip

            if !viewModel.speedSamples.isEmpty {
                speedChartCard
            }

            if !sortedStops.isEmpty {
                detailSelectionSection(title: L10n.tripStopsSection) {
                    VStack(spacing: 10) {
                        ForEach(sortedStops, id: \.persistentModelID) { stop in
                            TripStopEditRow(stop: stop)
                        }
                    }
                }
            }

            if trip.endedAt != nil {
                detailSplitSection(title: L10n.tripEditTimesSection) {
                    tripTimePicker(
                        title: L10n.tripStartedAt,
                        selection: $editedStartedAt
                    )
                } right: {
                    tripTimePicker(
                        title: L10n.tripEndedAt,
                        selection: $editedEndedAt
                    )
                }
            } else {
                detailSection(title: L10n.tripEditTimesSection) {
                    tripTimePicker(
                        title: L10n.tripStartedAt,
                        selection: $editedStartedAt
                    )
                }
            }

            detailSplitSection(title: L10n.tripTrimPointsSection) {
                trimStepperCell(
                    title: L10n.tripTrimHead,
                    value: $trimHeadCount,
                    range: 0...maxTrimHead
                )
            } right: {
                trimStepperCell(
                    title: L10n.tripTrimTail,
                    value: $trimTailCount,
                    range: 0...maxTrimTail
                )
            }

            detailSection(title: L10n.tripLocationOverrides) {
                compactTextField(
                    L10n.tripStartPlaceName,
                    text: $startPlaceNameText,
                    field: .startPlace
                )
                favoritePlaceAction(
                    endpoint: .start,
                    coordinate: trip.startCoordinate,
                    accessibilityLabel: L10n.tripAddStartToFavorites
                )
                compactTextField(
                    L10n.tripEndPlaceName,
                    text: $endPlaceNameText,
                    field: .endPlace
                )
                favoritePlaceAction(
                    endpoint: .end,
                    coordinate: trip.endCoordinate,
                    accessibilityLabel: L10n.tripAddEndToFavorites
                )
                compactTextField(
                    L10n.tripStartAddress,
                    text: $startAddressText,
                    field: .startAddress
                )
                compactTextField(
                    L10n.tripEndAddress,
                    text: $endAddressText,
                    field: .endAddress
                )
            }

            if vehicles.isEmpty {
                detailSection(title: L10n.tripEditCategory) {
                    detailMenuPicker(
                        title: L10n.tripEditCategory,
                        value: selectedCategoryDisplayName,
                        selection: $selectedCategoryID
                    ) {
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.systemImage)
                                .tag(category.id.uuidString)
                        }
                    }
                    .onChange(of: selectedCategoryID) { _, _ in
                        dismissKeyboard()
                    }
                }
            } else {
                detailSplitSection(title: L10n.tripEditCategory) {
                    detailMenuPicker(
                        title: L10n.tripEditCategory,
                        value: selectedCategoryDisplayName,
                        selection: $selectedCategoryID
                    ) {
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.systemImage)
                                .tag(category.id.uuidString)
                        }
                    }
                    .onChange(of: selectedCategoryID) { _, _ in
                        dismissKeyboard()
                    }
                } right: {
                    detailMenuPicker(
                        title: L10n.string("trip.edit.vehicle"),
                        value: selectedVehicleDisplayName,
                        selection: $selectedVehicleID,
                        leading: {
                            if let selected = selectedDetailVehicle {
                                VehicleAvatarView(
                                    systemImage: selected.systemImage,
                                    photoFileName: selected.photoFileName,
                                    size: 16,
                                    cornerRadius: 4,
                                    isElectricAccent: selected.fuelType == .electric,
                                    symbolColor: selected.fuelType == .electric
                                        ? Color.yellow
                                        : shellPalette.tintColor(for: colorScheme),
                                    showsSymbolPlate: false,
                                    symbolFitsFrame: true
                                )
                                .clipped()
                            } else {
                                Image(systemName: "car")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(fieldSecondaryInk)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    ) {
                        Text(L10n.string("trip.edit.vehicle_none"))
                            .tag(UUID?.none)
                        ForEach(sortedDetailVehicles) { vehicle in
                            Text(vehicle.name)
                                .tag(Optional(vehicle.id))
                        }
                    }
                    .onChange(of: selectedVehicleID) { _, newID in
                        dismissKeyboard()
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            loadFuelEditDefaults(for: newID, preferTripSnapshot: false)
                        }
                    }
                    .task(id: vehiclePhotoPrefetchID) {
                        await VehiclePhotoStore.shared.prefetch(vehicles: sortedDetailVehicles)
                    }
                }
            }

            detailSplitSection(
                title: L10n.tripEditFuelSection,
                helpTitle: L10n.tripEditFuelHelpTitle,
                helpBody: L10n.tripEditFuelHelpBody
            ) {
                fuelNumberField(
                    title: consumptionFieldTitle,
                    value: $editedFuelConsumption,
                    field: .fuelConsumption
                )
            } right: {
                fuelNumberField(
                    title: fuelPriceFieldTitle,
                    value: $editedFuelUnitPrice,
                    field: .fuelPrice
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tripEditFuelPreview(FuelCostCalculator.formatCost(
                    previewFuelCost,
                    currencyCode: settings.fuelCurrency.rawValue
                )))
                if let previewDynamic = previewDynamicFuelCost {
                    Text("\(L10n.dynamicFuel): \(FuelCostCalculator.formatCost(previewDynamic, currencyCode: settings.fuelCurrency.rawValue))")
                        .font(.footnote)
                        .glassSecondaryInk()
                }
            }
            .font(.footnote)
            .glassSecondaryInk()
            .padding(.top, -6)

            detailSection(title: L10n.tripEditNote) {
                TextField(L10n.tripEditNotePlaceholder, text: $noteText, axis: .vertical)
                    .foregroundStyle(fieldInk)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .note)
                    .submitLabel(.done)
                    .glassInputField()
                    .onSubmit { dismissKeyboard() }
                    .id(TripDetailFocusedField.note)
            }

            if trip.endedAt != nil {
                journalMembershipRow
            }

            Button(L10n.tripEditSave) {
                saveEdits()
                dismissKeyboard()
            }
            .accessibilityIdentifier("tripDetail.save")
            .milehoundProminentButton()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GlassTokens.listContentHorizontalInset)
        .padding(.top, showsGrabber ? 0 : GlassTokens.paneVerticalRhythm)
        .padding(.bottom, scrollBottomInset)
    }

    private var tripHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.routeSummary)
                .font(duoSheet ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(2)

            Text(viewModel.dateText)
                .font(.caption)
                .glassSecondaryInk()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var journalMembershipRow: some View {
        detailSection(
            title: L10n.journalAdd,
            helpTitle: L10n.journalAddHelpTitle,
            helpBody: L10n.journalAddHelpBody
        ) {
            detailMenuPicker(
                title: L10n.journalAdd,
                value: selectedJournalTitle,
                selection: journalPickerValue,
                leading: {
                    Image(systemName: trip.journalID == nil ? "map" : "map.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fieldSecondaryInk)
                        .frame(width: 22, height: 22)
                }
            ) {
                Section {
                    Label(L10n.journalNew, systemImage: "plus")
                        .tag(JournalPickerValue.createNew)
                }
                Section {
                    Text(L10n.journalNone)
                        .tag(JournalPickerValue.none)
                    ForEach(journals, id: \.id) { journal in
                        Text(journal.title)
                            .tag(JournalPickerValue.journal(journal.id))
                    }
                }
            }
            .accessibilityLabel(L10n.journalAdd)
            .accessibilityValue(selectedJournalTitle)
        }
    }

    private var selectedJournalTitle: String {
        guard let journalID = trip.journalID,
              let journal = journals.first(where: { $0.id == journalID }) else {
            return L10n.journalNone
        }
        return journal.title
    }

    private var journalPickerValue: Binding<JournalPickerValue> {
        Binding(
            get: {
                guard let journalID = trip.journalID,
                      journals.contains(where: { $0.id == journalID }) else {
                    return .none
                }
                return .journal(journalID)
            },
            set: { newValue in
                // Resigning first responder here runs while the menu is closing and
                // pulls the sheet down with the keyboard. Assign without that.
                // The first choice after the sheet appears also yanks this scroll
                // view while the menu dismisses and the save rebuilds the form.
                switch newValue {
                case .none:
                    menuScrollHold.pin()
                    assignJournal(nil)
                case .journal(let id):
                    menuScrollHold.pin()
                    assignJournal(id)
                case .createNew:
                    openNewTravelEditor()
                }
            }
        )
    }

    private func openNewTravelEditor() {
        dismissKeyboard()
        MilehoundHaptics.selection()
        let tripID = trip.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            journalEditor = .create(preselectedTripIDs: [tripID])
        }
    }

    private func assignJournal(_ journalID: UUID?) {
        let journal = journalID.flatMap { id in journals.first { $0.id == id } }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            TravelJournalTotals.assign(trip: trip, to: journal, in: modelContext)
            try? modelContext.save()
        }
        ToastPresenter.shared.show(.tripSaved)
    }

    @ViewBuilder
    private var statsStrip: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        VStack(alignment: .leading, spacing: 8) {
            statsMetricGrid(metrics: viewModel.summaryMetrics)
                .id(fuelCurrencyCode)
            if !viewModel.fuelFactorKinds.isEmpty {
                fuelFactorRow
            }
        }
    }

    private var fuelFactorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(L10n.fuelFactorsHelpTitle)
                    .font(.caption2.weight(.medium))
                    .glassSecondaryInk()
                HelpPopoverButton(
                    accessibilityLabel: L10n.fuelFactorsHelpTitle,
                    message: L10n.fuelFactorsHelpBody,
                    side: TripSummaryMetricCardLayout.helpButtonSide
                )
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(viewModel.fuelFactorKinds, id: \.rawValue) { kind in
                    Text(TripSummaryMetric.factorTitle(kind))
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .glassPrimaryInk()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .glassChrome(cornerRadius: 10, frozen: glassFrozen)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsMetricGrid(metrics: [TripSummaryMetric]) -> some View {
        // Eager rows. A lazy grid inside this sheet collapses the first time the
        // travel menu saves (the tiles are off screen), and the scroll view jumps.
        let rowIDs = stride(from: 0, to: metrics.count, by: 3).map { metrics[$0].id }
        return VStack(spacing: 8) {
            ForEach(rowIDs, id: \.self) { rowID in
                let start = metrics.firstIndex(where: { $0.id == rowID }) ?? 0
                let row = Array(metrics[start..<min(start + 3, metrics.count)])
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { metric in
                        statsMetricCard(for: metric)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    ForEach(0..<max(0, 3 - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func statsMetricCard(for metric: TripSummaryMetric) -> some View {
        let progress = statCountProgress[metric.id] ?? (panelRisen ? 1 : 0)
        return TripSummaryMetricTile(
            metric: metric,
            progress: progress,
            frozen: glassFrozen,
            showsHelp: true
        )
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : MilehoundMotion.snappy, value: progress)
        .opacity(progress > 0.01 || reduceMotion ? 1 : 0.35)
        .scaleEffect(progress > 0.01 || reduceMotion ? 1 : 0.94)
    }

    private var speedChartCard: some View {
        let progress = speedChartRevealProgress

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tripSpeedChart)
                .font(sectionTitleFont)

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(L10n.formatSpeedKmh(viewModel.speedChartMaxKmh))
                        .font(.caption2)
                    Spacer(minLength: 0)
                    Text(L10n.formatSpeedKmh(0))
                        .font(.caption2)
                }
                .glassSecondaryInk()
                .frame(width: 34, height: 120)

                SpeedChartRouteCanvas(
                    samples: viewModel.speedSamples,
                    maxKmh: viewModel.speedChartMaxKmh,
                    progress: progress,
                    tripStartedAt: trip.startedAt,
                    tripEndedAt: trip.endedAt ?? trip.startedAt,
                    sampleMedianIntervalSeconds: viewModel.speedSampleMedianIntervalSeconds
                )
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
        }
        .padding(12)
        .glassChrome(cornerRadius: 12, frozen: glassFrozen)
        .opacity(progress > 0.01 || reduceMotion ? 1 : 0.35)
        .scaleEffect(progress > 0.01 || reduceMotion ? 1 : 0.98)
    }

    private func tripTimePicker(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(fieldSecondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            DatePicker(title, selection: selection, displayedComponents: .date)
                .glassDatePicker()
                .scaleEffect(0.75, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .glassDatePicker()
                .scaleEffect(0.75, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func trimStepperCell(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(fieldSecondaryInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                detailCompactStepButton(systemImage: "minus") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Text("\(value.wrappedValue)")
                    .font(duoSheet ? .callout.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(fieldInk)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                detailCompactStepButton(systemImage: "plus") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                }
                .disabled(value.wrappedValue >= range.upperBound)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailCompactStepButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(fieldInk)
                .frame(width: 26, height: 26)
                .glassField(cornerRadius: 6)
        }
        .buttonStyle(.glassPlainHit)
    }

    private func detailMenuPicker<Selection: Hashable, Content: View>(
        title: String,
        value: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailMenuPicker(
            title: title,
            value: value,
            selection: selection,
            leading: { EmptyView() },
            content: content
        )
    }

    private func detailMenuPicker<Selection: Hashable, Leading: View, Content: View>(
        title: String,
        value: String,
        selection: Binding<Selection>,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(fieldSecondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 6) {
                leading()
                Menu {
                    Picker(title, selection: selection, content: content)
                        .pickerStyle(.inline)
                        .labelsHidden()
                } label: {
                    HStack(spacing: 4) {
                        Text(value)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(fieldInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .truncationMode(.tail)
                            .allowsTightening(true)
                            .animation(nil, value: value)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(fieldSecondaryInk)
                    }
                    .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glassPlainHit)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
    }

    private func detailMiniCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .modifier(TripDetailEditWell(padding: 8))
    }

    private func detailSplitSection<Left: View, Right: View>(
        title: String,
        helpTitle: String? = nil,
        helpBody: String? = nil,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        detailSelectionSection(title: title, helpTitle: helpTitle, helpBody: helpBody) {
            HStack(alignment: .top, spacing: 10) {
                detailMiniCard(content: left)
                    .frame(minWidth: 0, maxWidth: .infinity)
                detailMiniCard(content: right)
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private func detailSelectionSection<Content: View>(
        title: String,
        helpTitle: String? = nil,
        helpBody: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(sectionTitleFont)
                if let helpTitle, let helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: 22
                    )
                }
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12, frozen: glassFrozen)
    }

    private func detailSection<Content: View>(
        title: String,
        helpTitle: String? = nil,
        helpBody: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailSelectionSection(
            title: title,
            helpTitle: helpTitle,
            helpBody: helpBody
        ) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func compactTextField(
        _ title: String,
        text: Binding<String>,
        field: TripDetailFocusedField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(fieldSecondaryInk)
            TextField(title, text: text)
                .foregroundStyle(fieldInk)
                .focused($focusedField, equals: field)
                .glassInputField()
        }
        .id(field)
    }

    private func fuelNumberField(
        title: String,
        value: Binding<Double>,
        field: TripDetailFocusedField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(fieldSecondaryInk)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .foregroundStyle(fieldInk)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .glassInputField()
        }
        .id(field)
    }

    @ViewBuilder
    private func favoritePlaceAction(
        endpoint: FavoritePlaceSheetItem.Endpoint,
        coordinate: CLLocationCoordinate2D?,
        accessibilityLabel: String
    ) -> some View {
        if let coordinate {
            let existing = places.first(where: { $0.contains(coordinate) })
            Button {
                dismissKeyboard()
                if let existing {
                    favoritePlaceSheet = FavoritePlaceSheetItem(
                        mode: .edit(existing.id),
                        endpoint: endpoint
                    )
                } else {
                    favoritePlaceSheet = FavoritePlaceSheetItem(
                        mode: .create(draft(for: endpoint, coordinate: coordinate)),
                        endpoint: endpoint
                    )
                }
            } label: {
                Label(
                    existing == nil ? L10n.tripAddToFavorites : L10n.placeAlreadySaved,
                    systemImage: existing == nil ? "star" : "star.fill"
                )
                .font(duoSheet ? .caption.weight(.medium) : .subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(existing == nil ? accessibilityLabel : L10n.tripEditFavoritePlace)
        }
    }

    private func draft(
        for endpoint: FavoritePlaceSheetItem.Endpoint,
        coordinate: CLLocationCoordinate2D
    ) -> PlaceDraft {
        let placeName: String
        let address: String?
        switch endpoint {
        case .start:
            placeName = startPlaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            address = startAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .end:
            placeName = endPlaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            address = endAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let resolvedName: String
        if !placeName.isEmpty {
            resolvedName = placeName
        } else if let address, !address.isEmpty {
            resolvedName = address
        } else {
            resolvedName = ""
        }

        return PlaceDraft(
            name: resolvedName,
            coordinate: coordinate,
            address: (address?.isEmpty == false) ? address : nil,
            kind: .other
        )
    }

    @ViewBuilder
    private func favoritePlacePicker(for item: FavoritePlaceSheetItem) -> some View {
        switch item.mode {
        case .create(let draft):
            PlacePickerView(draft: draft) { savedName in
                applyFavoritePlaceName(savedName, to: item.endpoint)
            }
        case .edit(let placeID):
            if let place = places.first(where: { $0.id == placeID }) {
                PlacePickerView(editingPlace: place) { savedName in
                    applyFavoritePlaceName(savedName, to: item.endpoint)
                }
            } else {
                Text(L10n.placeAlreadySaved)
                    .glassSecondaryInk()
            }
        }
    }

    private func applyFavoritePlaceName(_ name: String, to endpoint: FavoritePlaceSheetItem.Endpoint) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch endpoint {
        case .start:
            startPlaceNameText = trimmed
            trip.startPlaceName = trimmed
        case .end:
            endPlaceNameText = trimmed
            trip.endPlaceName = trimmed
        }

        TripDerivedMetrics.refreshSearchIndex(
            for: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters
        )
        try? modelContext.save()
        onDisplayRefresh()
    }

    private func loadFuelEditDefaults(for vehicleID: UUID?, preferTripSnapshot: Bool) {
        let vehicle = vehicleID.flatMap { id in
            sortedDetailVehicles.first(where: { $0.id == id })
        }
        if preferTripSnapshot {
            let catalog = FuelCostCalculator.resolvedConsumption(
                tripConsumption: trip.fuelConsumptionPer100,
                vehicle: vehicle
            )
            fuelConsumptionAtOpen = catalog
            if trip.fuelMeasurementSource == .userMeasured,
               let measured = trip.measuredFuelConsumptionPer100, measured > 0 {
                editedFuelConsumption = measured
            } else {
                editedFuelConsumption = catalog
            }
            editedFuelUnitPrice = FuelCostCalculator.resolvedUnitPrice(
                tripUnitPrice: trip.fuelUnitPrice,
                vehicle: vehicle
            )
        } else {
            editedFuelConsumption = FuelCostCalculator.resolvedConsumption(vehicle: vehicle)
            fuelConsumptionAtOpen = editedFuelConsumption
            editedFuelUnitPrice = FuelCostCalculator.resolvedUnitPrice(vehicle: vehicle)
        }
    }

    private func fuelUnitPriceLabel(for vehicle: VehicleProfile?) -> String {
        vehicle?.fuelType == .electric ? L10n.fuelUnitCostPerKWh : L10n.fuelUnitCostPerLiter
    }

    private func saveEdits() {
        let previousRollup = TripRollupService.snapshot(of: trip)
        let previousOdometer = TripOdometerSnapshot(
            meters: trip.distanceMeters,
            startedAt: trip.startedAt,
            vehicleID: trip.vehicleID
        )

        trip.note = noteText.isEmpty ? nil : noteText
        if selectedCategoryID != trip.categoryID {
            trip.categoryOrigin = .user
            trip.clearPendingSuggestion()
        }
        trip.categoryID = selectedCategoryID
        let vehicle = selectedVehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: modelContext) }
        VehicleResolver.assign(vehicle: vehicle, to: trip)
        trip.startAddress = startAddressText.isEmpty ? nil : startAddressText
        trip.endAddress = endAddressText.isEmpty ? nil : endAddressText
        trip.startPlaceName = startPlaceNameText.isEmpty ? nil : startPlaceNameText
        trip.endPlaceName = endPlaceNameText.isEmpty ? nil : endPlaceNameText
        trip.startedAt = editedStartedAt
        if trip.endedAt != nil {
            trip.endedAt = max(editedEndedAt, editedStartedAt)
        }
        let didTrim = applyGPSTrimIfNeeded()
        let consumptionChanged = abs(editedFuelConsumption - fuelConsumptionAtOpen) > 0.049
        if consumptionChanged {
            trip.measuredFuelConsumptionPer100 = editedFuelConsumption
            trip.fuelMeasurementSource = .userMeasured
            FuelCostCalculator.applyEstimate(
                to: trip,
                distanceMeters: trip.distanceMeters,
                vehicle: vehicle,
                consumptionPer100: trip.fuelConsumptionPer100,
                unitPrice: editedFuelUnitPrice
            )
        } else {
            FuelCostCalculator.applyEstimate(
                to: trip,
                distanceMeters: trip.distanceMeters,
                vehicle: vehicle,
                consumptionPer100: editedFuelConsumption,
                unitPrice: editedFuelUnitPrice
            )
        }
        TripDerivedMetrics.recompute(
            for: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            fuelType: vehicle?.fuelType ?? .petrol,
            vehicle: vehicle
        )
        VehicleOdometerService.tripUpdated(trip, previous: previousOdometer, in: modelContext)
        TripRollupService.update(trip, from: previousRollup, in: modelContext)
        TripFuelDependencyService.invalidateSuccessor(of: trip, in: modelContext)
        if consumptionChanged, let vehicleID = trip.vehicleID {
            TripFuelCalibrationService.rebuild(for: vehicleID, in: modelContext)
            TripFuelCalibrationService.recomputeVehicleTrips(vehicleID: vehicleID, in: modelContext)
        }
        if let journal = trip.journal {
            TravelJournalTotals.refresh(journal)
        } else {
            TravelJournalTotals.refresh(journalID: trip.journalID, in: modelContext)
        }
        originalNoteText = noteText
        try? modelContext.save()
        VehicleCareNotificationScheduler.evaluateKmReminders(for: trip.vehicleID, in: modelContext)
        ToastPresenter.shared.show(.tripSaved)
        onDisplayRefresh()
        if didTrim {
            onRouteInvalidated()
        }
    }

    @discardableResult
    private func applyGPSTrimIfNeeded() -> Bool {
        guard trimHeadCount > 0 || trimTailCount > 0 else { return false }

        var sorted = trip.sortedPoints
        guard sorted.count > trimHeadCount + trimTailCount else { return false }

        if trimHeadCount > 0 {
            sorted.removeFirst(trimHeadCount)
        }
        if trimTailCount > 0 {
            sorted.removeLast(trimTailCount)
        }

        for point in trip.points {
            modelContext.delete(point)
        }
        trip.points.removeAll()

        var distance: Double = 0
        var previousLocation: CLLocation?
        for (index, oldPoint) in sorted.enumerated() {
            let point = TripPoint(
                timestamp: oldPoint.timestamp,
                latitude: oldPoint.latitude,
                longitude: oldPoint.longitude,
                sequence: index,
                speedMps: oldPoint.speedMps,
                trip: trip
            )
            trip.points.append(point)
            modelContext.insert(point)

            let location = CLLocation(latitude: oldPoint.latitude, longitude: oldPoint.longitude)
            if let previousLocation {
                distance += location.distance(from: previousLocation)
            }
            previousLocation = location
        }

        trip.distanceMeters = distance
        trip.invalidatePointCaches()
        TripDetailViewModel.invalidateSpeedSegmentCache(for: trip.id)
        TripRoutePathCache.shared.remove(for: trip.id)
        TripMapSnapshotCache.shared.remove(for: trip.id)
        DevLog.shared.log(
            .tripDetail,
            "gps trim trip=\(trip.id.uuidString.prefix(8)) head=\(trimHeadCount) tail=\(trimTailCount)"
        )
        trimHeadCount = 0
        trimTailCount = 0
        recordedPointCount = trip.points.count
        return true
    }
}

private struct TripStopEditRow: View {
    @Bindable var stop: TripStop
    @Environment(\.colorScheme) private var colorScheme
    @State private var startedAt: Date = Date()

    private let durationRange = 1...240

    private var fieldInk: Color {
        GlassText.primary(for: colorScheme)
    }

    private var fieldSecondaryInk: Color {
        GlassText.secondary(for: colorScheme)
    }

    private var durationMinutes: Binding<Int> {
        Binding(
            get: {
                max(durationRange.lowerBound, Int((stop.durationSeconds / 60.0).rounded()))
            },
            set: { newValue in
                let clamped = min(durationRange.upperBound, max(durationRange.lowerBound, newValue))
                stop.durationSeconds = TimeInterval(clamped * 60)
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stopMiniCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tripStartedAt)
                        .font(.caption)
                        .foregroundStyle(fieldSecondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    DatePicker(L10n.tripStartedAt, selection: $startedAt, displayedComponents: .date)
                        .glassDatePicker()
                        .scaleEffect(0.75, anchor: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DatePicker(L10n.tripStartedAt, selection: $startedAt, displayedComponents: .hourAndMinute)
                        .glassDatePicker()
                        .scaleEffect(0.75, anchor: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onChange(of: startedAt) { _, newValue in
                    stop.startedAt = newValue
                }
            }

            stopMiniCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.duration)
                        .font(.caption)
                        .foregroundStyle(fieldSecondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 6) {
                        stopStepButton(systemImage: "minus") {
                            durationMinutes.wrappedValue -= 1
                        }
                        .disabled(durationMinutes.wrappedValue <= durationRange.lowerBound)

                        Text(DateFormatters.formatDuration(TimeInterval(durationMinutes.wrappedValue * 60)))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(fieldInk)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)

                        stopStepButton(systemImage: "plus") {
                            durationMinutes.wrappedValue += 1
                        }
                        .disabled(durationMinutes.wrappedValue >= durationRange.upperBound)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            startedAt = stop.startedAt
        }
    }

    private func stopMiniCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .modifier(TripDetailEditWell(padding: 8, fillsHeight: true))
    }

    private func stopStepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(fieldInk)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .glassField(cornerRadius: 6)
        }
        .buttonStyle(.glassPlainHit)
    }
}

/// Light `glassChrome` wells use a tinted fill and white type.
private struct TripDetailEditWell: ViewModifier {
    var padding: CGFloat = 8
    var fillsHeight: Bool = false
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(ink)
            .tint(ink)
            .padding(padding)
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .leading
            )
            .background { well }
    }

    private var ink: Color {
        GlassText.primary(for: colorScheme)
    }

    private var well: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(fill)
            .overlay {
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.28), lineWidth: 1)
            }
    }

    private var fill: Color {
        GlassTokens.fieldFill(for: colorScheme, palette: shellPalette)
    }
}

/// Remembers where the trip-detail sheet was scrolled and puts it back if a
/// travel-menu save moves it. The first change after opening the sheet is the
/// one that jumps; later changes in the same visit do not.
@MainActor
private final class TripDetailMenuScrollHold {
    fileprivate weak var view: TripDetailMenuScrollHoldView?
    fileprivate var pinnedOffset: CGPoint?
    fileprivate var pinUntil: CFTimeInterval = 0
    fileprivate var lastStableOffset: CGPoint?

    func pin() {
        view?.beginPin()
    }
}

private struct TripDetailMenuScrollHoldAnchor: UIViewRepresentable {
    var hold: TripDetailMenuScrollHold

    func makeUIView(context: Context) -> TripDetailMenuScrollHoldView {
        let view = TripDetailMenuScrollHoldView()
        view.hold = hold
        hold.view = view
        return view
    }

    func updateUIView(_ uiView: TripDetailMenuScrollHoldView, context: Context) {
        uiView.hold = hold
        hold.view = uiView
        uiView.restoreIfNeeded()
    }
}

private final class TripDetailMenuScrollHoldView: UIView {
    weak var hold: TripDetailMenuScrollHold?
    private var observation: NSKeyValueObservation?
    private var isApplying = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
        if hold?.lastStableOffset == nil, let scroll = enclosingScrollView(), !scroll.isTracking {
            hold?.lastStableOffset = scroll.contentOffset
        }
        restoreIfNeeded()
    }

    func beginPin() {
        guard let scroll = enclosingScrollView(), let hold else { return }
        attachIfNeeded()
        let current = scroll.contentOffset
        if let stable = hold.lastStableOffset, abs(current.y - stable.y) > 24 {
            hold.pinnedOffset = stable
        } else {
            hold.pinnedOffset = current
            hold.lastStableOffset = current
        }
        hold.pinUntil = CACurrentMediaTime() + 0.55
        restoreIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.restoreIfNeeded()
        }
    }

    func restoreIfNeeded() {
        guard !isApplying, let hold else { return }
        guard CACurrentMediaTime() < hold.pinUntil, let pinned = hold.pinnedOffset else { return }
        guard let scroll = enclosingScrollView() else { return }
        if scroll.isTracking || scroll.isDragging {
            hold.pinUntil = 0
            hold.pinnedOffset = nil
            hold.lastStableOffset = scroll.contentOffset
            return
        }
        guard abs(scroll.contentOffset.y - pinned.y) > 0.5 else { return }
        isApplying = true
        scroll.setContentOffset(pinned, animated: false)
        isApplying = false
    }

    private func attachIfNeeded() {
        guard observation == nil, let scroll = enclosingScrollView() else { return }
        observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.noteOffset()
            }
        }
    }

    private func noteOffset() {
        guard !isApplying, let hold, let scroll = enclosingScrollView() else { return }
        if CACurrentMediaTime() < hold.pinUntil {
            restoreIfNeeded()
            return
        }
        hold.lastStableOffset = scroll.contentOffset
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }

    deinit {
        observation?.invalidate()
    }
}
