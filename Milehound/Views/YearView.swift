import SwiftData
import SwiftUI

private enum YearListAnchor {
    static let badges = "year.badges.card"
}

private enum RecapSection: String, CaseIterable, Hashable, Identifiable {
    case awards
    case badges
    case routes
    case forecast
    case recap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awards: L10n.string("stats.awards.section")
        case .badges: L10n.string("premium.achievements.title")
        case .routes: L10n.string("premium.routes.title")
        case .forecast: L10n.string("premium.forecast.title")
        case .recap: L10n.tabYear
        }
    }
}

struct YearView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.milehoundLayout) private var layout
    @Bindable private var tabSelection = TabSelection.shared

    @State private var storeVersion = 0
    @State private var earliestTripStart: Date?
    @State private var hasCompletedTrip: Bool?
    @State private var hasExpense: Bool?
    @State private var forecastLoader: MonthCostForecastLoader?
    @State private var forecast: MonthCostForecast = .empty
    @State private var recapLoader: YearRecapSnapshotLoader?
    @State private var recapSnapshot: YearRecapSnapshot?
    @State private var achievements: [AchievementDisplay] = []
    @State private var routeAggregates: [FrequentRouteAggregate] = []
    @State private var expandModel = RecapExpandModel()
    @State private var showForecastDetail = false
    @State private var forecastCardFrame: CGRect = .zero
    @State private var showAchievements = false
    @State private var badgesCardFrame: CGRect = .zero
    @State private var showRoutesMap = false
    @State private var routesCardFrame: CGRect = .zero
    @State private var pendingRecapPlay = false
    @State private var pendingRecapPlayAfterPromo = false
    @State private var recapStorySession: RecapStorySession?
    @State private var recapPromoSession: RecapStorySession?
    @State private var unlockQueue: [AchievementDisplay] = []
    @State private var yearAwardsLoader: StatsYearAwardsLoader?
    @State private var yearAwards: StatsYearAwardsSnapshot?
    @State private var selectedAwardsYear = Calendar.current.component(.year, from: Date())
    @State private var yearAwardsRefreshTask: Task<Void, Never>?
    @State private var badgeScrollRequest = 0
    @State private var recapSectionTracker = StickySectionTracker<RecapSection>(
        order: RecapSection.allCases,
        initial: .awards
    )

    var body: some View {
        Group {
            if EmptyLibraryPolicy.showsInsightsShowcase(hasCompletedTrip: hasCompletedTrip, hasExpense: hasExpense) {
                recapShowcase
            } else {
                yearList
            }
        }
            .glassListChrome()
            .navigationTitle(L10n.tabYear)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: handleYearAppear)
            .onStoreSave(perform: handleYearStoreSave)
            .onDisappear {
                yearAwardsRefreshTask?.cancel()
                RecapCardExpandPresenter.shared.dismissImmediately()
            }
            .onChange(of: tabSelection.selectedTab) { _, tab in
                guard tab != .year else { return }
                RecapCardExpandPresenter.shared.dismissImmediately()
            }
            .onChange(of: selectedAwardsYear) { _, _ in
                scheduleYearAwardsRefresh(delayMilliseconds: 0)
            }
            .onChange(of: earliestTripStart) { _, _ in
                clampSelectedAwardsYear()
            }
            .onChange(of: tabSelection.pendingStatsAnchor) { _, _ in
                consumeYearDeepLink()
            }
            .onPreferenceChange(AchievementCardGlobalFrameKey.self) { frame in
                badgesCardFrame = frame
                expandModel.badgesAnchor = frame
            }
            .onPreferenceChange(FrequentRoutesCardGlobalFrameKey.self) { frame in
                routesCardFrame = frame
                expandModel.routesAnchor = frame
            }
            .onPreferenceChange(StatsForecastCardGlobalFrameKey.self) { frame in
                forecastCardFrame = frame
                expandModel.forecastAnchor = frame
            }
            .onChange(of: settings.fuelCurrency) { _, currency in
                expandModel.currencyCode = currency.rawValue
            }
            .fullScreenCover(item: $recapStorySession) { session in
                YearRecapStoryView(snapshot: session.snapshot, startPage: session.startPage) {
                    markRecapSeen()
                    recapStorySession = nil
                }
                .onAppear { RecapStoryOrientation.refreshIfLocked() }
                .interactiveDismissDisabled()
            }
            .fullScreenCover(item: $recapPromoSession) { session in
                YearRecapPromoView(
                    snapshot: session.snapshot,
                    onPlay: { playRecapAfterPromo(session.snapshot) },
                    onClose: { dismissRecapPromo(year: session.snapshot.year) }
                )
                .onAppear { RecapStoryOrientation.refreshIfLocked() }
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
            }
            .onAppear { syncRecapStoryOrientation() }
            .onChange(of: recapStorySession?.id) { _, _ in
                syncRecapStoryOrientation()
            }
            .onChange(of: recapPromoSession?.id) { _, _ in
                syncRecapStoryOrientation()
            }
            .onChange(of: recapPromoSession?.id) { _, newID in
                guard newID == nil, pendingRecapPlayAfterPromo else { return }
                pendingRecapPlayAfterPromo = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    openRecapStory()
                }
            }
            .overlay {
                achievementUnlockOverlay
            }
    }

    @ViewBuilder
    private var yearList: some View {
        if pairsWideCards {
            ScrollView {
                MilehoundHingeCardStack {
                    wideRecapCard(.awards) {
                        yearAwardsCard
                            .glassCard(
                                cornerRadius: StatsCardTokens.radius,
                                contentInset: StatsCardTokens.contentInset
                            )
                    }
                    wideRecapCard(.badges) {
                        badgesCard
                            .glassCard(
                                cornerRadius: StatsCardTokens.radius,
                                contentInset: StatsCardTokens.contentInset
                            )
                    }
                    wideRecapCard(.routes) {
                        routesCard
                            .glassCard(
                                cornerRadius: StatsCardTokens.radius,
                                contentInset: StatsCardTokens.contentInset
                            )
                    }
                    wideRecapCard(.forecast) {
                        forecastCard
                            .glassCard(cornerRadius: StatsCardTokens.radius, contentInset: 0)
                    }
                    wideRecapCard(.recap) {
                        recapCard
                    }
                }
                .padding(16)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if layout.packsPortraitRecapHalves {
                        portraitRecapHubGrid
                    } else {
                        recapPinnedSection(.awards, title: RecapSection.awards.title) {
                            yearAwardsCard
                        }
                        recapPinnedSection(.badges, title: RecapSection.badges.title, trailing: { badgesExpandButton }) {
                            badgesCard
                        }
                        recapPinnedSection(.routes, title: RecapSection.routes.title, trailing: { routesExpandButton }) {
                            routesCard
                        }
                        recapPinnedSection(
                            .forecast,
                            title: RecapSection.forecast.title,
                            contentInset: 0,
                            trailing: { forecastExpandButton }
                        ) {
                            forecastCard
                        }
                    }
                    recapPinnedSection(.recap, title: RecapSection.recap.title, applyCard: false) {
                        recapCard
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, GlassTokens.panelHorizontalInset)
                .padding(.bottom, 8)
            }
            .glassCollapsingScroll()
            .scrollPosition(id: recapScrollPosition, anchor: .top)
            .onChange(of: badgeScrollRequest) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    recapSectionTracker.beginTapScroll(to: .badges)
                    recapSectionTracker.endTapScroll()
                }
            }
        }
    }

    private var recapScrollPosition: Binding<RecapSection?> {
        Binding(
            get: { recapSectionTracker.visibleSection },
            set: { recapSectionTracker.applyScrollPosition($0) }
        )
    }

    @ViewBuilder
    private func recapPinnedSection<Content: View>(
        _ section: RecapSection,
        title: String,
        contentInset: CGFloat = StatsCardTokens.contentInset,
        applyCard: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        recapPinnedSection(
            section,
            title: title,
            contentInset: contentInset,
            applyCard: applyCard,
            trailing: { EmptyView() },
            content: content
        )
    }

    @ViewBuilder
    private func recapPinnedSection<Content: View, Trailing: View>(
        _ section: RecapSection,
        title: String,
        contentInset: CGFloat = StatsCardTokens.contentInset,
        applyCard: Bool = true,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCollapsingCard(
            title: title,
            accessibilityIdentifier: "recap.section.\(section.rawValue)",
            contentInset: contentInset,
            applyCard: applyCard,
            trailing: trailing,
            content: content
        )
        .id(section)
    }

    /// Open book, a wide landscape phone, and iPad landscape. Cards pack down whichever side is shorter.
    private var pairsWideCards: Bool {
        layout.usesWidePanes
    }

    private func wideRecapCard<Content: View>(
        _ section: RecapSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recap.section.\(section.rawValue)")
    }

    /// Equal columns that pack from the top. A short Badges card must not leave
    /// a hole above This month’s forecast.
    private var portraitRecapHubGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                recapPinnedSection(.awards, title: RecapSection.awards.title) {
                    yearAwardsCard
                }
                recapPinnedSection(.routes, title: RecapSection.routes.title, trailing: { routesExpandButton }) {
                    routesCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            VStack(spacing: 12) {
                recapPinnedSection(.badges, title: RecapSection.badges.title, trailing: { badgesExpandButton }) {
                    badgesCard
                }
                recapPinnedSection(
                    .forecast,
                    title: RecapSection.forecast.title,
                    contentInset: 0,
                    trailing: { forecastExpandButton }
                ) {
                    forecastCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var yearAwardsCard: some View {
        StatsYearAwardsCard(
            snapshot: yearAwards,
            medals: yearAwardsMedals,
            years: awardsYears,
            selectedYear: $selectedAwardsYear,
            reduceMotion: reduceMotion,
            showsYearPicker: true,
            showsSectionTitle: pairsWideCards,
            onAppear: {
                scheduleYearAwardsRefresh(delayMilliseconds: 0)
            }
        )
    }

    private var badgesCard: some View {
        StatsAchievementsStrip(
            achievements: achievements,
            isExpanded: showAchievements,
            showsTitle: pairsWideCards,
            showsExpandControl: pairsWideCards,
            onOpen: openAchievements
        )
        .id(YearListAnchor.badges)
        .glassMorphPanelSource(isHidden: showAchievements)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AchievementCardGlobalFrameKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
    }

    private var routesCard: some View {
        FrequentRoutesPreviewCard(
            aggregates: routeAggregates,
            isExpanded: showRoutesMap,
            showsTitle: pairsWideCards,
            showsExpandControl: pairsWideCards,
            onOpen: openRoutesMap
        )
        .glassMorphPanelSource(isHidden: showRoutesMap)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FrequentRoutesCardGlobalFrameKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
    }

    private var badgesExpandButton: some View {
        recapCornerExpandButton(
            identifier: "stats.premium.achievements",
            hidden: showAchievements,
            action: openAchievements
        )
    }

    private var routesExpandButton: some View {
        recapCornerExpandButton(
            identifier: "stats.premium.routes",
            hidden: showRoutesMap,
            action: openRoutesMap
        )
    }

    private var forecastExpandButton: some View {
        recapCornerExpandButton(
            identifier: "stats.premium.forecast.expand",
            hidden: showForecastDetail,
            action: openForecastDetail
        )
        .accessibilityHidden(true)
    }

    private func recapCornerExpandButton(
        identifier: String,
        hidden: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(L10n.mapFullscreen)
        .accessibilityIdentifier(identifier)
        .glassMorphPanelSource(isHidden: hidden)
        .allowsHitTesting(!hidden)
    }

    private var forecastCard: some View {
        StatsForecastCard(
            forecast: forecast,
            currencyCode: settings.fuelCurrency.rawValue,
            isExpanded: showForecastDetail,
            showsTitle: pairsWideCards,
            showsExpandControl: pairsWideCards,
            onOpen: openForecastDetail
        )
        .glassMorphPanelSource(isHidden: showForecastDetail)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StatsForecastCardGlobalFrameKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
    }

    private var recapCard: some View {
        YearRecapHubCard(
            snapshot: recapSnapshot ?? .empty(year: RecapYearPolicy.displayYear()),
            onPlay: { openRecapStory() },
            onPlayPage: { openRecapStory(at: $0) }
        )
    }

    @ViewBuilder
    private var achievementUnlockOverlay: some View {
        ZStack {
            if let item = unlockQueue.first {
                Color.black.opacity(0.28).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        advanceUnlockQueue(from: item)
                    }
                AchievementUnlockOverlay(item: item) {
                    advanceUnlockQueue(from: item)
                }
                .id(item.id)
                .transition(MilehoundMotion.badgeUnlockCardTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(MilehoundMotion.badgeUnlock(reduceMotion: reduceMotion), value: unlockQueue.first?.id)
        .allowsHitTesting(unlockQueue.first != nil)
    }

    private var awardsYears: [Int] {
        StatsViewModel.selectableYears(earliestTripStart: earliestTripStart)
    }

    private var yearAwardsMedals: [StatsYearAward] {
        guard let yearAwards else { return [] }
        return StatsYearAwardsPresenter.medals(
            from: yearAwards,
            goalMetersForMonth: { settings.goalMeters(forMonthContaining: $0) },
            currencyCode: settings.fuelCurrency.rawValue
        )
    }

    private func handleYearAppear() {
        if forecastLoader == nil {
            forecastLoader = MonthCostForecastLoader(modelContainer: modelContext.container)
        }
        if recapLoader == nil {
            recapLoader = YearRecapSnapshotLoader(modelContainer: modelContext.container)
        }
        if recapSnapshot == nil {
            recapSnapshot = YearRecapCache.load(year: RecapYearPolicy.displayYear())
        }
        refreshEarliestTripStart()
        schedulePremiumRefresh()
        scheduleYearAwardsRefresh(delayMilliseconds: 0)
        consumeYearDeepLink()
    }

    private func handleYearStoreSave() {
        refreshEarliestTripStart()
        storeVersion &+= 1
        schedulePremiumRefresh()
        scheduleYearAwardsRefresh(delayMilliseconds: 0)
    }

    private func schedulePremiumRefresh() {
        let forecastActor = forecastLoader ?? MonthCostForecastLoader(modelContainer: modelContext.container)
        if forecastLoader == nil { forecastLoader = forecastActor }
        let recapActor = recapLoader ?? YearRecapSnapshotLoader(modelContainer: modelContext.container)
        if recapLoader == nil { recapLoader = recapActor }
        let year = RecapYearPolicy.displayYear()
        let version = storeVersion
        let request = MonthCostForecastRequest(
            storeVersion: version,
            selectedVehicleID: nil,
            now: Date()
        )
        Task {
            let builtRecap = await recapActor.snapshot(year: year, storeVersion: version)
            await MainActor.run {
                recapSnapshot = builtRecap
                if pendingRecapPlay {
                    pendingRecapPlay = false
                    if RecapYearPolicy.shouldPresent(builtRecap) {
                        recapStorySession = RecapStorySession(snapshot: builtRecap)
                    }
                } else {
                    maybePresentRecapPromo()
                }
            }
        }
        Task {
            let builtForecast = await forecastActor.forecast(for: request)
            await MainActor.run {
                forecast = builtForecast
                if !UITestSupport.isEnabled {
                    _ = AchievementEvaluator.replayUnlockCelebrationsIfNeeded(in: modelContext)
                }
                achievements = AchievementEvaluator.displays(in: modelContext)
                routeAggregates = FrequentRouteAggregateService.topAggregates(in: modelContext)
                syncExpandModel()
                let pending = achievements.filter(\.needsCelebration)
                unlockQueue = AchievementUnlockQueue.merging(queued: unlockQueue, pending: pending)
                PremiumWidgetBridge.sync(in: modelContext, forecast: builtForecast)
            }
        }
    }

    private func scheduleYearAwardsRefresh(delayMilliseconds: Int) {
        yearAwardsRefreshTask?.cancel()
        let loader = yearAwardsLoader ?? StatsYearAwardsLoader(modelContainer: modelContext.container)
        if yearAwardsLoader == nil {
            yearAwardsLoader = loader
        }
        clampSelectedAwardsYear()
        let request = StatsYearAwardsRequest(storeVersion: storeVersion, year: selectedAwardsYear)
        yearAwardsRefreshTask = Task {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                yearAwards = built
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
        hasCompletedTrip = earliestTripStart != nil
        hasExpense = ((try? modelContext.fetchCount(FetchDescriptor<VehicleExpense>())) ?? 0) > 0
    }

    private var recapShowcase: some View {
        GlassShowcasePane { size in
            GlassShowcaseEmptyState(
                emblem: .symbol("trophy.fill"),
                title: L10n.emptyRecapTitle,
                message: L10n.emptyRecapMessage,
                highlights: [
                    GlassShowcaseHighlight(systemImage: "medal.fill", title: L10n.emptyRecapHighlightAwards),
                    GlassShowcaseHighlight(systemImage: "seal.fill", title: L10n.string("premium.achievements.title")),
                    GlassShowcaseHighlight(
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill",
                        title: L10n.emptyRecapHighlightRoutes
                    )
                ],
                available: size,
                accessibilityIdentifier: "recap.empty"
            ) {
                Button {
                    tabSelection.openTrips()
                } label: {
                    Label(L10n.emptyGoTrips, systemImage: "car.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .milehoundGlassButton()
                .accessibilityIdentifier("recap.empty.goTrips")
            }
        }
    }

    private func clampSelectedAwardsYear() {
        let years = awardsYears
        if !years.contains(selectedAwardsYear) {
            selectedAwardsYear = years.first ?? Calendar.current.component(.year, from: Date())
        }
    }

    private func openAchievements() {
        presentRecapCard(.achievements, sourceHidden: $showAchievements, anchor: badgesCardFrame, startsShown: false)
    }

    /// Notification opens the badges page already grown. Close still shrinks toward the card.
    private func openAchievementsFromNotification() {
        guard !showAchievements, RecapCardExpandPresenter.shared.presentation == nil else { return }
        presentRecapCard(.achievements, sourceHidden: $showAchievements, anchor: badgesCardFrame, startsShown: true)
        badgeScrollRequest += 1
    }

    private func openRoutesMap() {
        presentRecapCard(.routes, sourceHidden: $showRoutesMap, anchor: routesCardFrame, startsShown: false)
    }

    private func openForecastDetail() {
        presentRecapCard(.forecast, sourceHidden: $showForecastDetail, anchor: forecastCardFrame, startsShown: false)
    }

    /// The card dissolves, then the root shell grows with the glass-panel motion.
    private func presentRecapCard(
        _ kind: RecapCardExpandKind,
        sourceHidden: Binding<Bool>,
        anchor: CGRect,
        startsShown: Bool
    ) {
        guard !sourceHidden.wrappedValue else { return }
        guard RecapCardExpandPresenter.shared.presentation == nil else { return }
        MilehoundHaptics.selection()
        syncExpandModel()
        let motion = reduceMotion
        withAnimation(MilehoundMotion.glassPanelSourceDissolve(reduceMotion: motion)) {
            sourceHidden.wrappedValue = true
        }
        RecapCardExpandPresenter.shared.present(
            kind: kind,
            anchor: anchor,
            startsShown: startsShown,
            model: expandModel,
            onWillDismiss: {
                withAnimation(MilehoundMotion.glassPanelSourceDissolve(reduceMotion: motion)) {
                    sourceHidden.wrappedValue = false
                }
            },
            onDismissed: {
                sourceHidden.wrappedValue = false
            }
        )
    }

    private func consumeYearDeepLink() {
        guard let pending = tabSelection.pendingStatsAnchor else { return }
        switch pending {
        case .goal:
            return
        case .forecast, .recap, .routes, .achievements:
            break
        }
        guard let anchor = tabSelection.consumePendingStatsAnchor() else { return }
        switch anchor {
        case .goal:
            break
        case .forecast:
            openForecastDetail()
        case .recap:
            playRecapWhenReady()
        case .routes:
            openRoutesMap()
        case .achievements:
            openAchievementsFromNotification()
        }
    }

    private func playRecapWhenReady() {
        if RecapYearPolicy.shouldPresent(recapSnapshot) {
            openRecapStory()
            return
        }
        pendingRecapPlay = true
        schedulePremiumRefresh()
    }

    private func syncRecapStoryOrientation() {
        let visible = recapStorySession != nil || recapPromoSession != nil
        RecapStoryOrientation.setCoverVisible(visible, layoutClass: layout.layoutClass)
    }

    private func openRecapStory(at page: RecapStoryPage? = nil) {
        guard let recapSnapshot, recapSnapshot.hasData else { return }
        recapStorySession = RecapStorySession(snapshot: recapSnapshot, startPage: page)
    }

    private func markRecapSeen() {
        let year = RecapYearPolicy.displayYear()
        RecapNotificationScheduler.noteRecapConsumed(year: year)
    }

    private func dismissRecapPromo(year: Int) {
        RecapPromoPolicy.noteDismissed(year: year)
        recapPromoSession = nil
    }

    private func playRecapAfterPromo(_ snapshot: YearRecapSnapshot) {
        RecapPromoPolicy.noteDismissed(year: snapshot.year)
        pendingRecapPlayAfterPromo = true
        recapPromoSession = nil
    }

    private func maybePresentRecapPromo() {
        guard recapStorySession == nil, recapPromoSession == nil else { return }
        guard !UITestSupport.isEnabled, !UITestSupport.isUnitTesting else { return }
        guard RecapYearPolicy.shouldPresent(recapSnapshot), let recapSnapshot else { return }
        let year = RecapYearPolicy.displayYear()
        let defaults = UserDefaults.standard
        let dismissed = defaults.bool(forKey: RecapPromoPolicy.dismissedKey(for: year))
        let catchUpPresented = defaults.bool(forKey: RecapPromoPolicy.catchUpPresentedKey(for: year))
        guard RecapPromoPolicy.shouldPresent(
            hasData: true,
            dismissed: dismissed,
            catchUpPresented: catchUpPresented,
            recapYear: year
        ) else { return }
        if !RecapPromoPolicy.isWithinWindow(recapYear: year) {
            RecapPromoPolicy.noteCatchUpPresented(year: year)
        }
        recapPromoSession = RecapStorySession(snapshot: recapSnapshot)
    }

    private func advanceUnlockQueue(from item: AchievementDisplay) {
        guard unlockQueue.contains(where: { $0.id == item.id }) else { return }
        AchievementEvaluator.markSeen([item.id], in: modelContext)
        withAnimation(MilehoundMotion.badgeUnlock(reduceMotion: reduceMotion)) {
            unlockQueue.removeAll { $0.id == item.id }
        }
        try? modelContext.save()
        achievements = AchievementEvaluator.displays(in: modelContext)
        syncExpandModel()
    }

    private func syncExpandModel() {
        expandModel.achievements = achievements
        expandModel.routeAggregates = routeAggregates
        expandModel.forecast = forecast
        expandModel.currencyCode = settings.fuelCurrency.rawValue
        expandModel.badgesAnchor = badgesCardFrame
        expandModel.routesAnchor = routesCardFrame
        expandModel.forecastAnchor = forecastCardFrame
    }
}
