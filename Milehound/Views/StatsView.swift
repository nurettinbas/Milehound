import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    // Deliberately no `@Query` for trips: the stats tab only ever aggregates the selected period,
    // so it fetches that window instead of pulling the whole library into memory.
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query private var places: [SavedPlace]
    @Query(sort: \TravelJournal.endedOn, order: .reverse) private var journals: [TravelJournal]
    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.milehoundLayout) private var layout

    @State private var selectedPeriod: StatsPeriod = .week
    @State private var selectedCategoryID: String?
    @State private var selectedVehicleID: UUID?
    @State private var selectedPlaceID: UUID?
    @State private var selectedJournalID: UUID?
    @State private var selectedMonth = StatsFilterDefaults.selectedMonth()
    @State private var customStart = StatsFilterDefaults.customStart()
    @State private var customEnd = Date()
    @State private var animatedProgress: Double = 0
    @State private var snapshot: StatsDisplaySnapshot?
    @State private var renderedSnapshotFingerprint: String?
    @State private var snapshotRefreshTask: Task<Void, Never>?
    @State private var earliestTripStart: Date?
    /// Bumped whenever the store reports a save, standing in for the change tracking a `@Query`
    /// would have given us.
    @State private var storeVersion = 0
    @State private var snapshotLoader: StatsSnapshotLoader?
    @State private var costSnapshotLoader: VehicleCostSnapshotLoader?
    @State private var costSnapshot: VehicleCostSnapshot = .empty
    @State private var costRefreshTask: Task<Void, Never>?
    @Bindable private var tabSelection = TabSelection.shared
    @State private var dailyChartPage = 0
    @State private var chartPlotWidth: CGFloat = 0
    @State private var weekdayChartPage = 0
    @State private var mixChartPage = 0
    @State private var vehicleChartPage = 0
    @State private var categoryChartPage = 0
    @State private var filterCardStuck: CGFloat = 0
    @State private var filterCardNatural: CGFloat = 0
    @State private var statsSectionTracker = StickySectionTracker<StatsSection>(
        order: StatsSection.allCases,
        initial: .summary
    )
    @Namespace private var periodChipNamespace

    private var snap: StatsDisplaySnapshot {
        snapshot ?? .empty
    }

    private var selectedPlaceName: String? {
        guard let selectedPlaceID else { return nil }
        return places.first(where: { $0.id == selectedPlaceID })?.name
    }

    private var sortedPlaces: [SavedPlace] {
        places.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var snapshotInputs: StatsSnapshotInputs {
        StatsSnapshotInputs(
            storeVersion: storeVersion,
            categoryCount: categories.count,
            vehicleCount: vehicles.count,
            placeCount: places.count,
            journalCount: journals.count,
            period: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID,
            selectedPlaceID: selectedPlaceID,
            selectedPlaceName: selectedPlaceName,
            selectedJournalID: selectedJournalID
        )
    }

    private var goalMonth: Date {
        StatsViewModel.goalMonth(
            for: selectedPeriod,
            selectedMonth: selectedMonth,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private var goalTargetMeters: Double {
        settings.goalMeters(forMonthContaining: goalMonth)
    }

    private var isGoalEditable: Bool {
        settings.isGoalEditable(forMonthContaining: goalMonth)
    }

    private var goalProgress: Double {
        guard goalTargetMeters > 0 else { return 0 }
        return min(1, snap.goalDistanceMeters / goalTargetMeters)
    }

    private var goalPercentText: String {
        "\(Int(goalProgress * 100))%"
    }

    private var goalRangeLabel: String {
        DateFormatters.monthYear.string(from: goalMonth)
    }

    /// Date window the summary and charts aggregate over (not the goal month).
    private var statsPeriodScopeLabel: String {
        switch selectedPeriod {
        case .week:
            return selectedPeriod.title
        case .month:
            return DateFormatters.monthYear.string(from: selectedMonth)
        case .custom:
            let start = DateFormatters.chartDay.string(from: min(customStart, customEnd))
            let end = DateFormatters.chartDay.string(from: max(customStart, customEnd))
            return "\(start) – \(end)"
        }
    }

    /// Period plus any active category/vehicle/place filters — trip-based charts and summary.
    private var statsTripChartScopeLabel: String {
        var parts = [statsPeriodScopeLabel]
        if selectedCategoryID != nil {
            parts.append(selectedCategoryName)
        }
        if selectedVehicleID != nil {
            parts.append(selectedVehicleName)
        }
        if selectedPlaceID != nil {
            parts.append(selectedPlaceDisplayName)
        }
        if selectedJournalID != nil {
            parts.append(selectedJournalName)
        }
        return parts.joined(separator: " · ")
    }

    private var statsSummaryScopeLabel: String {
        statsTripChartScopeLabel
    }

    private var statsFilterFingerprint: String {
        [
            selectedPeriod.rawValue,
            String(selectedMonth.timeIntervalSince1970),
            String(customStart.timeIntervalSince1970),
            String(customEnd.timeIntervalSince1970),
            selectedCategoryID ?? "",
            selectedVehicleID?.uuidString ?? "",
            selectedPlaceID?.uuidString ?? "",
            selectedPlaceName ?? "",
            selectedJournalID?.uuidString ?? ""
        ].joined(separator: "|")
    }

    private var showsSummarySkeleton: Bool {
        snapshot == nil || renderedSnapshotFingerprint != statsFilterFingerprint
    }

    private var activeStatsFilterCount: Int {
        var count = 0
        if selectedPeriod != .week { count += 1 }
        if selectedCategoryID != nil { count += 1 }
        if selectedVehicleID != nil { count += 1 }
        if selectedPlaceID != nil { count += 1 }
        if selectedJournalID != nil { count += 1 }
        return count
    }

    private var hasResettableStatsFilters: Bool {
        activeStatsFilterCount > 0
    }

    private var statsFilterMenuColumns: [GridItem] {
        let spacing: CGFloat = 8
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: spacing)]
        }
        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ]
    }

    private func titledWithScope(_ baseKey: StaticString, scope: String) -> String {
        String(format: L10n.string("stats.title.with_scope"), L10n.string(baseKey), scope)
    }

    var body: some View {
        applyStatsObservers(statsChrome)
    }

    private var statsChrome: some View {
        statsList(currencyCode: settings.fuelCurrency.rawValue)
            .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: selectedPeriod)
            .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: selectedCategoryID)
            .glassListChrome(showsAtmosphere: !layout.isPhoneBook)
            .navigationTitle(L10n.string("stats.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onPreferenceChange(StatsChartPlotWidthKey.self) { width in
                guard width > 1, abs(width - chartPlotWidth) > 1 else { return }
                chartPlotWidth = width
            }
            .onAppear(perform: handleStatsAppear)
            .onStoreSave(perform: handleStatsStoreSave)
            .onDisappear {
                snapshotRefreshTask?.cancel()
                costRefreshTask?.cancel()
            }
    }

    private func applyStatsObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: snapshotInputs) { _, _ in
                scheduleSnapshotRefresh()
                scheduleCostSnapshotRefresh()
            }
            .onChange(of: selectedPeriod) { _, newPeriod in
                if newPeriod == .month {
                    normalizeSelectedMonth()
                }
                resetChartPages()
            }
            .onChange(of: goalProgress) { _, _ in
                updateAnimatedProgress(animated: true)
            }
            .onChange(of: snap.goalDistanceMeters) { _, _ in
                updateAnimatedProgress(animated: true)
            }
            .onChange(of: goalTargetMeters) { _, _ in
                updateAnimatedProgress(animated: true)
            }
            .onChange(of: selectedCategoryID) { _, _ in
                dailyChartPage = 0
                weekdayChartPage = 0
                mixChartPage = 0
                categoryChartPage = 0
            }
            .onChange(of: selectedVehicleID) { _, _ in
                dailyChartPage = 0
                weekdayChartPage = 0
                mixChartPage = 0
                vehicleChartPage = 0
            }
            .onChange(of: selectedPlaceID) { _, _ in
                resetChartPages()
            }
            .onChange(of: selectedJournalID) { _, _ in
                resetChartPages()
            }
            .onChange(of: selectedMonth) { _, _ in
                resetChartPages()
            }
            .onChange(of: customStart) { _, _ in
                resetChartPages()
            }
            .onChange(of: customEnd) { _, _ in
                resetChartPages()
            }
            .onChange(of: tabSelection.pendingStatsAnchor) { _, _ in
                consumeStatsDeepLink()
            }
    }

    private func handleStatsAppear() {
        if snapshotLoader == nil {
            snapshotLoader = StatsSnapshotLoader(modelContainer: modelContext.container)
        }
        if costSnapshotLoader == nil {
            costSnapshotLoader = VehicleCostSnapshotLoader(modelContainer: modelContext.container)
        }
        refreshEarliestTripStart()
        normalizeSelectedMonth()
        updateAnimatedProgress(animated: false)
        scheduleSnapshotRefresh()
        scheduleCostSnapshotRefresh()
        consumeStatsDeepLink()
    }

    private func handleStatsStoreSave() {
        refreshEarliestTripStart()
        storeVersion &+= 1
    }

    private func resetChartPages() {
        dailyChartPage = 0
        weekdayChartPage = 0
        mixChartPage = 0
        vehicleChartPage = 0
        categoryChartPage = 0
    }

    @ViewBuilder
    private func statsList(currencyCode: String) -> some View {
        if layout.layoutClass == .duoOpen || layout.isPhoneBook {
            MilehoundPaneSplit(
                leadingFraction: MilehoundLayoutResolver.flatBookLeadingFraction(
                    isPhoneBook: layout.isPhoneBook,
                    layoutClass: layout.layoutClass,
                    isLandscape: layout.isLandscape,
                    hingeFullyOpen: MilehoundHingeMonitor.shared.isFullyOpen,
                    fraction: MilehoundLayoutResolver.flatStatsLeadingFraction,
                    isPadBook: false
                )
            ) {
                ScrollView {
                    wideStatsPrimary(currencyCode: currencyCode)
                        .padding(16)
                }
                .glassCollapsingScroll()
            } focus: {
                ScrollView {
                    wideStatsDistributions(currencyCode: currencyCode)
                        .padding(16)
                }
                .glassCollapsingScroll()
            }
        } else if layout.showsHeroRail {
            HStack(alignment: .top, spacing: GlassTokens.hingeGutter) {
                VStack(alignment: .leading, spacing: 12) {
                    statsFilterCard
                        .statsFullCard()
                    statsHeroCard(currencyCode: currencyCode)
                        .statsHalfCard()
                }
                .frame(maxWidth: layout.size.width * GlassTokens.railWidthFraction)
                .padding(.leading, 16)
                phoneStatsList(currencyCode: currencyCode, showsFilterCard: false)
            }
        } else {
            phoneStatsList(currencyCode: currencyCode, showsFilterCard: true)
        }
    }

    @ViewBuilder
    private func wideStatsPrimary(currencyCode: String) -> some View {
        VStack(spacing: 12) {
            statsFilterCard
                .statsFullCard()
            summaryHeroPair(currencyCode: currencyCode)
            summaryMetricsCard(currencyCode: currencyCode)
        }
    }

    @ViewBuilder
    private var wideDailyChartBody: some View {
        if snap.hasAnyDailyChart || costSnapshot.hasTimelineChart {
            StatsChartPager(
                pageCount: dailyChartKinds.count,
                contentHeight: dailyChartKinds.contains(.expenses)
                    ? StatsChartPagerMetrics.costContentHeight
                    : StatsChartPagerMetrics.dailyContentHeight,
                selection: $dailyChartPage,
                reduceMotion: reduceMotion
            ) { index in
                dailyChartPageContent(kind: dailyChartKinds[index], pageIndex: index)
            }
            .moduleSpan(.feature)
        }
    }

    @ViewBuilder
    private func wideStatsDistributions(currencyCode: String) -> some View {
        LazyVStack(spacing: 12) {
            if snap.hasAnyDailyChart || costSnapshot.hasTimelineChart {
                statsPinnedSection(.daily, title: titledWithScope("stats.chart.daily_section", scope: statsTripChartScopeLabel)) {
                    wideDailyChartBody
                }
            }
            if snap.hasWeekdayCharts, !weekdayChartKinds.isEmpty {
                statsPinnedSection(.weekday, title: titledWithScope("stats.chart.weekday_section", scope: statsTripChartScopeLabel)) {
                    StatsChartPager(
                        pageCount: weekdayChartKinds.count,
                        contentHeight: StatsChartPagerMetrics.dailyContentHeight,
                        selection: $weekdayChartPage,
                        reduceMotion: reduceMotion
                    ) { index in
                        weekdayChartPageContent(kind: weekdayChartKinds[index], pageIndex: index)
                    }
                }
            }
            if snap.hasMixCharts, !mixChartKinds.isEmpty {
                statsPinnedSection(.mix, title: titledWithScope("stats.chart.mix_section", scope: statsTripChartScopeLabel)) {
                    StatsChartPager(
                        pageCount: mixChartKinds.count,
                        contentHeight: StatsChartPagerMetrics.donutContentHeight,
                        selection: $mixChartPage,
                        reduceMotion: reduceMotion
                    ) { index in
                        mixChartPageContent(kind: mixChartKinds[index], pageIndex: index)
                    }
                }
            }
            if showsVehicleCompareList || snap.showsVehicleBreakdownCharts || costSnapshot.hasVehicleBreakdown {
                statsPinnedSection(.vehicles, title: titledWithScope("stats.chart.vehicles_section", scope: statsTripChartScopeLabel)) {
                    if showsVehicleCompareList {
                        StatsVehicleCompareList(rows: vehicleCompareRows, currencyCode: currencyCode)
                    }
                    if snap.showsVehicleBreakdownCharts || costSnapshot.hasVehicleBreakdown {
                        StatsChartPager(
                            pageCount: vehicleChartKinds.count,
                            contentHeight: StatsChartPagerMetrics.donutContentHeight,
                            selection: $vehicleChartPage,
                            reduceMotion: reduceMotion
                        ) { index in
                            vehicleChartPageContent(kind: vehicleChartKinds[index], pageIndex: index)
                        }
                    }
                }
            }
            if snap.hasCategoryCharts || costSnapshot.hasCategoryBreakdown {
                statsPinnedSection(.categories, title: titledWithScope("stats.chart.categories_section", scope: statsTripChartScopeLabel)) {
                    StatsChartPager(
                        pageCount: categoryChartKinds.count,
                        contentHeight: StatsChartPagerMetrics.donutContentHeight,
                        selection: $categoryChartPage,
                        reduceMotion: reduceMotion
                    ) { index in
                        categoryChartPageContent(kind: categoryChartKinds[index], pageIndex: index)
                    }
                }
            }
        }
        .scrollTargetLayout()
    }

    @ViewBuilder
    private func phoneStatsList(currencyCode: String, showsFilterCard: Bool) -> some View {
        let list = ScrollView {
            LazyVStack(spacing: 12) {
                if showsFilterCard {
                    statsFilterCard
                        .padding(StatsCardTokens.contentInset)
                        .glassCollapsingPlate(
                            stuck: $filterCardStuck,
                            natural: $filterCardNatural
                        )
                }

                VStack(spacing: 12) {
                    summaryHeroPair(currencyCode: currencyCode)
                    summaryMetricsCard(currencyCode: currencyCode)
                }
                .transition(MilehoundMotion.fadeScaleTransition(reduceMotion: reduceMotion))

                if snap.hasAnyDailyChart || costSnapshot.hasTimelineChart {
                    statsPinnedSection(.daily, title: titledWithScope("stats.chart.daily_section", scope: statsTripChartScopeLabel)) {
                        StatsChartPager(
                            pageCount: dailyChartKinds.count,
                            contentHeight: dailyChartKinds.contains(.expenses)
                                ? StatsChartPagerMetrics.costContentHeight
                                : StatsChartPagerMetrics.dailyContentHeight,
                            selection: $dailyChartPage,
                            reduceMotion: reduceMotion
                        ) { index in
                            dailyChartPageContent(kind: dailyChartKinds[index], pageIndex: index)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: selectedPeriod)
                }

                if snap.hasWeekdayCharts, !weekdayChartKinds.isEmpty {
                    statsPinnedSection(.weekday, title: titledWithScope("stats.chart.weekday_section", scope: statsTripChartScopeLabel)) {
                        StatsChartPager(
                            pageCount: weekdayChartKinds.count,
                            contentHeight: StatsChartPagerMetrics.dailyContentHeight,
                            selection: $weekdayChartPage,
                            reduceMotion: reduceMotion
                        ) { index in
                            weekdayChartPageContent(kind: weekdayChartKinds[index], pageIndex: index)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if snap.hasMixCharts, !mixChartKinds.isEmpty {
                    statsPinnedSection(.mix, title: titledWithScope("stats.chart.mix_section", scope: statsTripChartScopeLabel)) {
                        StatsChartPager(
                            pageCount: mixChartKinds.count,
                            contentHeight: StatsChartPagerMetrics.donutContentHeight,
                            selection: $mixChartPage,
                            reduceMotion: reduceMotion
                        ) { index in
                            mixChartPageContent(kind: mixChartKinds[index], pageIndex: index)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if showsVehicleCompareList || snap.showsVehicleBreakdownCharts || costSnapshot.hasVehicleBreakdown {
                    statsPinnedSection(.vehicles, title: titledWithScope("stats.chart.vehicles_section", scope: statsTripChartScopeLabel)) {
                        if showsVehicleCompareList {
                            StatsVehicleCompareList(
                                rows: vehicleCompareRows,
                                currencyCode: currencyCode
                            )
                        }
                        if snap.showsVehicleBreakdownCharts || costSnapshot.hasVehicleBreakdown {
                            StatsChartPager(
                                pageCount: vehicleChartKinds.count,
                                contentHeight: StatsChartPagerMetrics.donutContentHeight,
                                selection: $vehicleChartPage,
                                reduceMotion: reduceMotion
                            ) { index in
                                vehicleChartPageContent(kind: vehicleChartKinds[index], pageIndex: index)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                if snap.hasCategoryCharts || costSnapshot.hasCategoryBreakdown {
                    statsPinnedSection(.categories, title: titledWithScope("stats.chart.categories_section", scope: statsTripChartScopeLabel)) {
                        StatsChartPager(
                            pageCount: categoryChartKinds.count,
                            contentHeight: StatsChartPagerMetrics.donutContentHeight,
                            selection: $categoryChartPage,
                            reduceMotion: reduceMotion
                        ) { index in
                            categoryChartPageContent(kind: categoryChartKinds[index], pageIndex: index)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: selectedCategoryID)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, GlassTokens.panelHorizontalInset)
            .padding(.bottom, 8)
        }
        .glassCollapsingScroll()
        .scrollPosition(id: statsScrollPosition, anchor: .top)
        .onChange(of: visibleStatsSections) { _, sections in
            statsSectionTracker.updateOrder(sections)
        }

        list
    }

    private var statsScrollPosition: Binding<StatsSection?> {
        Binding(
            get: { statsSectionTracker.visibleSection },
            set: { statsSectionTracker.applyScrollPosition($0) }
        )
    }

    private var visibleStatsSections: [StatsSection] {
        var sections: [StatsSection] = [.summary]
        if snap.hasAnyDailyChart || costSnapshot.hasTimelineChart {
            sections.append(.daily)
        }
        if snap.hasWeekdayCharts, !weekdayChartKinds.isEmpty {
            sections.append(.weekday)
        }
        if snap.hasMixCharts, !mixChartKinds.isEmpty {
            sections.append(.mix)
        }
        if showsVehicleCompareList || snap.showsVehicleBreakdownCharts || costSnapshot.hasVehicleBreakdown {
            sections.append(.vehicles)
        }
        if snap.hasCategoryCharts || costSnapshot.hasCategoryBreakdown {
            sections.append(.categories)
        }
        return sections
    }

    @ViewBuilder
    private func summaryHeroPair(currencyCode: String) -> some View {
        HStack(alignment: .top, spacing: StatsCardTokens.pairSpacing) {
            GlassCollapsingCard(
                title: L10n.string("stats.summary.section"),
                accessibilityIdentifier: "stats.section.summary"
            ) {
                statsGoalCard
            }
            .frame(
                maxWidth: .infinity,
                minHeight: StatsCardTokens.halfMinHeight,
                alignment: .top
            )

            GlassCollapsingCard(
                title: statsSummaryScopeLabel,
                accessibilityIdentifier: "stats.section.summary.period"
            ) {
                statsHeroCard(currencyCode: currencyCode)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: StatsCardTokens.halfMinHeight,
                alignment: .top
            )
        }
        .id(StatsSection.summary)
    }

    private func summaryMetricsCard(currencyCode: String) -> some View {
        GlassCollapsingCard(
            title: statsSummaryScopeLabel,
            accessibilityIdentifier: "stats.section.summary.metrics",
            contentInset: StatsCardTokens.summaryGridInset
        ) {
            summaryMetricsGrid(currencyCode: currencyCode)
        }
    }

    private func statsPinnedSection<Content: View>(
        _ section: StatsSection,
        title: String,
        applyCard: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCollapsingCard(
            title: title,
            accessibilityIdentifier: "stats.section.\(section.rawValue)",
            applyCard: applyCard
        ) {
            content()
        }
        .id(section)
    }

    private func scheduleCostSnapshotRefresh() {
        costRefreshTask?.cancel()
        let loader = costSnapshotLoader ?? VehicleCostSnapshotLoader(modelContainer: modelContext.container)
        if costSnapshotLoader == nil {
            costSnapshotLoader = loader
        }
        let interval = StatsViewModel.interval(
            for: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth
        )
        let previous = StatsViewModel.alignedPreviousInterval(
            for: selectedPeriod,
            selectedInterval: interval,
            selectedMonth: selectedMonth
        )
        let request = VehicleCostSnapshotRequest(
            storeVersion: storeVersion,
            periodStart: interval.start,
            periodEnd: interval.end,
            selectedVehicleID: selectedVehicleID,
            compareStart: previous.start,
            compareEnd: previous.end
        )
        costRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                costSnapshot = built
            }
        }
    }

    private func consumeStatsDeepLink() {
        guard tabSelection.pendingStatsAnchor == .goal else { return }
        _ = tabSelection.consumePendingStatsAnchor()
    }

    private func scheduleSnapshotRefresh() {
        snapshotRefreshTask?.cancel()

        let isFirstLoad = snapshot == nil
        let loader = snapshotLoader ?? StatsSnapshotLoader(modelContainer: modelContext.container)
        if snapshotLoader == nil {
            snapshotLoader = loader
        }

        let request = StatsSnapshotRequest(
            storeVersion: storeVersion,
            selectedPeriod: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            goalMonth: goalMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID,
            selectedPlaceName: selectedPlaceName,
            selectedJournalID: selectedJournalID,
            categoryNames: StatsViewModel.categoryNameMap(for: categories),
            vehicleNames: StatsViewModel.vehicleNameMap(for: vehicles),
            vehicleCount: vehicles.count
        )

        let requestFingerprint = statsFilterFingerprint
        snapshotRefreshTask = Task {
            if !isFirstLoad {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                snapshot = built
                renderedSnapshotFingerprint = requestFingerprint
            }
        }
    }

    private func refreshEarliestTripStart() {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        earliestTripStart = (try? modelContext.fetch(descriptor))?.first?.startedAt
    }

    private func normalizeSelectedMonth() {
        selectedMonth = StatsViewModel.clampedMonth(
            selectedMonth,
            earliestTripStart: earliestTripStart
        )
    }

    private var selectedVehicleName: String {
        selectedVehicle?.name ?? L10n.all
    }

    private var selectedVehicle: VehicleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
    }

    private var selectedCategoryName: String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.storageKey == selectedCategoryID }) else {
            return L10n.all
        }
        return category.name
    }

    private var selectedPlaceDisplayName: String {
        selectedPlaceName ?? L10n.all
    }

    private var selectedJournalName: String {
        guard let selectedJournalID,
              let journal = journals.first(where: { $0.id == selectedJournalID }) else {
            return L10n.all
        }
        return journal.title
    }

    private var statsFilterCard: some View {
        statsFilterFields(includePeriodChips: true)
    }

    private func statsFilterFields(includePeriodChips: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasResettableStatsFilters {
                statsFilterHeader
                    .transition(reduceMotion ? .identity : .opacity)
            }

            if includePeriodChips {
                statsPeriodChipRow
            }

            if selectedPeriod == .month {
                statsMonthPicker
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }

            if selectedPeriod == .custom {
                statsCustomDateFields
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }

            LazyVGrid(columns: statsFilterMenuColumns, alignment: .leading, spacing: 8) {
                StatsFilterMenuField(
                    title: L10n.string("filter.category"),
                    value: selectedCategoryName,
                    isActive: selectedCategoryID != nil,
                    identifier: "stats.filters.category"
                ) {
                    Picker(L10n.string("filter.category"), selection: $selectedCategoryID) {
                        Text(L10n.all).tag(String?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.storageKey))
                        }
                    }
                    .pickerStyle(.inline)
                }

                if !vehicles.isEmpty {
                    StatsFilterMenuField(
                        title: L10n.string("filter.vehicle"),
                        value: selectedVehicleName,
                        isActive: selectedVehicleID != nil,
                        identifier: "stats.filters.vehicle",
                        avatarSystemImage: selectedVehicle?.systemImage,
                        avatarPhotoFileName: selectedVehicle?.photoFileName,
                        avatarIsElectric: selectedVehicle?.fuelType == .electric
                    ) {
                        Picker(L10n.string("filter.vehicle"), selection: $selectedVehicleID) {
                            Text(L10n.all).tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(Optional(vehicle.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                if !sortedPlaces.isEmpty {
                    StatsFilterMenuField(
                        title: L10n.filterPlace,
                        value: selectedPlaceDisplayName,
                        isActive: selectedPlaceID != nil,
                        identifier: "stats.filters.place"
                    ) {
                        Picker(L10n.filterPlace, selection: $selectedPlaceID) {
                            Text(L10n.all).tag(UUID?.none)
                            ForEach(sortedPlaces, id: \.id) { place in
                                Text(place.name).tag(Optional(place.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                if !journals.isEmpty {
                    StatsFilterMenuField(
                        title: L10n.journalStatsFilter,
                        value: selectedJournalName,
                        isActive: selectedJournalID != nil,
                        identifier: "stats.filters.journal"
                    ) {
                        Picker(L10n.journalStatsFilter, selection: $selectedJournalID) {
                            Text(L10n.all).tag(UUID?.none)
                            ForEach(journals, id: \.id) { journal in
                                Text(journal.title).tag(Optional(journal.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
        }
        .accessibilityIdentifier("stats.filters.card")
        .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: selectedPeriod)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
    }

    private var statsFilterHeader: some View {
        HStack(spacing: 8) {
            Text("\(activeStatsFilterCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 4)
                .background(
                    colorScheme == .dark
                        ? shellPalette.tintColor(for: .dark)
                        : LightGlassPalette.selectedChipFill(for: shellPalette),
                    in: Capsule()
                )
                .accessibilityHidden(true)

            Text(L10n.statsFiltersActiveCount(activeStatsFilterCount))
                .font(.caption.weight(.semibold))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                resetStatsFiltersToDefaults()
            } label: {
                Text(L10n.statsFiltersClear)
                    .font(.caption.weight(.semibold))
                    .glassAccentForeground()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .glassField(cornerRadius: 10)
            }
            .buttonStyle(.glassPlainHit)
            .accessibilityIdentifier("stats.filters.clear")
        }
        .accessibilityElement(children: .contain)
    }

    private var statsPeriodChipRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                GlassChipGroup(spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        statsPeriodChips
                    }
                }
            } else {
                GlassChipGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        statsPeriodChips
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("stats.period.title"))
    }

    private var statsPeriodChips: some View {
        ForEach(StatsPeriod.allCases) { period in
            GlassFilterChip(
                title: period.title,
                isSelected: selectedPeriod == period,
                namespace: periodChipNamespace,
                highlightID: "statsPeriodHighlight",
                expands: true,
                size: .compact
            ) {
                if reduceMotion {
                    selectedPeriod = period
                } else {
                    withAnimation(MilehoundMotion.gentle) {
                        selectedPeriod = period
                    }
                }
                MilehoundHaptics.selection()
            }
            .accessibilityIdentifier("stats.filters.period.\(period.rawValue)")
        }
    }

    private var statsCustomDateFields: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    statsCustomDateField(
                        title: L10n.string("stats.period.start"),
                        date: $customStart
                    )
                    statsCustomDateField(
                        title: L10n.string("stats.period.end"),
                        date: $customEnd
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    statsCustomDateField(
                        title: L10n.string("stats.period.start"),
                        date: $customStart
                    )
                    statsCustomDateField(
                        title: L10n.string("stats.period.end"),
                        date: $customEnd
                    )
                }
            }
        }
    }

    private func resetStatsFiltersToDefaults() {
        let reset = {
            selectedPeriod = .week
            selectedCategoryID = nil
            selectedVehicleID = nil
            selectedPlaceID = nil
            selectedJournalID = nil
            selectedMonth = StatsFilterDefaults.selectedMonth()
            customStart = StatsFilterDefaults.customStart()
            customEnd = Date()
        }
        MilehoundHaptics.selection()
        if reduceMotion {
            reset()
        } else {
            withAnimation(MilehoundMotion.gentle) {
                reset()
            }
        }
    }

    private var selectableMonths: [Date] {
        StatsViewModel.selectableMonths(earliestTripStart: earliestTripStart)
    }

    private var selectedMonthTitle: String {
        DateFormatters.monthYear.string(from: selectedMonth)
    }

    private var canGoToPreviousMonth: Bool {
        guard let earliest = selectableMonths.last else { return false }
        let selectedStart = StatsViewModel.calendarMonthInterval(containing: selectedMonth).start
        return selectedStart > earliest
    }

    private var canGoToNextMonth: Bool {
        let selectedStart = StatsViewModel.calendarMonthInterval(containing: selectedMonth).start
        let currentStart = StatsViewModel.calendarMonthInterval(containing: Date()).start
        return selectedStart < currentStart
    }

    private var selectedMonthBinding: Binding<Date> {
        Binding(
            get: {
                StatsViewModel.clampedMonth(
                    selectedMonth,
                    earliestTripStart: earliestTripStart
                )
            },
            set: { newValue in
                selectedMonth = StatsViewModel.clampedMonth(
                    newValue,
                    earliestTripStart: earliestTripStart
                )
            }
        )
    }

    private var monthControlInk: Color {
        GlassText.primary(for: colorScheme)
    }

    private var statsMonthPicker: some View {
        HStack(spacing: 0) {
            monthStepButton(
                systemImage: "chevron.left",
                enabled: canGoToPreviousMonth,
                accessibilityKey: "stats.period.previous_month"
            ) {
                shiftSelectedMonth(by: -1)
            }

            Menu {
                Picker(L10n.string("stats.period.select_month"), selection: selectedMonthBinding) {
                    ForEach(selectableMonths, id: \.self) { month in
                        Text(DateFormatters.monthYear.string(from: month))
                            .tag(month)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(selectedMonthTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(GlassText.primary(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .tint(GlassControlTint.link(for: colorScheme, palette: shellPalette))
            .accessibilityLabel(L10n.string("stats.period.select_month"))
            .accessibilityValue(selectedMonthTitle)

            monthStepButton(
                systemImage: "chevron.right",
                enabled: canGoToNextMonth,
                accessibilityKey: "stats.period.next_month"
            ) {
                shiftSelectedMonth(by: 1)
            }
        }
        .padding(.horizontal, 4)
        .glassField(cornerRadius: 12)
        .onAppear {
            selectedMonth = StatsViewModel.clampedMonth(
                selectedMonth,
                earliestTripStart: earliestTripStart
            )
        }
    }

    private func shiftSelectedMonth(by value: Int) {
        selectedMonth = StatsViewModel.clampedMonth(
            StatsViewModel.shiftMonth(selectedMonth, by: value),
            earliestTripStart: earliestTripStart
        )
        MilehoundHaptics.selection()
    }

    private func monthStepButton(
        systemImage: String,
        enabled: Bool,
        accessibilityKey: StaticString,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? monthControlInk : monthControlInk.opacity(0.35))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPlainHit)
        .disabled(!enabled)
        .accessibilityLabel(L10n.string(accessibilityKey))
    }

    private func statsCustomDateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            DatePicker(title, selection: date, displayedComponents: .date)
                .glassDatePicker()
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .glassField(cornerRadius: 12)
    }

    private var statsGoalCard: some View {
        VStack(spacing: 8) {
            goalRing
            VStack(spacing: 2) {
                Text(L10n.string("stats.goal.monthly"))
                    .font(.caption.weight(.semibold))
                Text(goalRangeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                Text("\(DateFormatters.formatDistance(snap.goalDistanceMeters)) / \(DateFormatters.formatDistance(goalTargetMeters))")
                    .font(.caption2)
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center)

            if isGoalEditable {
                VStack(spacing: 4) {
                    Text(L10n.string("stats.goal.target_km"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                    statsGoalStepper
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var statsGoalStepper: some View {
        let kilometers = Int(goalTargetMeters / 1000)
        let minimum = 50
        let maximum = 2000
        let step = 50
        return HStack(spacing: 0) {
            Button {
                guard kilometers > minimum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers - step) * 1000)
                MilehoundHaptics.selection()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(kilometers <= minimum)

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 0.5, height: 12)

            Button {
                guard kilometers < maximum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers + step) * 1000)
                MilehoundHaptics.selection()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(kilometers >= maximum)
        }
        .buttonStyle(.glassPlainHit)
        .foregroundStyle(GlassText.primary(for: colorScheme))
        .glassField(cornerRadius: 12)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("stats.goal.target_km"))
        .accessibilityValue(DateFormatters.formatDistance(goalTargetMeters))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                guard kilometers < maximum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers + step) * 1000)
            case .decrement:
                guard kilometers > minimum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers - step) * 1000)
            @unknown default:
                break
            }
            MilehoundHaptics.selection()
        }
    }

    private func statsHeroCard(currencyCode: String) -> some View {
        let rows = heroCompareRows(currencyCode: currencyCode)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                        .lineLimit(1)
                    HStack(alignment: .center, spacing: 4) {
                        Text(row.currentText)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        StatsTrendBadge(trend: row.trend, metricName: row.title)
                    }
                    Text("\(comparePreviousLabel) \(row.previousText)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroAccessibilityLabel(for: row))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func heroAccessibilityLabel(for row: StatsPeriodCompareRow) -> String {
        var parts = [
            row.title,
            "\(compareCurrentLabel) \(row.currentText)",
            "\(comparePreviousLabel) \(row.previousText)"
        ]
        if let trend = row.trend {
            parts.append(trend.accessibilityLabel(metricName: row.title))
        }
        return parts.joined(separator: ", ")
    }

    private func heroCompareRows(currencyCode: String) -> [StatsPeriodCompareRow] {
        let byID = Dictionary(uniqueKeysWithValues: periodCompareRows(currencyCode: currencyCode).map { ($0.id, $0) })
        let ids = hidesUnscopedCostComparison
            ? ["distance", "duration", "trips"]
            : ["distance", "duration", "expenses"]
        return ids.compactMap { byID[$0] }
    }

    private var heroMetricIDs: Set<String> {
        hidesUnscopedCostComparison
            ? ["distance", "duration", "trips"]
            : ["distance", "duration", "expenses"]
    }

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(shellPalette.tintColor(for: colorScheme).opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    shellPalette.tintColor(for: colorScheme),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(goalPercentText)
                .font(.caption2.weight(.bold))
                .numericTextAnimation(value: goalPercentText)
        }
        .frame(width: 56, height: 56)
        .accessibilityLabel(L10n.string("stats.goal.progress_accessibility"))
        .accessibilityValue("\(goalPercentText), \(goalRangeLabel)")
    }

    private func updateAnimatedProgress(animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(MilehoundMotion.cardSpring) {
                animatedProgress = goalProgress
            }
        } else {
            animatedProgress = goalProgress
        }
    }

    private func summaryMetricsGrid(currencyCode: String) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 5),
            GridItem(.flexible(), spacing: 5)
        ]
        let items = summaryMetricItems(currencyCode: currencyCode)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            if showsSummarySkeleton {
                ForEach(0..<items.count, id: \.self) { index in
                    StatsSummaryTileSkeleton(reduceMotion: reduceMotion)
                        .accessibilityIdentifier("stats.summary.skeleton.\(index)")
                }
            } else {
                ForEach(items) { item in
                    summaryMetricCard(
                        title: item.title,
                        value: item.value,
                        trend: item.trend,
                        previousText: item.previousText,
                        helpTitle: item.helpTitle,
                        helpBody: item.helpBody
                    )
                }
            }
        }
        .accessibilityElement(children: showsSummarySkeleton ? .ignore : .contain)
        .accessibilityIdentifier(showsSummarySkeleton ? "stats.summary.skeleton" : "stats.summary.grid")
        .modifier(StatsSummaryGridAccessibility(isLoading: showsSummarySkeleton))
        .animation(nil, value: showsSummarySkeleton)
    }

    private func summaryMetricItems(currencyCode: String) -> [StatsSummaryMetricItem] {
        let skip = heroMetricIDs
        let compareByID = Dictionary(
            uniqueKeysWithValues: periodCompareRows(currencyCode: currencyCode).map { ($0.id, $0) }
        )
        var items: [StatsSummaryMetricItem] = []
        if !skip.contains("trips") {
            items.append(
                StatsSummaryMetricItem(
                    id: "trips",
                    title: L10n.string("stats.trips"),
                    value: "\(snap.stats.tripCount)",
                    trend: snap.tripCountTrend,
                    previousText: compareByID["trips"]?.previousText
                )
            )
        }
        if !skip.contains("distance") {
            items.append(
                StatsSummaryMetricItem(
                    id: "distance",
                    title: L10n.string("stats.total_distance"),
                    value: snap.stats.totalDistanceText,
                    trend: snap.distanceTrend,
                    previousText: compareByID["distance"]?.previousText
                )
            )
        }
        if !skip.contains("duration") {
            items.append(
                StatsSummaryMetricItem(
                    id: "duration",
                    title: L10n.string("stats.total_duration"),
                    value: snap.stats.totalDurationText,
                    trend: snap.durationTrend,
                    previousText: compareByID["duration"]?.previousText
                )
            )
        }
        if !hidesUnscopedCostComparison, !skip.contains("expenses") {
            items.append(
                StatsSummaryMetricItem(
                    id: "expenses",
                    title: L10n.string("stats.total_expenses"),
                    value: costSnapshot.total > 0
                        ? FuelCostCalculator.formatCost(costSnapshot.total, currencyCode: currencyCode)
                        : "—",
                    trend: costSnapshot.expenseTrend,
                    previousText: compareByID["expenses"]?.previousText
                )
            )
        }
        items.append(contentsOf: [
            StatsSummaryMetricItem(
                id: "averageDuration",
                title: L10n.string("stats.average_duration"),
                value: snap.stats.averageDurationText
            ),
            StatsSummaryMetricItem(
                id: "averageDistance",
                title: L10n.string("stats.average_distance"),
                value: snap.stats.averageDistanceText,
                trend: snap.averageDistanceTrend,
                previousText: snap.previousStats.averageDistanceMeters > 0
                    ? snap.previousStats.averageDistanceText
                    : nil
            ),
            StatsSummaryMetricItem(
                id: "averageSpeed",
                title: L10n.string("stats.average_speed"),
                value: snap.stats.averageSpeedText,
                trend: snap.averageSpeedTrend
            ),
            StatsSummaryMetricItem(
                id: "maxSpeed",
                title: L10n.string("stats.max_speed"),
                value: snap.stats.maxSpeedText,
                trend: snap.maxSpeedTrend
            ),
            StatsSummaryMetricItem(
                id: "cruiseSpeed",
                title: L10n.string("stats.cruise_speed"),
                value: snap.stats.cruiseSpeedText,
                trend: snap.cruiseSpeedTrend,
                helpTitle: L10n.cruiseSpeedHelpTitle,
                helpBody: L10n.cruiseSpeedHelpBody
            ),
            StatsSummaryMetricItem(
                id: "mostCommonSpeed",
                title: L10n.string("stats.most_common_speed"),
                value: snap.stats.mostCommonSpeedText,
                trend: snap.mostCommonSpeedTrend,
                helpTitle: L10n.mostCommonSpeedHelpTitle,
                helpBody: L10n.mostCommonSpeedHelpBody
            ),
            StatsSummaryMetricItem(
                id: "stopDuration",
                title: L10n.string("stats.stop_duration"),
                value: snap.stats.stopDurationText,
                trend: snap.stopDurationTrend
            ),
            StatsSummaryMetricItem(
                id: "movingDuration",
                title: L10n.string("stats.moving_duration"),
                value: snap.stats.movingDurationText,
                trend: snap.movingDurationTrend,
                previousText: snap.previousStats.movingDuration > 0
                    ? snap.previousStats.movingDurationText
                    : nil,
                helpTitle: L10n.movingDurationHelpTitle,
                helpBody: L10n.movingDurationHelpBody
            ),
            StatsSummaryMetricItem(
                id: "estimatedFuel",
                title: L10n.string("stats.total_estimated_fuel"),
                value: FuelCostCalculator.formatCost(snap.stats.estimatedFuelCost, currencyCode: currencyCode),
                trend: snap.fuelCostTrend,
                previousText: compareByID["fuel"]?.previousText
            ),
            StatsSummaryMetricItem(
                id: "dynamicFuel",
                title: L10n.string("stats.total_dynamic_fuel"),
                value: snap.stats.dynamicFuelCost > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicFuelCost, currencyCode: currencyCode)
                    : "—",
                trend: snap.dynamicFuelCostTrend,
                helpTitle: L10n.dynamicFuelHelpTitle,
                helpBody: L10n.statsDynamicFuelHelpBody
            ),
            StatsSummaryMetricItem(
                id: "dynamicFuelVolume",
                title: L10n.statsFuelVolume,
                value: snap.stats.hasMixedFuelUnits
                    ? L10n.statsMixedFuelUnits
                    : (FuelCostCalculator.formatVolumeAmount(
                        snap.stats.dynamicFuelVolume,
                        isElectric: snap.stats.fuelUnitIsElectric
                    ) ?? "—"),
                helpTitle: L10n.statsFuelVolumeHelpTitle,
                helpBody: L10n.statsFuelVolumeHelpBody
            ),
            StatsSummaryMetricItem(
                id: "dynamicFuelRate",
                title: L10n.statsFuelRate,
                value: {
                    if snap.stats.hasMixedFuelUnits { return L10n.statsMixedFuelUnits }
                    let km = snap.stats.dynamicFuelVolumeDistanceMeters / 1_000
                    guard km > 0, snap.stats.dynamicFuelVolume > 0 else { return "—" }
                    return FuelCostCalculator.formatRatePer100(
                        100 * snap.stats.dynamicFuelVolume / km,
                        isElectric: snap.stats.fuelUnitIsElectric
                    ) ?? "—"
                }(),
                helpTitle: L10n.statsFuelRateHelpTitle,
                helpBody: L10n.statsFuelRateHelpBody
            ),
            StatsSummaryMetricItem(
                id: "fuelEfficiency",
                title: L10n.statsFuelEfficiency,
                value: snap.stats.hasMixedFuelUnits
                    ? L10n.statsMixedFuelUnits
                    : (snap.stats.fuelEfficiencyScore > 0
                        ? "\(Int(snap.stats.fuelEfficiencyScore.rounded()))"
                        : "—"),
                helpTitle: L10n.fuelEfficiencyHelpTitle,
                helpBody: L10n.fuelEfficiencyHelpBody
            ),
            StatsSummaryMetricItem(
                id: "costPerKm",
                title: L10n.string("stats.cost_per_km"),
                value: snap.stats.costPerKm > 0
                    ? FuelCostCalculator.formatCost(snap.stats.costPerKm, currencyCode: currencyCode)
                    : "—"
            ),
            StatsSummaryMetricItem(
                id: "dynamicCostPerKm",
                title: L10n.string("stats.dynamic_cost_per_km"),
                value: snap.stats.dynamicCostPerKm > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicCostPerKm, currencyCode: currencyCode)
                    : "—",
                helpTitle: L10n.statsDynamicCostPerKmHelpTitle,
                helpBody: L10n.statsDynamicCostPerKmHelpBody
            ),
            StatsSummaryMetricItem(
                id: "averageCostPerTrip",
                title: L10n.string("stats.average_cost_per_trip"),
                value: snap.stats.averageCostPerTrip > 0
                    ? FuelCostCalculator.formatCost(snap.stats.averageCostPerTrip, currencyCode: currencyCode)
                    : "—"
            ),
            StatsSummaryMetricItem(
                id: "dynamicCostPerTrip",
                title: L10n.string("stats.dynamic_cost_per_trip"),
                value: snap.stats.dynamicCostPerTrip > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicCostPerTrip, currencyCode: currencyCode)
                    : "—",
                helpTitle: L10n.statsDynamicCostPerTripHelpTitle,
                helpBody: L10n.statsDynamicCostPerTripHelpBody
            ),
            StatsSummaryMetricItem(
                id: "nightDriving",
                title: L10n.string("stats.night_driving"),
                value: snap.stats.nightDrivingText
            ),
            StatsSummaryMetricItem(
                id: "nightKm",
                title: L10n.string("stats.night_km"),
                value: snap.stats.nightDistanceText,
                trend: snap.nightDistanceTrend,
                previousText: snap.previousStats.nightDistanceMeters > 0
                    ? snap.previousStats.nightDistanceText
                    : nil
            ),
            StatsSummaryMetricItem(
                id: "drivingDays",
                title: L10n.string("stats.driving_days"),
                value: L10n.statsDrivingDays(snap.drivingDayCount, of: snap.periodDayCount),
                trend: snap.drivingDayTrend,
                previousText: snap.previousDrivingDayCount > 0
                    ? L10n.statsDrivingDays(snap.previousDrivingDayCount, of: snap.previousPeriodDayCount)
                    : nil,
                helpTitle: L10n.statsDrivingDaysHelpTitle,
                helpBody: L10n.statsDrivingDaysHelpBody
            ),
            StatsSummaryMetricItem(
                id: "busiestDay",
                title: L10n.string("stats.busiest_day"),
                value: busiestDayText
            )
        ])
        return items
    }

    private var busiestDayText: String {
        guard let day = snap.busiestDay, snap.busiestDayMeters > 0 else { return "—" }
        let date = DateFormatters.chartDay.string(from: day)
        let distance = DateFormatters.formatDistance(snap.busiestDayMeters)
        return "\(date) · \(distance)"
    }

    private func summaryMetricCard(
        title: String,
        value: String,
        trend: StatsTrend? = nil,
        previousText: String? = nil,
        helpTitle: String? = nil,
        helpBody: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let helpTitle, let helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: 16
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(height: StatsCardTokens.nestedTileTitleRowHeight)

            HStack(alignment: .center, spacing: 4) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                StatsTrendBadge(trend: trend, metricName: title)
            }

            Text(previousText.map { "\(comparePreviousLabel) \($0)" } ?? " ")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: StatsCardTokens.nestedTilePreviousLineHeight, alignment: .topLeading)
                .opacity(previousText == nil ? 0 : 1)
                .accessibilityHidden(previousText == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsNestedTile()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            summaryAccessibilityLabel(
                title: title,
                value: value,
                trend: trend,
                previousText: previousText
            )
        )
    }

    private func summaryAccessibilityLabel(
        title: String,
        value: String,
        trend: StatsTrend?,
        previousText: String? = nil
    ) -> String {
        var parts = [title, value]
        if let previousText {
            parts.append("\(comparePreviousLabel) \(previousText)")
        }
        if let trend {
            parts.append(trend.accessibilityLabel(metricName: title))
        }
        return parts.joined(separator: ", ")
    }

    private var dailyChartDayCount: Int {
        max(
            snap.dailyDistance.count,
            snap.dailyDuration.count,
            snap.dailyAverageSpeed.count,
            snap.dailyMaxSpeed.count,
            snap.dailyCruiseSpeed.count,
            snap.dailyMostCommonSpeed.count,
            snap.dailyStopDuration.count,
            snap.dailyFuelCost.count,
            snap.dailyTripCount.count,
            snap.dailyNightDistance.count,
            1
        )
    }

    /// Keep x-axis readable: daily for week, weekly ticks for month-sized ranges.
    private var dailyAxisLabelStride: Int {
        switch selectedPeriod {
        case .week:
            return 1
        case .month:
            return 5
        case .custom:
            switch dailyChartDayCount {
            case ...10: return 1
            case ...20: return 2
            default: return 5
            }
        }
    }

    private func dailyAxisDayLabel(_ date: Date) -> String {
        DateFormatters.chartDay.string(from: date)
    }

    private func dailyAxisLabelDates(from days: [Date]) -> [Date] {
        let stride = dailyAxisLabelStride
        return days.enumerated().compactMap { index, day in
            (index % stride == 0 || index == days.count - 1) ? day : nil
        }
    }

    /// A week of `d MMM` labels overlaps once each bar is narrower than caption size.
    /// Open-fold panes are always in that range; a normal phone chart is not.
    private func chartAxisUsesCompactDates(slots: Int) -> Bool {
        if layout.layoutClass == .duoOpen || layout.isPhoneBook { return true }
        return chartAxisSlotWidth(slots: slots) < 40
    }

    private var chartPlotEstimate: CGFloat {
        if chartPlotWidth > 1 { return chartPlotWidth }
        if layout.layoutClass == .duoOpen || layout.isPhoneBook {
            return max(140, (layout.size.width - GlassTokens.hingeGutter) / 2 - 32)
        }
        return max(140, layout.size.width - 64)
    }

    private func chartAxisSlotWidth(slots: Int) -> CGFloat {
        let usable = max(72, chartPlotEstimate - 40)
        return max(14, usable / CGFloat(max(slots, 1)))
    }

    @ViewBuilder
    private func chartAxisLabel(_ text: String, slots: Int) -> some View {
        let compact = chartAxisUsesCompactDates(slots: slots)
        let label = Text(text)
            .font(compact ? Font.system(size: 9, weight: .medium) : Font.caption2)
            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(compact ? 0.5 : 0.75)
            .allowsTightening(true)
        if compact {
            label.frame(width: chartAxisSlotWidth(slots: slots))
        } else {
            label
        }
    }

    @AxisContentBuilder
    private func dailyChartXAxis(days: [Date]) -> some AxisContent {
        AxisMarks(values: dailyAxisLabelDates(from: days)) { value in
            if let date = value.as(Date.self) {
                AxisValueLabel(centered: true) {
                    chartAxisLabel(dailyAxisDayLabel(date), slots: max(days.count, 1))
                }
            }
        }
    }

    private enum DailyChartKind: Hashable {
        case distance
        case duration
        case averageSpeed
        case maxSpeed
        case cruiseSpeed
        case mostCommonSpeed
        case stopDuration
        case trips
        case night
        case fuel
        case expenses
    }

    private enum WeekdayChartKind: Hashable {
        case distance
        case duration
    }

    private enum MixChartKind: Hashable {
        case nightDay
        case movingStop
        case fuelFactors
    }

    private enum VehicleChartKind: Hashable {
        case distance
        case duration
        case fuel
        case expenses
    }

    private enum CategoryChartKind: Hashable {
        case distance
        case duration
        case fuel
        case expenses
    }

    private var costInterval: DateInterval {
        StatsViewModel.interval(
            for: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth
        )
    }

    private var hidesUnscopedCostComparison: Bool {
        StatsViewModel.hidesUnscopedCostComparison(
            categoryID: selectedCategoryID,
            placeName: selectedPlaceName,
            journalID: selectedJournalID
        )
    }

    private var vehicleCompareRows: [VehicleCompareRow] {
        StatsVehicleCompareBuilder.rows(
            seeds: costSnapshot.compareSeeds,
            distances: snap.vehicleDistance
        )
    }

    private var showsVehicleCompareList: Bool {
        StatsViewModel.showsVehicleCompareList(
            hidesUnscopedCosts: hidesUnscopedCostComparison,
            selectedVehicleID: selectedVehicleID,
            rowCount: vehicleCompareRows.count
        )
    }

    private var compareCurrentLabel: String {
        switch selectedPeriod {
        case .week: L10n.string("stats.compare.this_week")
        case .month: L10n.string("stats.compare.this_month")
        case .custom: L10n.string("stats.compare.this_range")
        }
    }

    private var comparePreviousLabel: String {
        switch selectedPeriod {
        case .week: L10n.string("stats.compare.previous_week")
        case .month:
            if StatsViewModel.usesMonthToDatePrevious(for: .month, selectedMonth: selectedMonth) {
                L10n.string("stats.compare.same_days_last_month")
            } else {
                L10n.string("stats.compare.last_month")
            }
        case .custom: L10n.string("stats.compare.previous_range")
        }
    }

    private func periodCompareRows(currencyCode: String) -> [StatsPeriodCompareRow] {
        let stats = snap.stats
        let previous = snap.previousStats
        let dash = "—"
        let includeExpenses = !hidesUnscopedCostComparison
        let expenseCurrent = costSnapshot.total > 0
            ? FuelCostCalculator.formatCost(costSnapshot.total, currencyCode: currencyCode)
            : dash
        let expensePrevious = costSnapshot.previousTotal > 0
            ? FuelCostCalculator.formatCost(costSnapshot.previousTotal, currencyCode: currencyCode)
            : dash
        let byID: [String: StatsPeriodCompareRow] = [
            "trips": StatsPeriodCompareRow(
                id: "trips",
                title: L10n.string("stats.trips"),
                currentText: "\(stats.tripCount)",
                previousText: "\(previous.tripCount)",
                trend: snap.tripCountTrend
            ),
            "distance": StatsPeriodCompareRow(
                id: "distance",
                title: L10n.string("stats.total_distance"),
                currentText: stats.totalDistanceText,
                previousText: previous.totalDistanceText,
                trend: snap.distanceTrend
            ),
            "duration": StatsPeriodCompareRow(
                id: "duration",
                title: L10n.string("stats.total_duration"),
                currentText: stats.totalDurationText,
                previousText: previous.totalDurationText,
                trend: snap.durationTrend
            ),
            "expenses": StatsPeriodCompareRow(
                id: "expenses",
                title: L10n.string("stats.total_expenses"),
                currentText: expenseCurrent,
                previousText: expensePrevious,
                trend: costSnapshot.expenseTrend
            ),
            "fuel": StatsPeriodCompareRow(
                id: "fuel",
                title: L10n.string("stats.total_estimated_fuel"),
                currentText: FuelCostCalculator.formatCost(stats.estimatedFuelCost, currencyCode: currencyCode),
                previousText: FuelCostCalculator.formatCost(previous.estimatedFuelCost, currencyCode: currencyCode),
                trend: snap.fuelCostTrend
            )
        ]
        return StatsViewModel.periodCompareMetricIDs(includeExpenses: includeExpenses).compactMap { byID[$0] }
    }

    private var dailyChartKinds: [DailyChartKind] {
        var kinds: [DailyChartKind] = []
        if !snap.dailyDistance.isEmpty { kinds.append(.distance) }
        if !snap.dailyDuration.isEmpty { kinds.append(.duration) }
        if !snap.dailyAverageSpeed.isEmpty { kinds.append(.averageSpeed) }
        if !snap.dailyMaxSpeed.isEmpty { kinds.append(.maxSpeed) }
        if !snap.dailyCruiseSpeed.isEmpty { kinds.append(.cruiseSpeed) }
        if !snap.dailyMostCommonSpeed.isEmpty { kinds.append(.mostCommonSpeed) }
        if !snap.dailyStopDuration.isEmpty { kinds.append(.stopDuration) }
        if !snap.dailyTripCount.isEmpty { kinds.append(.trips) }
        if snap.hasNightDailyChart { kinds.append(.night) }
        if !snap.dailyFuelCost.isEmpty { kinds.append(.fuel) }
        if costSnapshot.hasTimelineChart { kinds.append(.expenses) }
        return kinds
    }

    private var weekdayChartKinds: [WeekdayChartKind] {
        var kinds: [WeekdayChartKind] = []
        if snap.weekdayDistance.contains(where: { $0.distanceMeters > 0 }) {
            kinds.append(.distance)
        }
        if snap.weekdayDuration.contains(where: { $0.duration > 0 }) {
            kinds.append(.duration)
        }
        return kinds
    }

    private var mixChartKinds: [MixChartKind] {
        var kinds: [MixChartKind] = []
        if snap.stats.trackedDistanceMeters > 0 { kinds.append(.nightDay) }
        if snap.stats.totalDuration > 0 { kinds.append(.movingStop) }
        if !snap.stats.fuelFactorShares.isEmpty { kinds.append(.fuelFactors) }
        return kinds
    }

    private var vehicleChartKinds: [VehicleChartKind] {
        var kinds: [VehicleChartKind] = []
        if snap.showsVehicleBreakdownCharts {
            kinds.append(.distance)
            if !snap.vehicleDuration.isEmpty { kinds.append(.duration) }
            if !snap.vehicleFuelCost.isEmpty { kinds.append(.fuel) }
        }
        if costSnapshot.hasVehicleBreakdown { kinds.append(.expenses) }
        return kinds
    }

    private var categoryChartKinds: [CategoryChartKind] {
        var kinds: [CategoryChartKind] = []
        if !snap.categoryDistance.isEmpty { kinds.append(.distance) }
        if !snap.categoryDuration.isEmpty { kinds.append(.duration) }
        if !snap.categoryFuelCost.isEmpty { kinds.append(.fuel) }
        if costSnapshot.hasCategoryBreakdown { kinds.append(.expenses) }
        return kinds
    }

    @ViewBuilder
    private func dailyChartPageContent(kind: DailyChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == dailyChartPage
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        switch kind {
        case .distance:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.weekly_distance", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyDistanceChartBody(snap.dailyDistance)
            }
        case .duration:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.weekly_duration", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyDurationChartBody(snap.dailyDuration)
            }
        case .averageSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_average_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyAverageSpeedChartBody(snap.dailyAverageSpeed)
            }
        case .maxSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_max_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyMaxSpeedChartBody(snap.dailyMaxSpeed)
            }
        case .cruiseSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_cruise_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyCruiseSpeedChartBody(snap.dailyCruiseSpeed)
            }
        case .mostCommonSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_most_common_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyMostCommonSpeedChartBody(snap.dailyMostCommonSpeed)
            }
        case .stopDuration:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_stop_duration", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyStopDurationChartBody(snap.dailyStopDuration)
            }
        case .trips:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_trips", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyTripCountChartBody(snap.dailyTripCount)
            }
        case .night:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_night", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyNightDistanceChartBody(snap.dailyNightDistance)
            }
        case .fuel:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_fuel", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive,
                titleAccessory: {
                    HelpPopoverButton(
                        accessibilityLabel: L10n.dynamicFuelHelpTitle,
                        message: L10n.statsDynamicFuelHelpBody
                    )
                }
            ) {
                dailyFuelCostChartBody(snap.dailyFuelCost)
            }
        case .expenses:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_expenses", scope: statsTripChartScopeLabel),
                chartHeight: StatsChartTheme.costBarChartBodyHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                VehicleCareMiniChart(
                    months: costSnapshot.months,
                    days: costSnapshot.days,
                    periodStart: costInterval.start,
                    periodEnd: costInterval.end,
                    currencyCode: fuelCurrencyCode
                )
            }
        }
    }

    @ViewBuilder
    private func weekdayChartPageContent(kind: WeekdayChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == weekdayChartPage
        switch kind {
        case .distance:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.weekday_distance", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                weekdayDistanceChartBody(snap.weekdayDistance)
            }
        case .duration:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.weekday_duration", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                weekdayDurationChartBody(snap.weekdayDuration)
            }
        }
    }

    @ViewBuilder
    private func mixChartPageContent(kind: MixChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == mixChartPage
        switch kind {
        case .nightDay:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                nightDayDonut()
            }
        case .movingStop:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                movingStopDonut()
            }
        case .fuelFactors:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                fuelFactorsDonut()
            }
        }
    }

    @ViewBuilder
    private func vehicleChartPageContent(kind: VehicleChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == vehicleChartPage
        switch kind {
        case .distance:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleDistanceDonut(data: snap.vehicleDistance)
            }
        case .duration:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleDurationDonut(data: snap.vehicleDuration)
            }
        case .fuel:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleFuelDonut(data: snap.vehicleFuelCost)
            }
        case .expenses:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleExpensesDonut(data: costSnapshot.vehicleBreakdown)
            }
        }
    }

    @ViewBuilder
    private func categoryChartPageContent(kind: CategoryChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == categoryChartPage
        switch kind {
        case .distance:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryDistanceDonut(data: snap.categoryDistance)
            }
        case .duration:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryDurationDonut(data: snap.categoryDuration)
            }
        case .fuel:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryFuelDonut(data: snap.categoryFuelCost)
            }
        case .expenses:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryExpensesDonut(data: costSnapshot.categoryBreakdown)
            }
        }
    }

    private func dailyDistanceChartBody(_ dailyChartData: [DailyDistance]) -> some View {
        let days = dailyChartData.map(\.day)
        return Chart(dailyChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers)
            )
            .foregroundStyle(StatsChartTheme.distanceBarFill(for: colorScheme, palette: shellPalette))
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyChartData.map(\.distanceKilometers).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.distance_km"))
        .frame(height: 200)
    }

    private func dailyDurationChartBody(_ dailyDurationChartData: [DailyDuration]) -> some View {
        let days = dailyDurationChartData.map(\.day)
        return Chart(dailyDurationChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
            )
            .foregroundStyle(StatsChartTheme.durationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyDurationChartData.map(\.durationHours).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.duration_hours"))
        .frame(height: 200)
    }

    private func dailyAverageSpeedChartBody(_ dailyAverageSpeedChartData: [DailyAverageSpeed]) -> some View {
        let days = dailyAverageSpeedChartData.map(\.day)
        return Chart(dailyAverageSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.averageSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyAverageSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyMaxSpeedChartBody(_ dailyMaxSpeedChartData: [DailyMaxSpeed]) -> some View {
        let days = dailyMaxSpeedChartData.map(\.day)
        return Chart(dailyMaxSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.maxSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyMaxSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyCruiseSpeedChartBody(_ dailyCruiseSpeedChartData: [DailyCruiseSpeed]) -> some View {
        let days = dailyCruiseSpeedChartData.map(\.day)
        return Chart(dailyCruiseSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.cruiseSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyCruiseSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyMostCommonSpeedChartBody(_ dailyMostCommonSpeedChartData: [DailyMostCommonSpeed]) -> some View {
        let days = dailyMostCommonSpeedChartData.map(\.day)
        return Chart(dailyMostCommonSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.mostCommonSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyMostCommonSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyStopDurationChartBody(_ dailyStopDurationChartData: [DailyStopDuration]) -> some View {
        let days = dailyStopDurationChartData.map(\.day)
        return Chart(dailyStopDurationChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
            )
            .foregroundStyle(StatsChartTheme.stopDurationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyStopDurationChartData.map(\.durationHours).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.duration_hours"))
        .frame(height: 200)
    }

    private func dailyTripCountChartBody(_ dailyTripCountChartData: [DailyTripCount]) -> some View {
        let days = dailyTripCountChartData.map(\.day)
        return Chart(dailyTripCountChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.trips_count"), item.count)
            )
            .foregroundStyle(StatsChartTheme.tripCountBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: Double(dailyTripCountChartData.map(\.count).max() ?? 0))
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.trips_count"))
        .frame(height: 200)
    }

    private func dailyNightDistanceChartBody(_ dailyNightDistanceChartData: [DailyNightDistance]) -> some View {
        let days = dailyNightDistanceChartData.map(\.day)
        return Chart(dailyNightDistanceChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers)
            )
            .foregroundStyle(StatsChartTheme.nightDistanceBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyNightDistanceChartData.map(\.distanceKilometers).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.distance_km"))
        .frame(height: 200)
    }

    private func weekdayDistanceChartBody(_ weekdayChartData: [WeekdayDistance]) -> some View {
        let labels = weekdayChartData.map(\.label)
        return Chart(weekdayChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.weekday"), item.label),
                y: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers)
            )
            .foregroundStyle(StatsChartTheme.weekdayDistanceBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartXScale(domain: labels)
        .chartBarValueHeadroom(maxValue: weekdayChartData.map(\.distanceKilometers).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) {
                    chartAxisLabel(value.as(String.self) ?? "", slots: labels.count)
                }
            }
        }
        .chartStatsYAxisUnit(L10n.string("stats.chart.distance_km"))
        .frame(height: 200)
    }

    private func weekdayDurationChartBody(_ weekdayChartData: [WeekdayDuration]) -> some View {
        let labels = weekdayChartData.map(\.label)
        return Chart(weekdayChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.weekday"), item.label),
                y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
            )
            .foregroundStyle(StatsChartTheme.weekdayDurationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartXScale(domain: labels)
        .chartBarValueHeadroom(maxValue: weekdayChartData.map(\.durationHours).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) {
                    chartAxisLabel(value.as(String.self) ?? "", slots: labels.count)
                }
            }
        }
        .chartStatsYAxisUnit(L10n.string("stats.chart.duration_hours"))
        .frame(height: 200)
    }

    private func dailyFuelCostChartBody(_ dailyFuelCostChartData: [DailyFuelCost]) -> some View {
        let days = dailyFuelCostChartData.map(\.day)
        let avgLabel = L10n.string("stats.chart.fuel_avg")
        let estLabel = L10n.string("stats.chart.fuel_estimated")
        let avgColor = Color(red: 0.28, green: 0.78, blue: 0.86)
        let estColor = Color(red: 0.98, green: 0.58, blue: 0.24)
        let maxValue = dailyFuelCostChartData.map { max($0.cost, $0.dynamicCost) }.max() ?? 0

        return Chart {
            ForEach(dailyFuelCostChartData) { item in
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.fuel_cost"), item.cost)
                )
                .foregroundStyle(by: .value("series", avgLabel))
                .position(by: .value("series", avgLabel))
                .cornerRadius(StatsChartTheme.barCornerRadius)

                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.fuel_cost"), item.dynamicCost)
                )
                .foregroundStyle(by: .value("series", estLabel))
                .position(by: .value("series", estLabel))
                .cornerRadius(StatsChartTheme.barCornerRadius)
            }
        }
        .chartForegroundStyleScale([
            avgLabel: avgColor,
            estLabel: estColor
        ])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYScale(domain: [0, max(maxValue * 1.12, 1)])
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartStatsYAxisUnit(L10n.string("stats.chart.fuel_cost"))
        .frame(height: 200)
    }

    private func statsDonutLegendItem(
        id: String,
        name: String,
        durationStyle: Bool,
        domainKeys: [String],
        value: String
    ) -> StatsDonutLegendItem {
        StatsDonutLegendItem(
            id: id,
            name: name,
            color: StatsChartTheme.sliceColor(
                forStableKey: id,
                durationStyle: durationStyle,
                domainKeys: domainKeys,
                palette: shellPalette,
                scheme: colorScheme
            ),
            value: value
        )
    }

    private func chartSlicePalette(
        labels: [String],
        stableKeys: [String],
        durationStyle: Bool
    ) -> ([String], [Color]) {
        StatsChartTheme.sliceScale(
            labels: labels,
            stableKeys: stableKeys,
            durationStyle: durationStyle,
            palette: shellPalette,
            scheme: colorScheme
        )
    }

    private static let donutChartHeight: CGFloat = 150

    @ViewBuilder
    private func statsDonutPage<ChartContent: View>(
        titleKey: StaticString,
        centerTotal: String,
        legendItems: [StatsDonutLegendItem],
        helpTitle: String? = nil,
        helpBody: String? = nil,
        @ViewBuilder chart: () -> ChartContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let helpTitle, let helpBody {
                HStack {
                    Spacer(minLength: 0)
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody
                    )
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: StatsChartTheme.donutLegendTopPadding) {
                ZStack {
                    chart()
                        .frame(maxWidth: .infinity)
                        .statsHiddenDonutLegend(height: Self.donutChartHeight)

                    VStack(spacing: 2) {
                        Text(centerTotal)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .lineLimit(2)
                        Text(L10n.string("stats.cost.chart.center_total"))
                            .font(.caption2)
                            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    }
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
                }

                StatsDonutLegendGrid(items: legendItems)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel(titledWithScope(titleKey, scope: statsTripChartScopeLabel))
        // Keep content above the pager clip / page dots.
        .padding(.bottom, 2)
    }

    private func fuelFactorTitle(_ kind: FuelFactorKind) -> String {
        TripSummaryMetric.factorTitle(kind)
    }

    private func nightDayDonut() -> some View {
        let slices = [
            StatsMixSlice(
                id: "night",
                name: L10n.string("stats.night_driving"),
                value: snap.stats.nightDistanceMeters
            ),
            StatsMixSlice(
                id: "day",
                name: L10n.string("stats.daytime"),
                value: snap.stats.daytimeDistanceMeters
            )
        ].filter { $0.value > 0 }
        let names = slices.map(\.name)
        let keys = slices.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let totalMeters = slices.reduce(0) { $0 + $1.value }
        let legendItems = slices.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: DateFormatters.formatDistance(item.value)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.mix_night_day",
            centerTotal: DateFormatters.formatDistance(totalMeters),
            legendItems: legendItems
        ) {
            Chart(slices) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.value / 1000),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("stats.chart.mix_night_day"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func movingStopDonut() -> some View {
        let slices = [
            StatsMixSlice(
                id: "moving",
                name: L10n.string("stats.moving_duration"),
                value: snap.stats.movingDuration
            ),
            StatsMixSlice(
                id: "stopped",
                name: L10n.string("stats.stop_duration"),
                value: snap.stats.stopDuration
            )
        ].filter { $0.value > 0 }
        let names = slices.map(\.name)
        let keys = slices.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: true)
        let total = slices.reduce(0) { $0 + $1.value }
        let legendItems = slices.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: true,
                domainKeys: keys,
                value: DateFormatters.formatDuration(item.value)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.mix_moving_stop",
            centerTotal: DateFormatters.formatDuration(total),
            legendItems: legendItems
        ) {
            Chart(slices) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.value / 3600),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("stats.chart.mix_moving_stop"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func fuelFactorsDonut() -> some View {
        let shares = snap.stats.fuelFactorShares
        let names = shares.map { fuelFactorTitle($0.kind) }
        let keys = shares.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currencyElectric = snap.stats.fuelUnitIsElectric
        let totalVolume = shares.reduce(0) { $0 + $1.volume }
        let legendItems = zip(shares, names).map { item, name in
            statsDonutLegendItem(
                id: item.id,
                name: name,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatVolumeAmount(
                    item.volume,
                    isElectric: currencyElectric
                ) ?? "—"
            )
        }
        let centerTotal = FuelCostCalculator.formatVolumeAmount(
            totalVolume,
            isElectric: currencyElectric
        ) ?? "—"
        return statsDonutPage(
            titleKey: "stats.chart.mix_fuel_factors",
            centerTotal: centerTotal,
            legendItems: legendItems,
            helpTitle: L10n.fuelFactorsHelpTitle,
            helpBody: L10n.fuelFactorsHelpBody
        ) {
            Chart(shares) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.mix_fuel_factors"), item.volume),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("stats.chart.mix_fuel_factors"), fuelFactorTitle(item.kind)))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleDistanceDonut(data vehicleChartData: [VehicleDistance]) -> some View {
        let names = vehicleChartData.map(\.name)
        let keys = vehicleChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let totalMeters = vehicleChartData.reduce(0) { $0 + $1.distanceMeters }
        let legendItems = vehicleChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: DateFormatters.formatDistance(item.distanceMeters)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles",
            centerTotal: DateFormatters.formatDistance(totalMeters),
            legendItems: legendItems
        ) {
            Chart(vehicleChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleDurationDonut(data vehicleDurationChartData: [VehicleDuration]) -> some View {
        let names = vehicleDurationChartData.map(\.name)
        let keys = vehicleDurationChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: true)
        let totalDuration = vehicleDurationChartData.reduce(0) { $0 + $1.duration }
        let legendItems = vehicleDurationChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: true,
                domainKeys: keys,
                value: DateFormatters.formatDuration(item.duration)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles_duration",
            centerTotal: DateFormatters.formatDuration(totalDuration),
            legendItems: legendItems
        ) {
            Chart(vehicleDurationChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.durationHours),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryDistanceDonut(data categoryChartData: [CategoryDistance]) -> some View {
        let names = categoryChartData.map(\.name)
        let keys = categoryChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let totalMeters = categoryChartData.reduce(0) { $0 + $1.distanceMeters }
        let legendItems = categoryChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: DateFormatters.formatDistance(item.distanceMeters)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories",
            centerTotal: DateFormatters.formatDistance(totalMeters),
            legendItems: legendItems
        ) {
            Chart(categoryChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryDurationDonut(data categoryDurationChartData: [CategoryDuration]) -> some View {
        let names = categoryDurationChartData.map(\.name)
        let keys = categoryDurationChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: true)
        let totalDuration = categoryDurationChartData.reduce(0) { $0 + $1.duration }
        let legendItems = categoryDurationChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: true,
                domainKeys: keys,
                value: DateFormatters.formatDuration(item.duration)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories_duration",
            centerTotal: DateFormatters.formatDuration(totalDuration),
            legendItems: legendItems
        ) {
            Chart(categoryDurationChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.durationHours),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleFuelDonut(data vehicleFuelChartData: [VehicleFuelCost]) -> some View {
        let names = vehicleFuelChartData.map(\.name)
        let keys = vehicleFuelChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalCost = vehicleFuelChartData.reduce(0) { $0 + $1.cost }
        let legendItems = vehicleFuelChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.cost, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles_fuel",
            centerTotal: FuelCostCalculator.formatCost(totalCost, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(vehicleFuelChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.fuel_cost"), item.cost),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryFuelDonut(data categoryFuelChartData: [CategoryFuelCost]) -> some View {
        let names = categoryFuelChartData.map(\.name)
        let keys = categoryFuelChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalCost = categoryFuelChartData.reduce(0) { $0 + $1.cost }
        let legendItems = categoryFuelChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.cost, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories_fuel",
            centerTotal: FuelCostCalculator.formatCost(totalCost, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(categoryFuelChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.fuel_cost"), item.cost),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleExpensesDonut(data shares: [VehicleExpenseShare]) -> some View {
        let items = shares.filter { $0.amount > 0 }
        let names = items.map(\.displayName)
        let keys = items.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalAmount = items.reduce(0) { $0 + $1.amount }
        let legendItems = items.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.displayName,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.amount, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles_expenses",
            centerTotal: FuelCostCalculator.formatCost(totalAmount, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(items) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.daily_expenses"), item.amount),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.displayName))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryExpensesDonut(data breakdown: [VehicleCategoryCost]) -> some View {
        let items = breakdown.filter { $0.amount > 0 }
        let names = items.map(\.displayName)
        let keys = items.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalAmount = items.reduce(0) { $0 + $1.amount }
        let legendItems = items.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.displayName,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.amount, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories_expenses",
            centerTotal: FuelCostCalculator.formatCost(totalAmount, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(items) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.daily_expenses"), item.amount),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.displayName))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }
}

private struct StatsSnapshotInputs: Equatable {
    let storeVersion: Int
    let categoryCount: Int
    let vehicleCount: Int
    let placeCount: Int
    let journalCount: Int
    let period: StatsPeriod
    let customStart: Date
    let customEnd: Date
    let selectedMonth: Date
    let selectedCategoryID: String?
    let selectedVehicleID: UUID?
    let selectedPlaceID: UUID?
    let selectedPlaceName: String?
    let selectedJournalID: UUID?
}

private struct StatsSummaryMetricItem: Identifiable {
    let id: String
    let title: String
    let value: String
    var trend: StatsTrend? = nil
    var previousText: String? = nil
    var helpTitle: String? = nil
    var helpBody: String? = nil
}

private struct StatsMixSlice: Identifiable {
    let id: String
    let name: String
    let value: Double
}

private struct StatsSummaryGridAccessibility: ViewModifier {
    var isLoading: Bool

    func body(content: Content) -> some View {
        if isLoading {
            content.accessibilityLabel(L10n.statsSummaryLoading)
        } else {
            content
        }
    }
}

private enum StatsSection: String, CaseIterable, Hashable, Identifiable {
    case summary
    case daily
    case weekday
    case mix
    case vehicles
    case categories

    var id: String { rawValue }
}

private enum StatsFilterDefaults {
    static func selectedMonth(now: Date = Date()) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now
    }

    static func customStart(now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
    }
}

/// Title + truncated value + chevron; Menu picker keeps long names on one line.
private struct StatsFilterMenuField<MenuContent: View>: View {
    let title: String
    let value: String
    let isActive: Bool
    let identifier: String
    var avatarSystemImage: String?
    var avatarPhotoFileName: String?
    var avatarIsElectric: Bool
    let menuContent: MenuContent

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    init(
        title: String,
        value: String,
        isActive: Bool,
        identifier: String,
        avatarSystemImage: String? = nil,
        avatarPhotoFileName: String? = nil,
        avatarIsElectric: Bool = false,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self.value = value
        self.isActive = isActive
        self.identifier = identifier
        self.avatarSystemImage = avatarSystemImage
        self.avatarPhotoFileName = avatarPhotoFileName
        self.avatarIsElectric = avatarIsElectric
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            fieldLabel
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .buttonStyle(.glassPlainHit)
        .tint(GlassControlTint.link(for: colorScheme, palette: shellPalette))
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var fieldLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(fieldTitleInk)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let avatarSystemImage {
                    VehicleAvatarView(
                        systemImage: avatarSystemImage,
                        photoFileName: avatarPhotoFileName,
                        size: 14,
                        cornerRadius: 4,
                        isElectricAccent: avatarIsElectric,
                        showsSymbolPlate: false,
                        symbolFitsFrame: true
                    )
                    .accessibilityHidden(true)
                }

                Text(value)
                    .font(.caption.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(fieldInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(fieldTitleInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fieldFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldTint)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .transaction { $0.animation = nil }
    }

    private var fieldInk: Color {
        GlassText.primary(for: colorScheme)
    }

    private var fieldTitleInk: Color {
        GlassText.secondary(for: colorScheme)
    }

    private var fieldFill: Color {
        GlassTokens.fieldFill(for: colorScheme, palette: shellPalette)
    }

    private var fieldTint: Color {
        Color.clear
    }

    private var borderColor: Color {
        if isActive {
            return colorScheme == .dark
                ? shellPalette.tintColor(for: .dark).opacity(0.55)
                : Color.white.opacity(0.55)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.28)
    }
}

private extension View {
    func statsHiddenDonutLegend(height: CGFloat) -> some View {
        chartLegend(.hidden)
            .frame(height: height)
    }
}

#Preview {
    NavigationStack { StatsView() }
        .modelContainer(PreviewData.shared.container)
}
