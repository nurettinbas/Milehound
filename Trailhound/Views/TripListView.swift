import SwiftData
@preconcurrency import Dispatch
import SwiftUI
import UIKit

struct TripListView: View {
    // Deliberately no `@Query` for trips: the list pages through the store instead of holding
    // every trip in memory. `ModelContext.didSave` stands in for the change tracking.
    @Query private var places: [SavedPlace]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.trailhoundLayout) private var layout
    @Environment(TripRecordingService.self) private var recordingService
    @Bindable private var settings = AppSettings.shared

    @Bindable private var notificationStore = AppNotificationStore.shared
    @Bindable private var careSummary = VehicleCareSummaryStore.shared

    @State private var selectedCategoryID: String?
    @State private var selectedDateSection: TripDateSection?
    @State private var selectedVehicleFilter: TripListPage.VehicleFilter?
    @State private var selectedPlaceID: UUID?
    @State private var listMode: TripsTabListMode = .trips
    @State private var loadedJournals: [TravelJournal] = []
    @State private var journalPageLimit = TravelJournalPage.pageSize
    @State private var hasMoreJournals = false
    @State private var hasAnyJournals = false
    @State private var journalEditor: TravelJournalEditorDraft?
    @State private var travelSuggestion: TravelJournalSuggestion?
    @State private var mergeSelection = Set<UUID>()
    @State private var isMergeMode = false
    @State private var aggregatesRefreshTask: Task<Void, Never>?
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var sideColumnChrome = SideColumnChromeState.shared

    @State private var orphanTrips: [TripRecoveryService.OrphanTrip] = []
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var isSearchApplying = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var journalSearchText = ""
    @State private var journalDebouncedSearchText = ""
    @State private var journalSearchDebounceTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isJournalSearchFocused: Bool
    @Namespace private var tripMorphNamespace
    @State private var morphingTripID: UUID?
    @State private var endCredits: RecordingEndCreditsSnapshot?
    /// How far the floating blue bar has slid down toward the trip list.
    @State private var creditsSlideY: CGFloat = 0
    @State private var isCreditsSliding = false
    @State private var listLandingMinY: CGFloat = 0
    /// Pinned at Stop so overlay keeps the live recording card's exact frame.
    @State private var pinnedCreditsCardAnchor = RecordingCardAnchor()
    /// Armed before recording state flips so entrance anim can't lose the race on device.
    @State private var coldOpenArmed = false
    @State private var coldOpenTripID: UUID?
    @State private var scrollToTopToken = 0
    @State private var scrollToTopRequest: TripListScrollToTopRequest?
    @State private var isRecordingCardInViewport = true
    @State private var recordingCardViewportTask: Task<Void, Never>?
    /// Rotation rebuilds the list and reports the card gone. Off-screen samples during this window are dropped.
    @State private var recordingViewportSettling = false
    @State private var recordingViewportSettleTask: Task<Void, Never>?
    @State private var showLiveFollowMap = false
    /// Chrome for the recording book. Held for the length of a turn so the card
    /// does not swap sides while the panes are still sliding.
    @State private var recordingBookFolds = false
    @State private var recordingBookLiveLeads = false
    @State private var paneTripID: UUID?
    @State private var liveFollowCardAnchor = RecordingCardAnchor()
    @State private var liveFollowVehiclePhoto: UIImage?

    /// The pages fetched so far, newest first.
    @State private var loadedTrips: [Trip] = []
    /// Grouped alongside the fetch so the sort does not rerun on every body pass.
    @State private var tripGroups: [(section: TripDateSection, trips: [Trip])] = []
    @State private var pageLimit = TripListPage.pageSize
    @State private var hasMorePages = false
    @State private var hasAnyTrips = false
    /// First `onAppear` loads the library. Later tab visits must not fetch again.
    @State private var didInitialLoad = false
    /// Calendar day the loaded rows were last grouped into Today / Yesterday / ….
    @State private var lastGroupedDay: Date?
    @State private var suggestionLoader: TravelSuggestionLoader?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var weekSummaryText = ""
    @State private var weekSummaryRefreshToken = 0
    @State private var isWeekSummaryRefreshing = false
    private var isSearchBusy: Bool {
        TripListViewModel.isSearchActivityVisible(
            searchText: searchText,
            debouncedSearchText: debouncedSearchText,
            isApplying: isSearchApplying
        )
    }

    private var hasActiveFilters: Bool {
        pageFilters.isActive
    }

    private var selectedPlaceName: String? {
        guard let selectedPlaceID else { return nil }
        return places.first(where: { $0.id == selectedPlaceID })?.name
    }

    private var pageFilters: TripListPage.Filters {
        TripListPage.Filters(
            searchText: debouncedSearchText,
            categoryID: selectedCategoryID,
            dateSection: selectedDateSection,
            vehicleFilter: selectedVehicleFilter,
            placeName: selectedPlaceName
        )
    }

    private var completedTrips: [Trip] {
        loadedTrips
    }

    /// Selection may include unfinished/orphan rows; only completed legs can merge.
    private var completedMergeSelectionCount: Int {
        loadedTrips.filter { mergeSelection.contains($0.id) && $0.endedAt != nil }.count
    }

    private func reloadTrips() {
        let filters = pageFilters
        let fetched = (try? modelContext.fetch(
            TripListPage.descriptor(filters: filters, limit: pageLimit)
        )) ?? []

        let matching = fetched.filter { matchesInMemoryFilters($0, filters) }
        let searching = !filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        hasMorePages = searching
            ? matching.count > pageLimit
            : fetched.count > pageLimit
        let visible = Array(matching.prefix(pageLimit))
        let today = Calendar.current.startOfDay(for: Date())
        let dayChanged = today != lastGroupedDay
        lastGroupedDay = today
        let stamps = visible.map(Self.rowStamp)
        let previous = loadedTrips.map(Self.rowStamp)
        if stamps == previous, !dayChanged {
            return
        }
        if stamps != previous {
            loadedTrips = visible
        }
        tripGroups = TripDateGrouping.groupedSections(from: loadedTrips)
    }

    /// Tab return after the first load. Same-day visits do not touch the store.
    private func handleTripListAppear() {
        if searchText != debouncedSearchText {
            debouncedSearchText = searchText
        }
        if didInitialLoad {
            regroupLoadedTripsIfDayChanged()
            beginColdOpenIfNeeded(onlyIfRecentlyStarted: true)
            consumeTripDeepLink()
            return
        }
        didInitialLoad = true
        refreshOrphans()
        refreshListAggregates()
        reloadTrips()
        reloadJournals()
        careSummary.refresh(in: modelContext)
        notificationStore.reload()
        beginColdOpenIfNeeded(onlyIfRecentlyStarted: true)
        consumeTripDeepLink()
    }

    /// Section titles move with the calendar day. Regroup the rows already in memory.
    private func regroupLoadedTripsIfDayChanged() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != lastGroupedDay else { return }
        lastGroupedDay = today
        tripGroups = TripDateGrouping.groupedSections(from: loadedTrips)
        refreshListAggregates()
    }

    private static func rowStamp(_ trip: Trip) -> TripListRowStamp {
        TripListRowStamp(
            id: trip.id,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt,
            distanceMeters: trip.distanceMeters,
            startPlaceName: trip.startPlaceName,
            endPlaceName: trip.endPlaceName,
            startAddress: trip.startAddress,
            endAddress: trip.endAddress,
            categoryRaw: trip.categoryRaw,
            note: trip.note,
            maxSpeedMps: trip.maxSpeedMps,
            estimatedFuelCost: trip.estimatedFuelCost,
            dynamicFuelCost: trip.dynamicFuelCost,
            pendingSuggestedCategoryID: trip.pendingSuggestedCategoryID,
            vehicleID: trip.vehicleID
        )
    }

    private func consumeTripDeepLink() {
        guard let id = tabSelection.consumePendingTripID() else { return }
        let resolution = TripDeepLinkResolver.resolve(
            tripID: id,
            in: modelContext,
            activeTripID: recordingService.activeTripID
        )
        DevLog.shared.log(
            .tripDetail,
            "consume trip=\(id.uuidString.prefix(8)) path=\(tabSelection.tripsPath.count)"
        )
        switch resolution {
        case .finished(let trip):
            tabSelection.showFinishedTrip(trip)
        case .recording:
            tabSelection.focusRecordingCard()
        case .unfinished:
            break
        case .missing:
            ToastPresenter.shared.show(.tripNotFound)
        }
    }

    /// The parts of a filter the store cannot answer exactly: date-section boundaries move with
    /// the wall clock, and a stale `searchIndex` can miss a live saved-place name. Place names
    /// are also re-checked so a renamed favorite stays consistent with the chip's current
    /// `SavedPlace.name`. Text search is always applied here: SwiftData rejects optional
    /// `searchIndex` unwraps in `#Predicate`, so the fetch is over-inclusive.
    private func matchesInMemoryFilters(_ trip: Trip, _ filters: TripListPage.Filters) -> Bool {
        if let section = filters.dateSection,
           !TripDateGrouping.matches(section, date: trip.startedAt) {
            return false
        }
        if !TripPlaceFilter.matches(
            startPlaceName: trip.startPlaceName,
            endPlaceName: trip.endPlaceName,
            placeName: filters.placeName
        ) {
            return false
        }
        if filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return TripListViewModel.matchesSearch(
            trip,
            searchText: filters.searchText,
            places: places,
            privacyRadius: settings.privacyRadiusMeters
        )
    }

    private func loadNextPage() {
        guard hasMorePages else { return }
        pageLimit += TripListPage.pageSize
        reloadTrips()
    }

    private func resetPagingAndReload() {
        pageLimit = TripListPage.pageSize
        reloadTrips()
    }

    private func scheduleSearchApply(_ pending: String) {
        searchDebounceTask?.cancel()
        if pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchApplying = false
        }
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, searchText == pending else { return }
            let showActivity = !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if showActivity {
                isSearchApplying = true
            }
            debouncedSearchText = pending
            if showActivity {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                if searchText == pending {
                    isSearchApplying = false
                }
            } else {
                isSearchApplying = false
            }
        }
    }

    private func reloadJournals() {
        let filters = TravelJournalPage.Filters(searchText: journalQueryText)
        let page = (try? TravelJournalPage.fetch(
            filters: filters,
            limit: journalPageLimit,
            in: modelContext
        )) ?? (journals: [], hasMore: false)
        hasMoreJournals = page.hasMore
        loadedJournals = page.journals
        hasAnyJournals = (try? modelContext.fetchCount(TravelJournalPage.countDescriptor())).map { $0 > 0 } ?? false
        scheduleTravelSuggestionRefresh()
    }

    private func loadNextJournalPage() {
        guard hasMoreJournals else { return }
        journalPageLimit += TravelJournalPage.pageSize
        reloadJournals()
    }

    /// The suggestion banner is only on Travels. Computing it scans every completed trip,
    /// so it stays off the trips-tab appear path and off the main actor.
    private var showsTravelSuggestion: Bool {
        listMode == .travels || showsLibrarySplit
    }

    private func scheduleTravelSuggestionRefresh() {
        suggestionTask?.cancel()
        guard showsTravelSuggestion else { return }
        let homes = TravelJournalSuggester.homeSnapshots(from: places)
        let ranges = loadedJournals.map {
            TravelJournalDateRange(start: $0.startedOn, end: $0.endedOn)
        }
        let dismissed = settings.dismissedJournalSuggestionFingerprints
        let loader = suggestionLoader ?? TravelSuggestionLoader(modelContainer: modelContext.container)
        suggestionLoader = loader
        suggestionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let suggestion = await loader.suggestion(
                homes: homes,
                existingJournalRanges: ranges,
                dismissedFingerprints: dismissed
            )
            guard !Task.isCancelled else { return }
            travelSuggestion = suggestion
        }
    }

    private func acceptTravelSuggestion(_ suggestion: TravelJournalSuggestion) {
        let journal = TravelJournal(title: suggestion.title)
        modelContext.insert(journal)
        let ids = suggestion.tripIDs
        let members = (try? modelContext.fetch(TripListPage.descriptor(forIDs: Set(ids)))) ?? []
        for trip in members {
            TravelJournalTotals.assign(trip: trip, to: journal, in: modelContext)
        }
        TravelJournalTotals.refresh(journal)
        try? modelContext.save()
        travelSuggestion = nil
    }

    /// Open book and iPad, both orientations. One mounted pair of lists follows the window
    /// through a turn, so the page does not scale from the wide book down to one column.
    private var usesLibraryOrientation: Bool {
        guard paneTripID == nil, !showLiveFollowMap else { return false }
        guard !recordingService.state.isActiveSession else { return false }
        return layout.layoutClass == .duoOpen || layout.layoutClass == .pad || layout.isPhoneBook
    }

    /// Open book and iPad landscape show both libraries. Phone landscape stays one column.
    /// A recording, live map, or selected trip keeps the trailing pane for that surface.
    private var showsLibrarySplit: Bool {
        layout.splitsIdleLibrary
            && !recordingService.state.isActiveSession
            && paneTripID == nil
            && !showLiveFollowMap
    }

    /// Trip search and travel search stay separate once both panes are on screen.
    private var journalQueryText: String {
        if showsLibrarySplit { return journalDebouncedSearchText }
        if listMode == .travels { return debouncedSearchText }
        return ""
    }

    private func scheduleJournalSearchApply(_ pending: String) {
        journalSearchDebounceTask?.cancel()
        journalSearchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, journalSearchText == pending else { return }
            journalDebouncedSearchText = pending
        }
    }

    @ViewBuilder
    private func journalListContent(searchText: String, searchBusy: Bool) -> some View {
        let isSearching = TravelJournalPage.Filters(searchText: searchText).isActive

        if let suggestion = travelSuggestion, !isSearching {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .glassAccentForeground()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.journalSuggestChip)
                            .font(.subheadline.weight(.semibold))
                        Text(suggestion.title)
                            .font(.caption)
                            .glassSecondaryInk()
                    }
                    Spacer()
                    Button(L10n.journalSuggestAccept) {
                        acceptTravelSuggestion(suggestion)
                    }
                    .font(.caption.weight(.semibold))
                    Button {
                        settings.dismissJournalSuggestion(suggestion.fingerprint)
                        travelSuggestion = nil
                    } label: {
                        Image(systemName: "xmark")
                            .glassGlyphHit(minSide: 28)
                    }
                    .buttonStyle(.glassPlainHit)
                    .accessibilityLabel(L10n.journalSuggestDismiss)
                }
                .padding(.vertical, 4)
            }
            .glassListRow()
        }

        if loadedJournals.isEmpty {
            if !searchBusy {
                GlassEmptyState(
                    title: isSearching ? L10n.journalEmptySearchTitle : L10n.journalEmptyTitle,
                    systemImage: isSearching ? "magnifyingglass" : "map",
                    message: isSearching ? L10n.journalEmptySearchMessage : L10n.journalEmptyMessage,
                    bounceTrigger: isSearching
                )
                .glassListRow()
                if !isSearching {
                    Button {
                        journalEditor = .create()
                    } label: {
                        Text(L10n.journalCreate)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .trailhoundProminentButton()
                    .tint(TrailhoundBrandColors.brandBottom)
                    .glassListRow()
                }
            }
        } else {
            Section {
                ForEach(Array(loadedJournals.enumerated()), id: \.element.id) { index, journal in
                    NavigationLink(value: journal) {
                        HStack(spacing: 8) {
                            TravelJournalRowView(journal: journal, reduceMotion: reduceMotion)
                            GlassDisclosureChevron()
                        }
                    }
                    .glassHidesNavigationLinkIndicator()
                    .buttonStyle(.glassPlainHit)
                    .accessibilityIdentifier("journal.row.\(journal.id.uuidString)")
                    .glassRow(position: GlassRowPosition.index(index, in: loadedJournals.count))
                    .confirmingDeleteSwipe(title: L10n.journalDelete) {
                        TravelJournalTotals.prepareForDelete(journal)
                        modelContext.delete(journal)
                        try? modelContext.save()
                        ToastPresenter.shared.show(.deleted)
                    }
                }
            }
            .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: loadedJournals.count)
        }

        if hasMoreJournals {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear(perform: loadNextJournalPage)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func refreshListAggregates() {
        hasAnyTrips = (try? modelContext.fetchCount(TripListPage.completedCountDescriptor())).map { $0 > 0 }
            ?? false

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekTrips = (try? modelContext.fetch(
            TripListPage.completedInDescriptor(from: weekAgo)
        )) ?? []
        let stats = StatsViewModel.stats(for: weekTrips, includeNightRatio: false)
        weekSummaryText = L10n.weekSummary(
            distance: stats.totalDistanceText,
            duration: stats.totalDurationText
        )
    }

    @MainActor
    private func refreshFromPull() async {
        let playsMotion = WeekSummaryRefresh.shouldPlayMotion(
            listMode: listMode,
            weekSummaryText: weekSummaryText,
            reduceMotion: reduceMotion
        )
        if playsMotion {
            TrailhoundHaptics.selection()
            isWeekSummaryRefreshing = true
            weekSummaryRefreshToken += 1
        }
        refreshListAggregates()
        reloadTrips()
        reloadJournals()
        careSummary.refresh(in: modelContext)
        if playsMotion {
            try? await Task.sleep(for: WeekSummaryRefresh.motionDuration)
            TrailhoundHaptics.selection()
            isWeekSummaryRefreshing = false
        }
    }

    private func newestCompletedTrip() -> Trip? {
        (try? modelContext.fetch(TripListPage.newestCompletedDescriptor()))?.first
    }

    private var showsVehicleSetupPrompt: Bool {
        !settings.hasCompletedCarSetup
    }

    private var visibleOrphan: TripRecoveryService.OrphanTrip? {
        orphanTrips.first { orphan in
            !orphan.isStale && orphan.id != recordingService.activeTripID
        }
    }

    private var showsActiveRecordingNavAffordance: Bool {
        guard recordingService.state.isActiveSession,
              endCredits == nil,
              recordingService.activeTripID != nil
        else { return false }

        // The upright fold and a split pane keep the recording surface on screen.
        // Landscape with the card in the list does not: scrolling it away needs the steering control.
        guard !layout.pinsRecordingCardToFold, !layout.splitsRecording else { return false }
        return !isRecordingCardInViewport
    }

    /// Live map on the wide book covers the title row. A recording keeps the row so the bell stays.
    private var hidesWideBookNavigationBar: Bool {
        layout.isWideBook && !isMergeMode && showLiveFollowMap
    }

    /// The phone book is short. The Trailhound title sits in the only free row above the card.
    private var phoneBookRecordingHidesTitle: Bool {
        layout.isPhoneBook && recordingService.state.isActiveSession && endCredits == nil
    }

    /// Off-screen has to last, and a turn does not count. The list is rebuilt while the
    /// card is still at the top, which used to flash the steering control on and off.
    private func noteRecordingCardOnScreen(_ onScreen: Bool) {
        if onScreen {
            recordingCardViewportTask?.cancel()
            recordingCardViewportTask = nil
            if !isRecordingCardInViewport { isRecordingCardInViewport = true }
            return
        }
        guard !recordingViewportSettling, recordingCardViewportTask == nil else { return }
        recordingCardViewportTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, !recordingViewportSettling else { return }
            recordingCardViewportTask = nil
            isRecordingCardInViewport = false
        }
    }

    private func beginRecordingViewportSettle() {
        recordingCardViewportTask?.cancel()
        recordingCardViewportTask = nil
        recordingViewportSettling = true
        recordingViewportSettleTask?.cancel()
        recordingViewportSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            recordingViewportSettling = false
        }
    }

    private func resetRecordingCardViewport() {
        recordingCardViewportTask?.cancel()
        recordingCardViewportTask = nil
        recordingViewportSettleTask?.cancel()
        recordingViewportSettling = false
        isRecordingCardInViewport = true
    }

    private var shellPageOwnsLeading: Bool {
        showsStandaloneTripDetail
            || isMergeMode
            || (recordingService.state.isActiveSession && showsActiveRecordingNavAffordance)
    }

    /// The bell has to share this page's single trailing item. A second trailing
    /// item becomes the circle beside the side tab, and a turn leaves it empty.
    /// Standalone trip detail draws its own bar; the shell bell stays there.
    private var pageOwnsTrailingBell: Bool {
        guard !showsStandaloneTripDetail else { return false }
        if isMergeMode { return true }
        if showsLibrarySplit { return !splitCapsuleOwnsTrailing }
        return false
    }

    /// The landscape book draws bell, plus, and merge in the vertical capsule.
    private var splitCapsuleOwnsTrailing: Bool {
        showsLibrarySplit
            && sideColumnChrome.uprightDuoCapsuleFrame(buttonCount: 3, layout: layout) != nil
    }

    /// The upright-Duo capsule already draws the bell. Merge and Cancel stay in the bar.
    private var duoCapsuleOwnsBell: Bool {
        sideColumnChrome.uprightDuoCapsuleFrame(buttonCount: 1, layout: layout) != nil
    }

    private var liveMapCoverPresented: Binding<Bool> {
        Binding(
            get: { showLiveFollowMap && !layout.splitsRecording && !layout.pinsRecordingCardToFold },
            set: { showLiveFollowMap = $0 }
        )
    }

    /// A turn already moves the window. The reflow spring would fade the old page on top.
    private var layoutChangeAnimation: Animation? {
        let rotation = TrailhoundInterfaceRotation.shared
        if rotation.isRotating || rotation.suppressReflowAnimation { return nil }
        return TrailhoundMotion.layoutReflow(reduceMotion: reduceMotion)
    }

    private var showsRecordingBook: Bool {
        let session = recordingService.state.isActiveSession || showLiveFollowMap
        guard session else { return false }
        return layout.pinsRecordingCardToFold || layout.splitsRecording
    }

    /// Card and list stay mounted and slide. A live map or an open trip detail keeps
    /// the dedicated pane, which owns safe-area and navigation chrome.
    private var recordingBookSlidesWithRotation: Bool {
        let recording = recordingService.state.isActiveSession && endCredits == nil
        if showLiveFollowMap && recording { return false }
        if layout.splitsRecording, paneTripID != nil, paneTrip != nil { return false }
        return true
    }

    private var showsStandaloneTripDetail: Bool {
        // Keep the open trip through the turn. A portrait pass can resolve as a
        // phone for a moment; dropping the pane then is what sends the user back to the list.
        paneTrip != nil
            && !recordingService.state.isActiveSession
            && !showLiveFollowMap
    }

    private var paneTrip: Trip? {
        guard let paneTripID else { return nil }
        return completedTrips.first { $0.id == paneTripID }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            tripListRotationHooks(scrollProxy: scrollProxy)
        }
        .toolbar(hidesTabBarForLiveMap ? .hidden : .automatic, for: .tabBar)
        .onChange(of: hidesTabBarForLiveMap, initial: true) { _, hides in
            TrailhoundTabBarVisibility.shared.hiddenByScreen = hides
        }
        .onDisappear {
            TrailhoundTabBarVisibility.shared.hiddenByScreen = false
        }
    }

    /// The phone book is short and the floating tab bar sits across the fold, on top of the
    /// live map's recording card. Like Apple Maps, the map hides it; closing the map brings it back.
    private var hidesTabBarForLiveMap: Bool {
        layout.isPhoneBook && showLiveFollowMap && recordingService.state.isActiveSession && endCredits == nil
    }

    private func tripListRoot(scrollProxy: ScrollViewProxy) -> some View {
        Group {
            if showsStandaloneTripDetail, let trip = paneTrip {
                TripDetailView(trip: trip)
                    .id(trip.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                paneTripID = nil
                            } label: {
                                GlassToolbarSymbol(systemName: "chevron.backward")
                            }
                            .accessibilityLabel(L10n.cancel)
                        }
                    }
            } else if showsRecordingBook {
                recordingBook(scrollProxy: scrollProxy)
            } else if layout.splitsTrips, paneTripID != nil {
                tripsSplit(scrollProxy: scrollProxy)
            } else if usesLibraryOrientation {
                libraryOrientation(scrollProxy: scrollProxy)
            } else if showsLibrarySplit {
                librarySplit(scrollProxy: scrollProxy)
            } else {
                tripList(scrollProxy: scrollProxy)
            }
        }
        .animation(layoutChangeAnimation, value: layout.layoutClass)
        .animation(layoutChangeAnimation, value: layout.isLandscape)
        .navigationDestination(for: TravelJournal.self) { journal in
            TravelJournalDetailView(journal: journal)
        }
        .navigationDestination(for: Trip.self) { trip in
            TripDetailView(trip: trip)
                .id(trip.id)
        }
    }

    @ViewBuilder
    private func recordingBook(scrollProxy: ScrollViewProxy) -> some View {
        if recordingBookSlidesWithRotation {
            recordingOrientationBook(scrollProxy: scrollProxy)
        } else if layout.pinsRecordingCardToFold {
            recordingFoldStack(scrollProxy: scrollProxy)
        } else {
            tripsSplit(scrollProxy: scrollProxy)
        }
    }

    @ToolbarContentBuilder
    private func tripListBar(scrollProxy: ScrollViewProxy) -> some ToolbarContent {
        if !showsStandaloneTripDetail, isMergeMode {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    presentMergeConfirm()
                } label: {
                    GlassToolbarTitle(title: L10n.actionMerge)
                }
                .disabled(completedMergeSelectionCount < 2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                GlassToolbarCluster(clustered: true) {
                    if !duoCapsuleOwnsBell {
                        TrailhoundNotificationBell()
                    }
                    Button {
                        isMergeMode = false
                        mergeSelection.removeAll()
                    } label: {
                        GlassToolbarTitle(title: L10n.cancel)
                    }
                }
            }
        } else if !showsStandaloneTripDetail {
            if recordingService.state.isActiveSession, showsActiveRecordingNavAffordance {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        TrailhoundHaptics.selection()
                        scrollToActiveTrip(scrollProxy: scrollProxy)
                    } label: {
                        TripListActiveRecordingNavIcon(
                            isPaused: recordingService.state == .paused,
                            reduceMotion: reduceMotion
                        )
                        .glassCircleChrome()
                    }
                    .buttonStyle(.glassPlainHit)
                    .accessibilityLabel(L10n.string("trips.active_recording.show"))
                    .accessibilityIdentifier("trips.active_recording.nav")
                }
                .hideSharedToolbarBackgroundIfAvailable()
            }
            if showsLibrarySplit, !splitCapsuleOwnsTrailing {
                ToolbarItem(placement: .topBarTrailing) {
                    GlassToolbarCluster(clustered: true) {
                        TrailhoundNotificationBell()
                        Button {
                            journalEditor = .create()
                        } label: {
                            GlassToolbarSymbol(systemName: "plus")
                        }
                        .accessibilityLabel(L10n.journalNew)
                        .accessibilityIdentifier(SideColumnChromeID.newJournal)
                        Button {
                            isMergeMode = true
                        } label: {
                            GlassToolbarSymbol(systemName: "arrow.triangle.merge")
                        }
                        .accessibilityLabel(L10n.actionMerge)
                        .accessibilityIdentifier(SideColumnChromeID.merge)
                    }
                }
            }
        }
    }

    private func tripListChrome<Content: View>(
        scrollProxy: ScrollViewProxy,
        content: Content
    ) -> some View {
        content
            .onChange(of: tabSelection.pendingTripID) { _, _ in
                consumeTripDeepLink()
            }
            .onChange(of: tabSelection.tripsPath.count) { _, count in
                DevLog.shared.log(.tripDetail, "tripsPath count=\(count)")
            }
            .toolbar { tripListBar(scrollProxy: scrollProxy) }
            .sheet(item: $journalEditor) { draft in
                TravelJournalEditorSheet(draft: draft)
            }
            .trailhoundShellToolbar(
                pageOwnsLeading: shellPageOwnsLeading,
                pageOwnsTrailing: pageOwnsTrailingBell
            )
            .onAppear {
                syncWideBookStatusActions()
                recordingBookFolds = layout.pinsRecordingCardToFold
                recordingBookLiveLeads = layout.recordingCardLeads
            }
    }

    private func tripListFoldHooks<Content: View>(content: Content) -> some View {
        content
            .onChange(of: layout.pinsRecordingCardToFold) { _, folds in
                guard !TrailhoundInterfaceRotation.shared.isRotating else { return }
                recordingBookFolds = folds
            }
            .onChange(of: layout.recordingCardLeads) { _, leads in
                guard !TrailhoundInterfaceRotation.shared.isRotating else { return }
                recordingBookLiveLeads = leads
            }
            .onChange(of: TrailhoundInterfaceRotation.shared.isRotating) { _, rotating in
                guard !rotating else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    recordingBookFolds = layout.pinsRecordingCardToFold
                    recordingBookLiveLeads = layout.recordingCardLeads
                }
            }
            .onChange(of: isMergeMode) { _, _ in syncWideBookStatusActions() }
            .onChange(of: listMode) { _, _ in syncWideBookStatusActions() }    }

    private func tripListSceneHooks<Content: View>(content: Content) -> some View {
        content
            .onChange(of: showsLibrarySplit) { _, isSplit in
                syncWideBookStatusActions()
                if isSplit {
                    scheduleTravelSuggestionRefresh()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, didInitialLoad else { return }
                guard !DeleteConfirmPresenter.shared.isProgressVisible else { return }
                reloadTrips()
                reloadJournals()
                refreshOrphans()
                refreshListAggregates()
                notificationStore.reload()
            }
            .onChange(of: tabSelection.wideBookTrailingToken) { _, _ in
                performWideBookTrailing()
            }
            .onChange(of: tabSelection.wideBookJournalToken) { _, _ in
                journalEditor = .create()
            }
            .onChange(of: tabSelection.wideBookMergeToken) { _, _ in
                isMergeMode = true
            }
    }

    private func tripListRotationHooks(scrollProxy: ScrollViewProxy) -> some View {
        tripListSceneHooks(
            content: tripListFoldHooks(
                content: tripListChrome(
                    scrollProxy: scrollProxy,
                    content: tripListRoot(scrollProxy: scrollProxy)
                )
            )
        )
        .onChange(of: layout.isLandscape) { _, _ in
            beginRecordingViewportSettle()
            syncWideBookStatusActions()
        }
        .onChange(of: layout.layoutClass) { _, _ in
            beginRecordingViewportSettle()
            syncWideBookStatusActions()
        }
        .toolbar(hidesWideBookNavigationBar ? .hidden : .automatic, for: .navigationBar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingBookGutter: CGFloat {
        if layout.layoutClass == .pad, layout.isLandscape {
            return GlassTokens.padLandscapeGap
        }
        return GlassTokens.hingeGutter
    }

    /// Same recording card and list through portrait and landscape. Their frames
    /// follow the window, so the turn does not crossfade two copies.
    private func recordingOrientationBook(scrollProxy: ScrollViewProxy) -> some View {
        let rotating = TrailhoundInterfaceRotation.shared.isRotating
        let folds = rotating ? recordingBookFolds : layout.pinsRecordingCardToFold
        let liveLeads = rotating
            ? (recordingBookFolds || recordingBookLiveLeads)
            : (layout.pinsRecordingCardToFold || layout.recordingCardLeads)
        return RecordingOrientationStage(
            gutter: recordingBookGutter,
            liveLeads: liveLeads
        ) {
            recordingOrientationLivePane(folds: folds)
        } list: {
            // The stage paints one atmosphere for the window. A second one clipped to the
            // list pane reads as a lighter box beside the card in phone landscape.
            tripList(scrollProxy: scrollProxy, paintsAtmosphere: false)
        }
    }

    private func recordingOrientationLivePane(folds: Bool) -> some View {
        ActiveTripView(
            morphNamespace: tripMorphNamespace,
            morphID: recordingService.activeTripID ?? UUID(),
            playEntranceReveal: coldOpenArmed && coldOpenTripID == recordingService.activeTripID,
            onEntranceFinished: finishColdOpen,
            onStop: { anchor in beginEndCredits(cardAnchor: anchor) },
            onOpenLiveFollow: { anchor in
                liveFollowCardAnchor = anchor
                Task { @MainActor in
                    await prepareLiveFollowVehiclePhoto()
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showLiveFollowMap = true
                    }
                }
            },
            isRecordingCardVisible: true
        )
        .padding(.horizontal, folds ? GlassTokens.recordingFoldExtraInset(contentWidth: layout.size.width) : 0)
        .frame(maxWidth: folds ? .infinity : GlassTokens.paneCardMaxWidth)
        .padding(folds ? 0 : (layout.isPhoneBook ? 8 : 16))
        .modifier(PhoneBookRecordingClearance(active: layout.isPhoneBook))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func tripsSplit(scrollProxy: ScrollViewProxy) -> some View {
        let recording = recordingService.state.isActiveSession && endCredits == nil
        let live = showLiveFollowMap && recording
        let openTrip = recording ? paneTrip : nil
        // The open trip takes the list's pane, so the map or card keeps its own.
        if layout.recordingCardLeads {
            TrailhoundPaneSplit(leadingFillsVertically: live) {
                if live {
                    liveFollowMap
                } else {
                    recordingPane
                }
            } focus: {
                if let openTrip {
                    recordingPaneTripDetail(openTrip)
                } else {
                    tripList(scrollProxy: scrollProxy)
                }
            }
        } else {
            TrailhoundPaneSplit(focusFillsVertically: live) {
                if let openTrip {
                    recordingPaneTripDetail(openTrip)
                } else {
                    tripList(scrollProxy: scrollProxy)
                }
            } focus: {
                if live {
                    liveFollowMap
                } else {
                    recordingPane
                }
            }
        }
    }

    /// The navigation bar is hidden over the live map and owned by the shell beside the
    /// card, so Back rides on the pane's own route map.
    private func recordingPaneTripDetail(_ trip: Trip) -> some View {
        TripDetailView(trip: trip)
            .id(trip.id)
            .environment(\.tripDetailRegion, .stacked)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recording.paneTrip")
            .overlay(alignment: .topLeading) {
                GlassToolbarBackButton {
                    paneTripID = nil
                }
                .accessibilityIdentifier("recording.paneTrip.back")
                .padding(12)
            }
    }

    private func recordingFoldStack(scrollProxy: ScrollViewProxy) -> some View {
        let recording = recordingService.state.isActiveSession && endCredits == nil
        let live = showLiveFollowMap && recording
        return TrailhoundFoldStack(
            gutter: live ? 0 : GlassTokens.hingeGutter,
            topFillsToEdge: live
        ) {
            if live {
                liveFollowMap
            } else {
                foldRecordingCard(expands: true)
            }
        } bottom: {
            tripList(scrollProxy: scrollProxy, paintsAtmosphere: false)
        }
    }

    /// Same recording card as the phone list, centered in the top half of the upright fold.
    private func foldRecordingCard(expands: Bool) -> some View {
        ActiveTripView(
            morphNamespace: tripMorphNamespace,
            morphID: recordingService.activeTripID ?? UUID(),
            playEntranceReveal: coldOpenArmed && coldOpenTripID == recordingService.activeTripID,
            onEntranceFinished: finishColdOpen,
            onStop: { anchor in beginEndCredits(cardAnchor: anchor) },
            onOpenLiveFollow: { anchor in
                liveFollowCardAnchor = anchor
                Task { @MainActor in
                    await prepareLiveFollowVehiclePhoto()
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showLiveFollowMap = true
                    }
                }
            },
            isRecordingCardVisible: true
        )
        .padding(.horizontal, GlassTokens.recordingFoldExtraInset(contentWidth: layout.size.width))
        .frame(
            maxWidth: .infinity,
            maxHeight: expands ? .infinity : nil,
            alignment: expands ? .center : .top
        )
    }

    /// Same trips list and travels list through upright and landscape. The travels list
    /// fades, then the trips list changes width. A scale would read as a cheap shrink.
    private func libraryOrientation(scrollProxy: ScrollViewProxy) -> some View {
        let gap = layout.layoutClass == .pad ? GlassTokens.padLandscapeGap : GlassTokens.hingeGutter
        let stage = LibraryOrientationStage(gutter: gap, reduceMotion: reduceMotion) { split in
            // Keep the list the turn started with. Swapping it while the window is
            // turning cancels the orientation change.
            let pinsTrips = TrailhoundInterfaceRotation.shared.isRotating
                ? layout.splitsIdleLibrary
                : LibraryAxisPlacement.pinsTripsLibrary(split)
            tripList(
                scrollProxy: scrollProxy,
                library: pinsTrips ? .trips : nil,
                paintsAtmosphere: false
            )
        } travels: {
            travelsPane
        }
        return stage
            .animation(nil, value: layout.layoutClass)
            .animation(nil, value: layout.isLandscape)
    }

    private func librarySplit(scrollProxy: ScrollViewProxy) -> some View {
        // One atmosphere for the whole book. Each list painting its own glow
        // piles a white veil on the fold.
        TrailhoundPaneSplit {
            tripList(scrollProxy: scrollProxy, library: .trips, paintsAtmosphere: false)
        } focus: {
            travelsPane
        }
    }

    private var travelsPane: some View {
        List {
            Section {
                TripListFiltersBar(
                    searchText: $journalSearchText,
                    searchFocused: $isJournalSearchFocused,
                    selectedDateSection: $selectedDateSection,
                    selectedCategoryID: $selectedCategoryID,
                    selectedVehicleFilter: $selectedVehicleFilter,
                    selectedPlaceID: $selectedPlaceID,
                    listMode: .constant(.travels),
                    showsModePicker: false
                )
            }
            .glassListRow()
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: GlassTokens.listContentHorizontalInset,
                    bottom: 8,
                    trailing: GlassTokens.listContentHorizontalInset
                )
            )
            .listSectionSpacing(6)

            journalListContent(searchText: journalDebouncedSearchText, searchBusy: false)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap(focus: $isJournalSearchFocused)
        .fieldKeyboardAccessory(
            title: L10n.journalSearchPlaceholder,
            focusID: isJournalSearchFocused ? AnyHashable(true) : nil,
            onDone: {
                isJournalSearchFocused = false
                KeyboardDismiss.dismiss()
            }
        )
        .glassListChrome(showsAtmosphere: false)
        .listSectionSpacing(6)
        .portraitPaneListWidth(layout.splitsTrips || layout.isWideBook)
        .refreshable {
            await refreshFromPull()
        }
        .tint(shellPalette.tintColor(for: colorScheme).opacity(0.42))
        .onChange(of: journalSearchText) { _, newValue in
            scheduleJournalSearchApply(newValue)
        }
        .onChange(of: journalDebouncedSearchText) { _, _ in
            guard showsLibrarySplit else { return }
            journalPageLimit = TravelJournalPage.pageSize
            reloadJournals()
        }
    }

    private var recordingPane: some View {
        ActiveTripView(
            morphNamespace: tripMorphNamespace,
            morphID: recordingService.activeTripID ?? UUID(),
            playEntranceReveal: coldOpenArmed && coldOpenTripID == recordingService.activeTripID,
            onEntranceFinished: finishColdOpen,
            onStop: { anchor in beginEndCredits(cardAnchor: anchor) },
            onOpenLiveFollow: { anchor in
                liveFollowCardAnchor = anchor
                Task { @MainActor in
                    await prepareLiveFollowVehiclePhoto()
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showLiveFollowMap = true
                    }
                }
            },
            isRecordingCardVisible: true
        )
        .trailhoundPaneCard()
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var liveFollowMap: some View {
        LiveFollowMapView(
            vehiclePhoto: liveFollowVehiclePhoto,
            vehicleSystemImage: "car.fill",
            cardAnchor: liveFollowCardAnchor,
            fillsPane: true,
            pinsAttributionToBottomCorner: layout.pinsRecordingCardToFold,
            isSceneVisible: tabSelection.selectedTab == .trips,
            onClose: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showLiveFollowMap = false
                }
            },
            onStop: { anchor in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showLiveFollowMap = false
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(280))
                    beginEndCredits(cardAnchor: anchor)
                }
            }
        )
        .environment(recordingService)
        .environment(AppServices.runtime.locationService)
        .environment(NetworkMonitor.shared)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncWideBookStatusActions() {
        tabSelection.wideBookTrailingVisible = !isMergeMode && !showsLibrarySplit
        tabSelection.wideBookShowsPlusAndMerge = showsLibrarySplit && !isMergeMode
        tabSelection.wideBookTrailingSymbol = listMode == .travels ? "plus" : "arrow.triangle.merge"
        tabSelection.wideBookTrailingLabel = listMode == .travels ? L10n.journalNew : L10n.actionMerge
    }

    private func performWideBookTrailing() {
        if listMode == .travels {
            journalEditor = .create()
        } else {
            isMergeMode = true
        }
    }

    private func tripList(
        scrollProxy: ScrollViewProxy,
        library: TripsTabListMode? = nil,
        paintsAtmosphere: Bool = true
    ) -> some View {
        // Computed once per body pass. `completedTrips` used to be re-evaluated inside every
        // row, which made rendering the list quadratic in trip count.
        let mode = library ?? listMode
        let visibleTrips = completedTrips
        let groups = tripGroups
        let firstTripID = visibleTrips.first?.id
        let hasAnyTrips = self.hasAnyTrips
        let weekSummary = hasAnyTrips ? weekSummaryText : ""

        return tripListCover(
            content: tripListCredits(
                content: tripListRecordingHooks(
                    scrollProxy: scrollProxy,
                    content: tripListReloadHooks(
                        library: library,
                        content: tripListScrollChrome(
                            mode: mode,
                            paintsAtmosphere: paintsAtmosphere,
                            content: tripListRows(
                                library: library,
                                mode: mode,
                                visibleTrips: visibleTrips,
                                groups: groups,
                                firstTripID: firstTripID,
                                hasAnyTrips: hasAnyTrips,
                                weekSummary: weekSummary
                            )
                        )
                    )
                )
            )
        )
    }

    private func tripListRows(
        library: TripsTabListMode?,
        mode: TripsTabListMode,
        visibleTrips: [Trip],
        groups: [(section: TripDateSection, trips: [Trip])],
        firstTripID: UUID?,
        hasAnyTrips: Bool,
        weekSummary: String
    ) -> some View {
        List {
            Section {
                LocationPermissionBanner()
                    .id(TripListScrollTarget.top)
                    .background {
                        TripListScrollToTopInstaller(request: scrollToTopRequest)
                    }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSpacing(6)

            if showsVehicleSetupPrompt {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tripListSetupVehicleTitle)
                            .font(.headline)
                        Text(L10n.tripListSetupVehicleMessage)
                            .font(.caption)
                            .glassSecondaryInk()
                        Button(L10n.string("onboarding.shortcuts.link")) {
                            tabSelection.openPairing()
                        }
                        .trailhoundProminentButton()

                        Button(L10n.vehiclePairingSkip) {
                            settings.skipCarSetup()
                        }
                        .font(.caption)
                        .glassSecondaryInk()
                    }
                    .padding(.vertical, 4)
                }
                .glassListRow()
                .listSectionSpacing(6)
            }

            if let careItem = careSummary.topBannerItem {
                Section {
                    VehicleCareBannerView(
                        item: careItem,
                        onTap: {
                            tabSelection.openVehicleCare(vehicleID: careItem.vehicleID)
                        },
                        onDismiss: {
                            careSummary.dismissBanner(scheduleID: careItem.scheduleID)
                        }
                    )
                }
                .vehicleCareBannerRow(state: careItem.state)
                .listSectionSpacing(6)
            }

            if let orphan = visibleOrphan {
                Section {
                    OrphanRecoveryBanner(
                        onResume: {
                            if TripRecoveryService.resumeOrphan(orphan.trip, recordingService: recordingService) {
                                refreshOrphans()
                            }
                        },
                        onSave: {
                            if TripRecoveryService.finalizeOrphan(orphan.trip, in: modelContext, saveTrip: true) {
                                ToastPresenter.shared.show(.orphanSaved)
                                refreshOrphans()
                            }
                        },
                        onDelete: {
                            DeleteConfirmPresenter.shared.confirm(.generic) {
                                if TripRecoveryService.deleteOrphan(orphan.trip, in: modelContext) {
                                    ToastPresenter.shared.show(.deleted)
                                    refreshOrphans()
                                }
                            }
                        }
                    )
                }
                .glassListRow()
                .listSectionSpacing(6)
            }

            if recordingService.state.isActiveSession,
               endCredits == nil,
               let activeTripID = recordingService.activeTripID,
               !layout.hidesRecordingCardFromList {
                Section {
                    ActiveTripView(
                        morphNamespace: tripMorphNamespace,
                        morphID: activeTripID,
                        playEntranceReveal: coldOpenArmed && coldOpenTripID == activeTripID,
                        onEntranceFinished: finishColdOpen,
                        onStop: { anchor in beginEndCredits(cardAnchor: anchor) },
                        onOpenLiveFollow: { anchor in
                            liveFollowCardAnchor = anchor
                            Task { @MainActor in
                                await prepareLiveFollowVehiclePhoto()
                                // Skip the system cover slide — LiveFollowMapView owns the expand.
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    showLiveFollowMap = true
                                }
                            }
                        },
                        isRecordingCardVisible: tabSelection.selectedTab == .trips
                            && isRecordingCardInViewport
                            && !showLiveFollowMap
                    )
                    .id(activeTripID)
                    .background {
                        RecordingCardVisibilityProbe { onScreen in
                            noteRecordingCardOnScreen(onScreen)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listSectionSpacing(6)
            }

            if library == .trips || hasAnyTrips || hasAnyJournals {
                Section {
                    TripListFiltersBar(
                        searchText: $searchText,
                        searchFocused: $isSearchFocused,
                        selectedDateSection: $selectedDateSection,
                        selectedCategoryID: $selectedCategoryID,
                        selectedVehicleFilter: $selectedVehicleFilter,
                        selectedPlaceID: $selectedPlaceID,
                        listMode: Binding(
                            get: { mode },
                            set: { newValue in
                                if library == nil { listMode = newValue }
                            }
                        ),
                        showsModePicker: library == nil,
                        isSearchBusy: isSearchBusy,
                        vehicles: vehicles,
                        places: places,
                        weekSummaryText: weekSummary,
                        weekSummaryRefreshToken: weekSummaryRefreshToken,
                        isWeekSummaryRefreshing: isWeekSummaryRefreshing
                    )
                    .background {
                        // Only the stop-credits slide needs this, and a `.global` frame
                        // changes every scroll frame — so don't install it otherwise.
                        if endCredits != nil {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: CreditsListLandingYKey.self,
                                    value: geo.frame(in: .global).maxY + 6
                                )
                            }
                        }
                    }
                }
                .glassListRow()
                .listRowInsets(
                    EdgeInsets(
                        top: 8,
                        leading: GlassTokens.listContentHorizontalInset,
                        bottom: 8,
                        trailing: GlassTokens.listContentHorizontalInset
                    )
                )
                .listSectionSpacing(6)
            }

            if mode == .travels {
                journalListContent(searchText: debouncedSearchText, searchBusy: isSearchBusy)
            } else if visibleTrips.isEmpty {
                let showFilteredEmpty = hasActiveFilters && hasAnyTrips && !isSearchBusy
                let showDefaultEmpty = !hasAnyTrips
                    && !recordingService.state.isActiveSession
                    && endCredits == nil
                    && coldOpenTripID == nil
                    && !isSearchBusy
                if showFilteredEmpty || showDefaultEmpty {
                    GlassEmptyState(
                        title: hasActiveFilters ? L10n.tripsEmptyFilteredTitle : L10n.tripsEmptyTitle,
                        systemImage: "car",
                        message: hasActiveFilters
                            ? L10n.tripsEmptyFilteredMessage
                            : L10n.tripsEmptyMessage,
                        bounceTrigger: hasActiveFilters
                    )
                    .glassListRow()
                    .transition(TrailhoundMotion.fadeScaleTransition(reduceMotion: reduceMotion))
                }
            } else {
                ForEach(groups, id: \.section) { group in
                    Section(group.section.title) {
                        ForEach(Array(group.trips.enumerated()), id: \.element.id) { index, trip in
                            // Keep the new trip hidden until the blue bar finishes sliding onto it.
                            if endCredits?.tripID != trip.id {
                                tripRow(for: trip, isFirst: trip.id == firstTripID)
                                    .glassRow(position: GlassRowPosition.index(index, in: group.trips.count))
                            }
                        }
                    }
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: visibleTrips.count)
            }

            if hasMorePages && mode != .travels {
                // Sits below the last section rather than on the last row, so a page whose rows
                // were all filtered out in memory still pulls the next one instead of dead-ending.
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityLabel(L10n.string("trips.loading_more"))
                        .onAppear(perform: loadNextPage)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func tripListScrollChrome<Content: View>(
        mode: TripsTabListMode,
        paintsAtmosphere: Bool,
        content: Content
    ) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap(focus: $isSearchFocused)
            .fieldKeyboardAccessory(
                title: mode == .travels ? L10n.journalSearchPlaceholder : L10n.searchTrips,
                focusID: isSearchFocused ? AnyHashable(true) : nil,
                onDone: {
                    isSearchFocused = false
                    KeyboardDismiss.dismiss()
                }
            )
            .glassListChrome(showsAtmosphere: paintsAtmosphere)
            // Tighter than the global glass default so banner/search cards sit like date→trip gaps.
            .listSectionSpacing(6)
            .portraitPaneListWidth(layout.splitsTrips || layout.isWideBook)
            .refreshable {
                await refreshFromPull()
            }
            .tint(shellPalette.tintColor(for: colorScheme).opacity(0.42))
            .onChange(of: searchText) { _, newValue in
                scheduleSearchApply(newValue)
            }
            .onPreferenceChange(CreditsListLandingYKey.self) { newY in
                guard endCredits != nil else { return }
                listLandingMinY = newY
            }
            .navigationTitle(phoneBookRecordingHidesTitle ? "" : "Trailhound")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                PerformanceSignposts.measure("TripsTabAppear") {
                    handleTripListAppear()
                }
            }
    }

    private func tripListReloadHooks<Content: View>(
        library: TripsTabListMode?,
        content: Content
    ) -> some View {
        content
            .onStoreSave {
                // Merge saves from a background actor; rebuilding the list under that lock
                // is the hitch. Progress overlay lives on the root host — do not read it
                // into this view's body.
                if DeleteConfirmPresenter.shared.isProgressVisible {
                    aggregatesRefreshTask?.cancel()
                    aggregatesRefreshTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { return }
                        refreshListAggregates()
                    }
                    return
                }
                // Row identity must refresh before the next body pass or a deleted model crashes.
                reloadTrips()
                reloadJournals()
                careSummary.refresh(in: modelContext)
                // Week summary is display-only — coalesce rapid saves (merge + post-process).
                aggregatesRefreshTask?.cancel()
                aggregatesRefreshTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    refreshListAggregates()
                }
            }
            .onChange(of: pageFilters) { _, _ in
                resetPagingAndReload()
            }
            .onChange(of: listMode) { _, _ in
                searchDebounceTask?.cancel()
                isSearchApplying = false
                searchText = ""
                debouncedSearchText = ""
                reloadJournals()
            }
            .onChange(of: debouncedSearchText) { _, _ in
                if library == nil, listMode == .travels {
                    journalPageLimit = TravelJournalPage.pageSize
                    reloadJournals()
                }
            }
    }

    private func tripListRecordingHooks<Content: View>(
        scrollProxy: ScrollViewProxy,
        content: Content
    ) -> some View {
        content
            .onChange(of: recordingService.state) { _, newState in
                if !newState.isActiveSession {
                    refreshOrphans()
                    coldOpenArmed = false
                    coldOpenTripID = nil
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showLiveFollowMap = false
                    }
                }
            }
            .onChange(of: recordingService.state.isActiveSession) { wasActive, isActive in
                if isActive {
                    // New recording must never be blocked by a stuck credits card.
                    if endCredits != nil {
                        endCredits = nil
                        ToastPresenter.shared.flushRecordingCreditsQueue()
                    }
                } else {
                    resetRecordingCardViewport()
                }
                if !wasActive, isActive, endCredits == nil {
                    resetRecordingCardViewport()
                    beginColdOpenIfNeeded()
                    requestScrollToTop()
                }
                // Vehicle auto-stop (and other external stops) still get a light morph —
                // full credits play only for manual Stop.
                if wasActive, !isActive, endCredits == nil {
                    ToastPresenter.shared.flushRecordingCreditsQueue()
                }
                if wasActive, !isActive, endCredits == nil, morphingTripID == nil,
                   let newest = newestCompletedTrip(),
                   let endedAt = newest.endedAt,
                   Date().timeIntervalSince(endedAt) < 2.5 {
                    morphingTripID = newest.id
                    clearMorphingTripSoon(delayMilliseconds: reduceMotion ? 50 : 280)
                }
            }
            .onChange(of: scrollToTopToken) { _, _ in
                performScrollToTop(scrollProxy: scrollProxy)
            }
            .onChange(of: tabSelection.scrollToRecordingToken) { _, _ in
                if recordingService.state.isActiveSession {
                    scrollToActiveTrip(scrollProxy: scrollProxy)
                } else {
                    performScrollToTop(scrollProxy: scrollProxy)
                }
            }
            .animation(reduceMotion ? nil : TrailhoundMotion.recordingMorph, value: morphingTripID)
    }

    private func tripListCredits<Content: View>(content: Content) -> some View {
        content
            .overlay {
                if let endCredits {
                    GeometryReader { geo in
                        let containerFrame = geo.frame(in: .global)
                        let anchor = pinnedCreditsCardAnchor
                        let startY = anchor.minY > 0
                            ? anchor.minY - containerFrame.minY
                            : 12
                        let xOffset = anchor.minX > 0
                            ? anchor.minX - containerFrame.minX
                            : 0

                        Group {
                            if anchor.width > 0 {
                                RecordingEndCreditsView(
                                    snapshot: endCredits,
                                    reduceMotion: reduceMotion,
                                    onFinished: startCreditsSlideIntoList
                                )
                                .frame(width: anchor.width)
                            } else {
                                RecordingEndCreditsView(
                                    snapshot: endCredits,
                                    reduceMotion: reduceMotion,
                                    onFinished: startCreditsSlideIntoList
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal)
                            }
                        }
                        .id(endCredits.sessionID)
                        .offset(x: xOffset, y: startY + creditsSlideY)
                    }
                    .allowsHitTesting(false)
                    .zIndex(50)
                }
            }
    }

    private func tripListCover<Content: View>(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: liveMapCoverPresented) {
                LiveFollowMapView(
                    vehiclePhoto: liveFollowVehiclePhoto,
                    vehicleSystemImage: "car.fill",
                    cardAnchor: liveFollowCardAnchor,
                    isSceneVisible: tabSelection.selectedTab == .trips,
                    onClose: {
                        // Cover presentation itself stays silent; reverse morph already finished.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            showLiveFollowMap = false
                        }
                    },
                    onStop: { anchor in
                        // Instant dismiss — no reverse morph; end credits play on the list.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            showLiveFollowMap = false
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            beginEndCredits(cardAnchor: anchor)
                        }
                    }
                )
                .presentationBackground(.clear)
                .transaction { transaction in
                    if !transaction[LiveFollowSheetTransition.self] {
                        transaction.disablesAnimations = true
                    }
                }
                .environment(recordingService)
                .environment(AppServices.runtime.locationService)
                .environment(NetworkMonitor.shared)
            }
    }


    @MainActor
    private func prepareLiveFollowVehiclePhoto() async {
        let vehicleID = recordingService.activeRecordingVehicleID(from: vehicles)
        let fileName = vehicles.first(where: { $0.id == vehicleID })?.photoFileName
        guard let fileName, !fileName.isEmpty else {
            liveFollowVehiclePhoto = nil
            return
        }
        // Same asset as the recording card — no backdrop punch (that eats white vehicles).
        if let synced = VehiclePhotoStore.shared.imageSync(fileName: fileName) {
            liveFollowVehiclePhoto = synced
            return
        }
        if let loaded = await VehiclePhotoStore.shared.image(fileName: fileName) {
            liveFollowVehiclePhoto = loaded
        } else {
            liveFollowVehiclePhoto = nil
        }
    }

    private func tripRowIdentifier(for trip: Trip, isFirst: Bool) -> String {
        let base = isFirst ? "trips.row.first" : "trips.row.\(trip.id.uuidString)"
        return trip.hasPendingCategorySuggestion ? "\(base).suggested" : base
    }

    private func tripRowLabel(
        trip: Trip,
        vehicle: VehicleProfile?,
        isMorphing: Bool,
        rowID: String
    ) -> some View {
        HStack(spacing: 8) {
            TripRowView(
                trip: trip,
                places: places,
                categories: categories,
                privacyRadius: settings.privacyRadiusMeters,
                vehicle: vehicle,
                morphNamespace: tripMorphNamespace,
                morphID: morphingTripID,
                emphasizeLanding: isMorphing,
                rowAccessibilityIdentifier: rowID
            )
            .contentShape(Rectangle())
            if !isMergeMode {
                GlassDisclosureChevron()
            }
        }
    }

    private var tripRowOpensInPane: Bool {
        layout.opensTripInPane(
            whileRecording: recordingService.state.isActiveSession && endCredits == nil
        )
    }

    @ViewBuilder
    private func tripRow(for trip: Trip, isFirst: Bool) -> some View {
        let isMorphing = morphingTripID == trip.id
        let vehicle = trip.vehicleID.flatMap { id in vehicles.first(where: { $0.id == id }) }
        let rowID = tripRowIdentifier(for: trip, isFirst: isFirst)
        let isSelected = mergeSelection.contains(trip.id)
        HStack(spacing: 8) {
            if isMergeMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .accessibilityLabel(isSelected ? L10n.a11ySelected : L10n.a11yNotSelected)
            }
            Group {
                if tripRowOpensInPane, !isMergeMode {
                    Button {
                        paneTripID = trip.id
                    } label: {
                        tripRowLabel(
                            trip: trip,
                            vehicle: vehicle,
                            isMorphing: isMorphing,
                            rowID: rowID
                        )
                    }
                    .buttonStyle(.glassPlainHit)
                } else {
                    NavigationLink(value: trip) {
                        tripRowLabel(
                            trip: trip,
                            vehicle: vehicle,
                            isMorphing: isMorphing,
                            rowID: rowID
                        )
                    }
                    .glassHidesNavigationLinkIndicator()
                    .buttonStyle(.glassPlainHit)
                    .allowsHitTesting(!isMergeMode)
                }
            }
        }
        .overlay {
            if isMergeMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleMergeSelection(trip.id) }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: isMergeMode ? .combine : .contain)
        .accessibilityIdentifier(rowID)
        .accessibilityAddTraits(isMergeMode ? .isButton : [])
        .matchedGeometryEffectIfAvailable(
            id: isMorphing ? trip.id : nil,
            namespace: tripMorphNamespace,
            isSource: false
        )
        .transition(.opacity)
        .confirmingDeleteSwipe {
            deleteTrip(trip)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: trip.hasPendingCategorySuggestion) {
            if trip.hasPendingCategorySuggestion {
                Button {
                    acceptSuggestedCategory(trip)
                } label: {
                    Label(
                        suggestedCategoryAcceptLabel(for: trip),
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .tint(TrailhoundBrandColors.brandBottom)
                .accessibilityIdentifier("trips.row.acceptSuggestedCategory")
            }

            Button {
                addToMergeSelection(trip.id)
            } label: {
                Label(L10n.actionMerge, systemImage: "arrow.triangle.merge")
            }
            .tint(.indigo)

            Menu {
                ForEach(categories) { category in
                    Button {
                        updateCategory(trip, categoryID: category.id.uuidString)
                    } label: {
                        Label(category.name, systemImage: category.systemImage)
                    }
                }
            } label: {
                Label(L10n.actionCategory, systemImage: "tag")
            }
            .tint(.orange)
        }
    }

    private func beginColdOpenIfNeeded(onlyIfRecentlyStarted: Bool = false) {
        guard endCredits == nil,
              recordingService.state.isActiveSession,
              let tripID = recordingService.activeTripID
        else { return }

        // Already armed for this trip.
        if coldOpenTripID == tripID, coldOpenArmed { return }

        if onlyIfRecentlyStarted {
            guard let startedAt = recordingService.recordingStartedAt,
                  Date().timeIntervalSince(startedAt) < 2.0
            else { return }
        }

        coldOpenArmed = true
        coldOpenTripID = tripID
    }

    private func finishColdOpen() {
        coldOpenArmed = false
        // Only clear once this trip's entrance finished — don't block a newer start.
        if let active = recordingService.activeTripID, coldOpenTripID == active {
            coldOpenTripID = nil
        } else if coldOpenTripID != nil, recordingService.activeTripID == nil {
            coldOpenTripID = nil
        }
    }

    private func beginEndCredits(cardAnchor: RecordingCardAnchor) {
        guard let tripID = recordingService.activeTripID else {
            recordingService.stopManualRecording()
            return
        }

        resetTripFiltersToAll()

        let activeVehicleID = recordingService.activeRecordingVehicleID(from: vehicles)
        let serviceDue = activeVehicleID.flatMap { vehicleID in
            VehicleCareDueCalculator.urgentServiceDue(for: vehicleID, from: schedules)
        }

        let snapshot = RecordingEndCreditsSnapshot(
            sessionID: UUID(),
            tripID: tripID,
            durationText: DateFormatters.formatDuration(recordingService.elapsedTime),
            distanceText: DateFormatters.formatDistance(recordingService.currentDistanceMeters),
            coordinates: recordingService.liveBreadcrumbCoordinates,
            showsServiceDue: serviceDue != nil,
            serviceIsOverdue: serviceDue?.state.isOverdue ?? false
        )

        morphingTripID = tripID
        coldOpenArmed = false
        coldOpenTripID = nil
        creditsSlideY = 0
        isCreditsSliding = false
        pinnedCreditsCardAnchor = cardAnchor

        if reduceMotion {
            recordingService.stopManualRecording()
            endCredits = nil
            ToastPresenter.shared.flushRecordingCreditsQueue()
            clearMorphingTripSoon(delayMilliseconds: 50)
            return
        }

        endCredits = snapshot
        recordingService.stopManualRecording()

        let sessionID = snapshot.sessionID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if endCredits?.sessionID == sessionID, !isCreditsSliding {
                startCreditsSlideIntoList()
            }
        }
    }

    private func resetTripFiltersToAll() {
        guard selectedCategoryID != nil || selectedVehicleFilter != nil || selectedPlaceID != nil else { return }

        if reduceMotion {
            selectedCategoryID = nil
            selectedVehicleFilter = nil
            selectedPlaceID = nil
        } else {
            withAnimation(TrailhoundMotion.recordingMorph) {
                selectedCategoryID = nil
                selectedVehicleFilter = nil
                selectedPlaceID = nil
            }
        }
    }

    private func requestScrollToTop() {
        scrollToTopToken += 1
        scrollToTopRequest = TripListScrollToTopRequest(id: UUID())
    }

    private func performScrollToTop(scrollProxy: ScrollViewProxy) {
        let target = TripListScrollTarget.top
        let delays: [UInt64] = [0, 50, 140]
        Task { @MainActor in
            for (index, delay) in delays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                var transaction = Transaction()
                transaction.disablesAnimations = index < delays.count - 1 || reduceMotion
                withTransaction(transaction) {
                    scrollProxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    private func scrollToActiveTrip(scrollProxy: ScrollViewProxy) {
        guard let tripID = recordingService.activeTripID else {
            requestScrollToTop()
            return
        }

        let delays: [UInt64] = [0, 50, 140]
        Task { @MainActor in
            for (index, delay) in delays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                var transaction = Transaction()
                transaction.disablesAnimations = index < delays.count - 1 || reduceMotion
                withTransaction(transaction) {
                    scrollProxy.scrollTo(tripID, anchor: .top)
                }
            }
        }
    }

    private func startCreditsSlideIntoList() {
        guard endCredits != nil, !isCreditsSliding else { return }

        let startGlobal = pinnedCreditsCardAnchor.minY > 0
            ? pinnedCreditsCardAnchor.minY
            : 0
        let measured = listLandingMinY - startGlobal
        let distance = measured > 40 ? measured : 140

        isCreditsSliding = true

        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            creditsSlideY = distance
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(210))
            // Swap overlay → real row with no List insert morph / empty-cell fade.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                endCredits = nil
                creditsSlideY = 0
                isCreditsSliding = false
                pinnedCreditsCardAnchor = RecordingCardAnchor()
            }
            TrailhoundHaptics.selection()
            ToastPresenter.shared.flushRecordingCreditsQueue()
            clearMorphingTripSoon(delayMilliseconds: 220)
        }
    }

    private func clearMorphingTripSoon(delayMilliseconds: Int = 280) {
        let clearingID = morphingTripID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            if morphingTripID == clearingID {
                morphingTripID = nil
            }
        }
    }

    private func refreshOrphans() {
        let found = TripRecoveryService.findOrphanTrips(in: modelContext)
        orphanTrips = found
        TripRecoveryService.scheduleOrphanStaleNotifications(
            for: found,
            excludingTripID: recordingService.activeTripID
        )
    }

    private func toggleMergeSelection(_ id: UUID) {
        if mergeSelection.contains(id) {
            mergeSelection.remove(id)
        } else {
            mergeSelection.insert(id)
        }
    }

    private func addToMergeSelection(_ id: UUID) {
        isMergeMode = true
        mergeSelection.insert(id)
    }

    private func updateCategory(_ trip: Trip, categoryID: String) {
        TripCategorySuggestionService.applyUserCategory(categoryID, to: trip, in: modelContext)
        try? modelContext.save()
        ToastPresenter.shared.show(.categoryAccepted)
    }

    private func acceptSuggestedCategory(_ trip: Trip) {
        TripCategorySuggestionService.acceptPending(trip, in: modelContext)
        try? modelContext.save()
        ToastPresenter.shared.show(.categoryAccepted)
    }

    private func suggestedCategoryName(for trip: Trip) -> String? {
        guard let pendingID = trip.pendingSuggestedCategoryID else { return nil }
        return categories.first(where: { $0.id.uuidString == pendingID })?.name
    }

    private func suggestedCategoryAcceptLabel(for trip: Trip) -> String {
        if let name = suggestedCategoryName(for: trip) {
            return L10n.actionAcceptSuggestedCategory(name)
        }
        return L10n.actionAcceptCategory
    }

    private func deleteTrip(_ trip: Trip) {
        TripMapSnapshotCache.shared.remove(for: trip.id)
        TripRoutePathCache.shared.remove(for: trip.id)
        TravelJournalTotals.handleTripDeletion(trip, in: modelContext)
        let successor = TripFuelDependencyService.successor(of: trip, in: modelContext)
        TripRollupService.remove(trip, in: modelContext)
        VehicleOdometerService.tripRemoved(trip, in: modelContext)
        modelContext.delete(trip)
        if let successor {
            TripFuelDependencyService.recompute(successor, in: modelContext)
        }
        mergeSelection.remove(trip.id)
        try? modelContext.save()
        VehicleCareNotificationScheduler.evaluateKmReminders(for: trip.vehicleID, in: modelContext)
        ToastPresenter.shared.show(.deleted)
    }

    private func presentMergeConfirm() {
        let count = completedMergeSelectionCount
        guard count >= 2 else { return }
        DeleteConfirmPresenter.shared.present(
            title: L10n.tripsMergeTitle,
            message: L10n.tripsMergeMessage(count),
            confirmTitle: L10n.actionMerge,
            role: .prominent
        ) {
            DeleteConfirmPresenter.shared.showProgress(L10n.tripsMergeProgress)
            Task { await performMerge() }
        }
    }

    private func performMerge() async {
        let presenter = DeleteConfirmPresenter.shared
        if !presenter.isProgressVisible {
            presenter.showProgress(L10n.tripsMergeProgress)
        }
        defer { presenter.hideProgress() }

        // Let the root overlay paint before the worker takes the store lock.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))

        // Fetched by ID rather than filtered from the loaded pages: a selection made before
        // scrolling could otherwise include trips that are no longer resident.
        let selectedIDs = Array(mergeSelection)
        let container = modelContext.container
        do {
            let mergedUUID = try await TripMergeService.merge(
                tripIDs: selectedIDs,
                container: container
            )
            let legCount = selectedIDs.count
            isMergeMode = false
            mergeSelection.removeAll()
            reloadTrips()
            reloadJournals()
            careSummary.refresh(in: modelContext)
            ToastPresenter.shared.show(.tripsMerged)
            var mergedDescriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.id == mergedUUID }
            )
            mergedDescriptor.fetchLimit = 1
            if let merged = try? modelContext.fetch(mergedDescriptor).first {
                PersonalRecordToast.presentIfNeeded(
                    for: merged,
                    in: modelContext,
                    timing: .followingCurrent
                )
            }
            if !UITestSupport.isUnitTesting {
                TripNotificationService.notifyTripsMerged(
                    tripID: mergedUUID,
                    legCount: legCount
                )
            }
            Task { @MainActor in
                await TripPostProcessor.process(
                    tripUUID: mergedUUID,
                    container: container
                )
            }
        } catch let error as TripMergeError {
            modelContext.rollback()
            AppErrorPresenter.shared.presentInfo(error.localizedDescription)
        } catch {
            modelContext.rollback()
            AppErrorPresenter.shared.present(error.localizedDescription)
        }
    }
}

/// Incomplete-recording card. Light glass wells need chrome ink so Resume stays readable.
private struct OrphanRecoveryBanner: View {
    let onResume: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.orphanBannerTitle)
                .font(.headline)
                .foregroundStyle(ink)
            Text(L10n.orphanBannerMessage)
                .font(.caption)
                .foregroundStyle(messageColor)
            HStack {
                Button(action: onResume) {
                    Text(L10n.orphanResume)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(resumeFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.glassPlainHit)

                Button(L10n.orphanSave, action: onSave)
                    .buttonStyle(.bordered)
                    .tint(ink)

                Button(L10n.delete, role: .destructive, action: onDelete)
                    .destructiveTint()
            }
        }
    }

    private var ink: Color {
        GlassText.primary(for: colorScheme)
    }

    private var messageColor: Color {
        GlassText.secondary(for: colorScheme)
    }

    private var resumeFill: Color {
        colorScheme == .dark
            ? shellPalette.tintColor(for: .dark)
            : LightGlassPalette.selectedChipFill(for: shellPalette)
    }
}

/// List cells move under UIKit during a scroll. SwiftUI’s frame preference stays
/// stale until the scroll direction changes, so the steering button flickered.
/// This reads the card against the collection view’s visible rect, and keeps
/// sampling after a turn so a torn-down cell cannot leave the control stuck on.
private struct RecordingCardVisibilityProbe: UIViewRepresentable {
    var onChange: (Bool) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = onChange
    }

    final class Probe: UIView {
        var onChange: ((Bool) -> Void)?
        private var observation: NSKeyValueObservation?
        private var lastOnScreen: Bool?
        private var scheduled: DispatchWorkItem?
        private var poll: DispatchWorkItem?
        private var settleUntil: CFTimeInterval = 0
        private var lastBoundsSize: CGSize = .zero

        override func didMoveToWindow() {
            super.didMoveToWindow()
            beginSettle()
            attachScrollObservation()
            scheduleCheck()
            schedulePoll()
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil {
                poll?.cancel()
                poll = nil
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let size = bounds.size
            if lastBoundsSize.width > 1, lastBoundsSize.height > 1 {
                let flipped = abs(size.width - lastBoundsSize.height) < 8
                    && abs(size.height - lastBoundsSize.width) < 8
                let jumped = abs(size.width - lastBoundsSize.width) > 48
                    || abs(size.height - lastBoundsSize.height) > 48
                if flipped || jumped {
                    beginSettle()
                }
            }
            lastBoundsSize = size
            if observation == nil {
                attachScrollObservation()
            }
            scheduleCheck()
        }

        private func beginSettle() {
            settleUntil = CACurrentMediaTime() + 0.9
        }

        private func attachScrollObservation() {
            observation?.invalidate()
            observation = nil
            guard let scroll = enclosingScrollView() else { return }
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.scheduleCheck()
                }
            }
        }

        private func scheduleCheck() {
            scheduled?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.check()
            }
            scheduled = work
            DispatchQueue.main.async(execute: work)
        }

        /// An on-screen card must keep reporting. A rotation used to emit one false
        /// sample and then go quiet, so the steering control stayed up at the top.
        private func schedulePoll() {
            poll?.cancel()
            guard window != nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.window != nil else { return }
                self.check()
                self.schedulePoll()
            }
            poll = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        private func check() {
            guard window != nil, let scroll = enclosingScrollView() else { return }
            let frame = cardFrame(in: scroll)
            guard frame.width > 1, frame.height > 40 else { return }
            let overlap = frame.intersection(scroll.bounds).height
            let onScreen: Bool
            if lastOnScreen != nil {
                if overlap < 36 {
                    onScreen = false
                } else if overlap > 100 {
                    onScreen = true
                } else {
                    return
                }
            } else {
                onScreen = overlap > 72
            }
            if !onScreen, CACurrentMediaTime() < settleUntil {
                return
            }
            let changed = onScreen != lastOnScreen
            lastOnScreen = onScreen
            if onScreen || changed {
                onChange?(onScreen)
            }
        }

        private func cardFrame(in scroll: UIScrollView) -> CGRect {
            var view: UIView? = self
            while let current = view {
                if current is UICollectionViewCell || current is UITableViewCell {
                    return current.convert(current.bounds, to: scroll)
                }
                if current is UIScrollView { break }
                view = current.superview
            }
            return convert(bounds, to: scroll)
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
            scheduled?.cancel()
            poll?.cancel()
        }
    }
}

private struct TripListActiveRecordingNavIcon: View {
    var isPaused: Bool
    var reduceMotion: Bool

    private var accent: Color {
        isPaused ? TrailhoundBrandColors.paused : TrailhoundBrandColors.recording
    }

    private let maxTilt: Double = 55
    /// One ease-in-out half-swing (right → left). Full cycle is 2× this.
    private let swingDuration: Double = 2.4

    private var shouldAnimate: Bool {
        !isPaused && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @State private var clockDate = Date()

    var body: some View {
        ZStack {
            Image(systemName: "steeringwheel")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(accent)
            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)
        }
        .rotationEffect(.degrees(tilt(at: clockDate)))
        .background {
            TrailhoundDisplayLinkTicker(
                isRunning: shouldAnimate,
                framesPerSecond: ProcessInfo.processInfo.isLowPowerModeEnabled ? 10 : 20
            ) { clockDate = Date(timeIntervalSinceReferenceDate: $0) }
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    private func tilt(at date: Date) -> Double {
        guard shouldAnimate else { return 0 }
        let period = swingDuration * 2
        let unit = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return maxTilt * sin(unit * 2 * .pi)
    }
}

/// Book and landscape panes are regular-width, so List adds iPad side margins
/// and the cards look narrower than a portrait phone. Phone portrait is unchanged.
private struct PortraitPaneListWidth: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 26.0, *) {
                content
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .listSectionMargins(.horizontal, 0)
            } else {
                content.contentMargins(.horizontal, 0, for: .scrollContent)
            }
        } else {
            content
        }
    }
}

private extension View {
    func portraitPaneListWidth(_ enabled: Bool) -> some View {
        modifier(PortraitPaneListWidth(enabled: enabled))
    }
}

private enum TripListScrollTarget: Hashable {
    case top
}

private struct TripListScrollToTopRequest: Equatable {
    let id: UUID
}

/// UIKit fallback — iOS 17+ `List` is backed by `UICollectionView`, not `UITableView`.
private struct TripListScrollToTopInstaller: UIViewRepresentable {
    var request: TripListScrollToTopRequest?

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handledRequestID: UUID?
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let request else { return }
        guard context.coordinator.handledRequestID != request.id else { return }
        context.coordinator.handledRequestID = request.id
        scheduleScrollToTop(from: uiView)
    }

    private func scheduleScrollToTop(from view: UIView) {
        let delays: [TimeInterval] = [0, 0.05, 0.14]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let animated = index == delays.count - 1
                scrollLinkedListToTop(from: view, animated: animated)
            }
        }
    }

    private func scrollLinkedListToTop(from view: UIView, animated: Bool) {
        let scrollView = view.enclosingListScrollView ?? view.window?.largestVerticalScrollView
        scrollView?.forceScrollToTop(animated: animated)
    }
}

private extension UIScrollView {
    func forceScrollToTop(animated: Bool) {
        if let tableView = self as? UITableView,
           tableView.numberOfSections > 0,
           tableView.numberOfRows(inSection: 0) > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
        } else if let collectionView = self as? UICollectionView,
                  collectionView.numberOfSections > 0,
                  collectionView.numberOfItems(inSection: 0) > 0 {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: animated)
        }

        let top = CGPoint(x: 0, y: -adjustedContentInset.top)
        setContentOffset(top, animated: animated)
    }
}

private extension UIView {
    var enclosingListScrollView: UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let collectionView = view as? UICollectionView { return collectionView }
            if let tableView = view as? UITableView { return tableView }
            current = view.superview
        }
        return nil
    }

    var allSubviewsRecursive: [UIView] {
        subviews + subviews.flatMap(\.allSubviewsRecursive)
    }
}

private extension UIWindow {
    var largestVerticalScrollView: UIScrollView? {
        allSubviewsRecursive
            .compactMap { $0 as? UIScrollView }
            .filter { $0.contentSize.height > $0.bounds.height }
            .max(by: { $0.contentSize.height < $1.contentSize.height })
    }
}

/// Display fields of a trip row. A store save that does not change these must not
/// replace `loadedTrips`, or SwiftUI diffs every visible row.
private struct TripListRowStamp: Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let startPlaceName: String?
    let endPlaceName: String?
    let startAddress: String?
    let endAddress: String?
    let categoryRaw: String
    let note: String?
    let maxSpeedMps: Double?
    let estimatedFuelCost: Double?
    let dynamicFuelCost: Double?
    let pendingSuggestedCategoryID: String?
    let vehicleID: UUID?
}

private struct CreditsListLandingYKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The phone-book pane runs under the floating tab bar. Keep the recording card in the clear.
private struct PhoneBookRecordingClearance: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            GeometryReader { geo in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.bottom, geo.safeAreaInsets.bottom)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack { TripListView() }
        .modelContainer(PreviewData.shared.container)
        .environment(PreviewData.shared.recordingService)
}
