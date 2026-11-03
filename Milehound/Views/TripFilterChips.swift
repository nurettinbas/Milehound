import SwiftData
import SwiftUI

/// Week summary + search + date/category/vehicle/place filters pinned above the trip rows.
struct TripListFiltersBar: View {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    @Binding var selectedDateSection: TripDateSection?
    @Binding var selectedCategoryID: String?
    @Binding var selectedVehicleFilter: TripListPage.VehicleFilter?
    @Binding var selectedPlaceID: UUID?
    @Binding var listMode: TripsTabListMode
    /// Wide layouts show both libraries, so the segment is only the phone switch.
    var showsModePicker: Bool = true
    var isSearchBusy: Bool = false
    var vehicles: [VehicleProfile] = []
    var places: [SavedPlace] = []
    /// Compact “Last 7 days” strip shown above search when non-empty.
    var weekSummaryText: String = ""
    var weekSummaryRefreshToken: Int = 0
    var isWeekSummaryRefreshing: Bool = false

    @Namespace private var dateChipNamespace
    @Namespace private var vehicleChipNamespace
    @Namespace private var placeChipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var isFiltersExpanded = false

    private var dateSelectionKey: String {
        if let selectedDateSection { return "date:\(selectedDateSection.rawValue)" }
        return "date:all"
    }

    private var activeChipFilterCount: Int {
        var count = 0
        if selectedDateSection != nil { count += 1 }
        if selectedCategoryID != nil { count += 1 }
        if selectedVehicleFilter != nil { count += 1 }
        if selectedPlaceID != nil { count += 1 }
        return count
    }

    private var hasChipFiltersActive: Bool {
        activeChipFilterCount > 0
    }

    private var showsWeekSummary: Bool {
        !weekSummaryText.isEmpty
    }

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsModePicker {
                listModePicker
            } else {
                GlassSectionHeader(title: listMode.title)
                    .accessibilityIdentifier(listMode == .travels ? "trips.library.travels" : "trips.library.trips")
            }

            if showsWeekSummary && listMode == .trips {
                weekSummaryRow
            }

            HStack(alignment: .center, spacing: 8) {
                searchField
                if listMode == .trips {
                    filtersToggleButton
                    if hasChipFiltersActive {
                        clearFiltersButton
                    }
                }
            }
            .animation(reduceMotion ? nil : MilehoundMotion.cardSpring, value: hasChipFiltersActive)

            if listMode == .trips, isFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    dateFilterRow
                    TripFilterChips(selectedCategoryID: $selectedCategoryID, usesCardInsets: false)
                    vehicleFilterRow
                    if !sortedPlaces.isEmpty {
                        placeFilterRow
                    }
                }
                .transition(filtersRevealTransition)
            }
        }
        .animation(reduceMotion ? nil : MilehoundMotion.cardSpring, value: isFiltersExpanded)
        .animation(reduceMotion ? nil : MilehoundMotion.snappy, value: isSearchBusy)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
    }

    private var listModePicker: some View {
        Picker(L10n.tripsSegmentTravels, selection: $listMode) {
            ForEach(TripsTabListMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .glassSegmentedStyle()
        .accessibilityIdentifier("trips.segment")
    }

    private var weekSummaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .symbolVariant(isWeekSummaryRefreshing ? .fill : .none)
                .foregroundStyle(shellPalette.tintColor(for: colorScheme))
                .symbolEffect(.bounce, value: weekSummaryRefreshToken)
                .frame(width: 16)

            Text(L10n.lastSevenDays)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(weekSummaryText)
                .font(.caption2)
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .numericTextAnimation(value: weekSummaryAnimationID)
        }
        .padding(.vertical, 2)
        .glassEntranceGlint(
            cornerRadius: 10,
            id: "trips.week.\(weekSummaryRefreshToken)",
            isEnabled: weekSummaryRefreshToken > 0 && !reduceMotion && !UITestSupport.isEnabled
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.lastSevenDays). \(weekSummaryText)")
    }

    private var weekSummaryAnimationID: String {
        WeekSummaryRefresh.animationID(text: weekSummaryText, token: weekSummaryRefreshToken)
    }

    private var filtersRevealTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSearchBusy ? shellPalette.tintColor(for: colorScheme) : Color.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: isSearchBusy && !reduceMotion)
                .accessibilityHidden(true)

            TextField(listMode == .travels ? L10n.journalSearchPlaceholder : L10n.searchTrips, text: $searchText)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused.wrappedValue = false
                    KeyboardDismiss.dismiss()
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GlassText.secondary(for: colorScheme))
                        .glassGlyphHit()
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityLabel(L10n.placePickerSearchClear)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .glassInputWell(cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    shellPalette.tintColor(for: colorScheme).opacity(isSearchBusy ? 0.38 : 0),
                    lineWidth: 1
                )
        }
        .shadow(
            color: shellPalette.tintColor(for: colorScheme).opacity(isSearchBusy && !reduceMotion ? 0.22 : 0),
            radius: 10,
            y: 0
        )
        .overlay(alignment: .bottom) {
            if isSearchBusy {
                SearchFieldScanComet(reduceMotion: reduceMotion)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 3)
                    .transition(.opacity)
                    .accessibilityIdentifier("trips.search.activity")
            }
        }
        .accessibilityValue(isSearchBusy ? L10n.searchWorking : "")
    }

    private var filtersToggleButton: some View {
        Button {
            MilehoundHaptics.selection()
            if reduceMotion {
                isFiltersExpanded.toggle()
            } else {
                withAnimation(MilehoundMotion.cardSpring) {
                    isFiltersExpanded.toggle()
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
                .symbolVariant(isFiltersExpanded || hasChipFiltersActive ? .fill : .none)
                .foregroundStyle(
                    isFiltersExpanded || hasChipFiltersActive
                        ? shellPalette.tintColor(for: colorScheme)
                        : Color.secondary
                )
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .glassField(cornerRadius: 10)
                .overlay(alignment: .topTrailing) {
                    if activeChipFilterCount > 0 {
                        Text("\(activeChipFilterCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, 3)
                            .background(shellPalette.tintColor(for: colorScheme), in: Capsule())
                            .offset(x: 4, y: -4)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(L10n.tripsFilters)
        .accessibilityValue(
            activeChipFilterCount > 0
                ? "\(activeChipFilterCount)"
                : ""
        )
        .accessibilityAddTraits(isFiltersExpanded ? .isSelected : [])
    }

    private var clearFiltersButton: some View {
        Button {
            MilehoundHaptics.selection()
            clearChipFilters()
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .glassAccentForeground()
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .glassField(cornerRadius: 10)
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(L10n.tripsFiltersClear)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.85)))
    }

    private func clearChipFilters() {
        let clear = {
            selectedDateSection = nil
            selectedCategoryID = nil
            selectedVehicleFilter = nil
            selectedPlaceID = nil
        }
        if reduceMotion {
            clear()
        } else {
            withAnimation(MilehoundMotion.cardSpring) {
                clear()
            }
        }
    }

    private var sortedPlaces: [SavedPlace] {
        places.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var placeSelectionKey: String {
        if let selectedPlaceID { return "place:\(selectedPlaceID.uuidString)" }
        return "place:all"
    }

    private var dateFilterRow: some View {
        filterChipRow(label: L10n.filterDate) {
            chipScroller(selectionKey: dateSelectionKey) {
                dateChip(
                    title: L10n.all,
                    key: "date:all",
                    isSelected: selectedDateSection == nil
                ) {
                    selectedDateSection = nil
                }
                ForEach(TripDateSection.allCases) { section in
                    dateChip(
                        title: section.title,
                        key: "date:\(section.rawValue)",
                        isSelected: selectedDateSection == section
                    ) {
                        selectedDateSection = selectedDateSection == section ? nil : section
                    }
                }
            }
        }
    }

    private var vehicleSelectionKey: String {
        switch selectedVehicleFilter {
        case .unassigned: return "vehicle:unassigned"
        case .vehicle(let id): return "vehicle:\(id.uuidString)"
        case nil: return "vehicle:all"
        }
    }

    private var vehicleFilterRow: some View {
        filterChipRow(label: L10n.filterVehicle) {
            chipScroller(selectionKey: vehicleSelectionKey) {
                vehicleChip(
                    title: L10n.all,
                    key: "vehicle:all",
                    isSelected: selectedVehicleFilter == nil
                ) {
                    selectedVehicleFilter = nil
                }
                vehicleChip(
                    title: L10n.string("stats.vehicle.unassigned"),
                    key: "vehicle:unassigned",
                    isSelected: selectedVehicleFilter == .unassigned
                ) {
                    selectedVehicleFilter = selectedVehicleFilter == .unassigned ? nil : .unassigned
                }
                ForEach(sortedVehicles) { vehicle in
                    let key = "vehicle:\(vehicle.id.uuidString)"
                    let filter = TripListPage.VehicleFilter.vehicle(vehicle.id)
                    vehicleChip(
                        title: vehicle.name,
                        key: key,
                        isSelected: selectedVehicleFilter == filter,
                        avatarSystemImage: vehicle.systemImage,
                        avatarPhotoFileName: vehicle.photoFileName,
                        avatarIsElectric: vehicle.fuelType == .electric
                    ) {
                        selectedVehicleFilter = selectedVehicleFilter == filter ? nil : filter
                    }
                }
            }
        }
    }

    private var placeFilterRow: some View {
        filterChipRow(label: L10n.filterPlace) {
            chipScroller(selectionKey: placeSelectionKey) {
                placeChip(
                    title: L10n.all,
                    key: "place:all",
                    isSelected: selectedPlaceID == nil
                ) {
                    selectedPlaceID = nil
                }
                ForEach(sortedPlaces, id: \.id) { place in
                    let key = "place:\(place.id.uuidString)"
                    placeChip(
                        title: place.name,
                        key: key,
                        isSelected: selectedPlaceID == place.id
                    ) {
                        selectedPlaceID = selectedPlaceID == place.id ? nil : place.id
                    }
                }
            }
        }
    }

    private func filterChipRow<Content: View>(
        label: String,
        @ViewBuilder chips: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(label):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .fixedSize()
                .accessibilityHidden(true)

            chips()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func chipScroller<Content: View>(
        selectionKey: String,
        @ViewBuilder chips: () -> Content
    ) -> some View {
        let chipViews = chips()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassChipGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        chipViews
                    }
                    .animation(reduceMotion ? nil : MilehoundMotion.cardSpring, value: selectionKey)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: selectionKey) { _, newKey in
                revealChip(withID: newKey, using: proxy)
            }
        }
        .glassChipScroller()
    }

    private func dateChip(
        title: String,
        key: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: dateChipNamespace,
            highlightID: "tripDateFilterHighlight",
            size: .compact,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(MilehoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }

    private func vehicleChip(
        title: String,
        key: String,
        isSelected: Bool,
        avatarSystemImage: String? = nil,
        avatarPhotoFileName: String? = nil,
        avatarIsElectric: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: vehicleChipNamespace,
            highlightID: "tripVehicleFilterHighlight",
            size: .compact,
            avatarSystemImage: avatarSystemImage,
            avatarPhotoFileName: avatarPhotoFileName,
            avatarIsElectric: avatarIsElectric,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(MilehoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }

    private func placeChip(
        title: String,
        key: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: placeChipNamespace,
            highlightID: "tripPlaceFilterHighlight",
            size: .compact,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(MilehoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }

    private func revealChip(withID id: String, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation(MilehoundMotion.cardSpring) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

struct TripFilterChips: View {
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Binding var selectedCategoryID: String?
    /// When embedded in a glass card, outer list insets already handle horizontal padding.
    var usesCardInsets: Bool = true

    @Namespace private var chipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var selectionKey: String {
        if let selectedCategoryID { return "category:\(selectedCategoryID)" }
        return "all"
    }

    private var leadingInset: CGFloat {
        usesCardInsets ? GlassTokens.listContentHorizontalInset : 0
    }

    private var trailingInset: CGFloat {
        usesCardInsets ? GlassTokens.listContentHorizontalInset : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(L10n.filterCategory):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .fixedSize()
                .padding(.leading, leadingInset)
                .accessibilityHidden(true)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassChipGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            filterChip(
                                title: L10n.all,
                                key: "all",
                                isSelected: selectedCategoryID == nil
                            ) {
                                selectedCategoryID = nil
                            }
                            ForEach(categories) { category in
                                let id = category.id.uuidString
                                filterChip(
                                    title: category.name,
                                    key: "category:\(id)",
                                    isSelected: selectedCategoryID == id
                                ) {
                                    selectedCategoryID = selectedCategoryID == id ? nil : id
                                }
                            }
                        }
                    }
                    .padding(.trailing, trailingInset)
                    .animation(reduceMotion ? nil : MilehoundMotion.cardSpring, value: selectionKey)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onChange(of: selectionKey) { _, newKey in
                    revealChip(withID: newKey, using: proxy)
                }
            }
            .glassChipScroller()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.filterCategory)
    }

    private func revealChip(withID id: String, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation(MilehoundMotion.cardSpring) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func filterChip(
        title: String,
        key: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: chipNamespace,
            highlightID: "tripFilterHighlight",
            size: .compact,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(MilehoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }
}

/// Brand comet that travels along the search field — no spinner, no extra copy.
private struct SearchFieldScanComet: View {
    var reduceMotion: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let barWidth = max(40, width * 0.36)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            shellPalette.tintColor(for: colorScheme).opacity(0.55),
                            shellPalette.tintColor(for: colorScheme),
                            shellPalette.tintColor(for: colorScheme).opacity(0.55),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: barWidth, height: 2)
                .shadow(color: shellPalette.tintColor(for: colorScheme).opacity(0.65), radius: 4, y: 0)
                .offset(x: (width - barWidth) * phase)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            if reduceMotion {
                phase = 0.5
                return
            }
            phase = 0
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.easeInOut(duration: 1.12).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}
