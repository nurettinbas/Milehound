import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

enum TravelJournalPanelDetent: Equatable {
    case compact
    case expanded
}

/// Resting travel-detail sheet is a compact summary so the map stays the hero.
/// Drag snaps between compact and a list detent that still leaves a map peek.
enum TravelJournalPanelLayout {
    static let compactHeightFraction: CGFloat = 0.32
    static let expandedHeightFraction: CGFloat = 0.72
    static let compactMinimum: CGFloat = 292
    static let rubberBand: CGFloat = 28

    static func compactHeight(
        containerHeight: CGFloat,
        fraction: CGFloat = compactHeightFraction,
        minimum: CGFloat = compactMinimum
    ) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let preferred = containerHeight * fraction
        let ceiling = containerHeight * 0.40
        return min(max(preferred, minimum), ceiling)
    }

    static func expandedHeight(
        containerHeight: CGFloat,
        mapPeek: CGFloat,
        fraction: CGFloat = expandedHeightFraction
    ) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let preferred = containerHeight * fraction
        let capped = max(0, containerHeight - max(mapPeek, 0))
        return min(preferred, capped)
    }

    static func height(
        for detent: TravelJournalPanelDetent,
        containerHeight: CGFloat,
        mapPeek: CGFloat,
        compactFraction: CGFloat = compactHeightFraction,
        compactFloor: CGFloat = compactMinimum,
        expandedFraction: CGFloat = expandedHeightFraction
    ) -> CGFloat {
        switch detent {
        case .compact:
            return compactHeight(
                containerHeight: containerHeight,
                fraction: compactFraction,
                minimum: compactFloor
            )
        case .expanded:
            return expandedHeight(
                containerHeight: containerHeight,
                mapPeek: mapPeek,
                fraction: expandedFraction
            )
        }
    }

    /// `translation` is SwiftUI drag translation: positive Y shrinks the bottom sheet.
    static func draggedHeight(
        detent: TravelJournalPanelDetent,
        translation: CGFloat,
        containerHeight: CGFloat,
        mapPeek: CGFloat,
        compactFraction: CGFloat = compactHeightFraction,
        compactFloor: CGFloat = compactMinimum,
        expandedFraction: CGFloat = expandedHeightFraction
    ) -> CGFloat {
        let compact = compactHeight(
            containerHeight: containerHeight,
            fraction: compactFraction,
            minimum: compactFloor
        )
        let expanded = expandedHeight(
            containerHeight: containerHeight,
            mapPeek: mapPeek,
            fraction: expandedFraction
        )
        let base = height(
            for: detent,
            containerHeight: containerHeight,
            mapPeek: mapPeek,
            compactFraction: compactFraction,
            compactFloor: compactFloor,
            expandedFraction: expandedFraction
        )
        return clampedHeight(base - translation, compact: compact, expanded: expanded)
    }

    static func clampedHeight(_ height: CGFloat, compact: CGFloat, expanded: CGFloat) -> CGFloat {
        min(max(height, compact - rubberBand), expanded + rubberBand)
    }

    static func snappedDetent(
        predictedTranslation: CGFloat,
        from detent: TravelJournalPanelDetent,
        containerHeight: CGFloat,
        mapPeek: CGFloat,
        compactFraction: CGFloat = compactHeightFraction,
        compactFloor: CGFloat = compactMinimum,
        expandedFraction: CGFloat = expandedHeightFraction
    ) -> TravelJournalPanelDetent {
        let compact = compactHeight(
            containerHeight: containerHeight,
            fraction: compactFraction,
            minimum: compactFloor
        )
        let expanded = expandedHeight(
            containerHeight: containerHeight,
            mapPeek: mapPeek,
            fraction: expandedFraction
        )
        let base = height(
            for: detent,
            containerHeight: containerHeight,
            mapPeek: mapPeek,
            compactFraction: compactFraction,
            compactFloor: compactFloor,
            expandedFraction: expandedFraction
        )
        let projected = clampedHeight(base - predictedTranslation, compact: compact, expanded: expanded)
        let mid = (compact + expanded) / 2
        if predictedTranslation < -240 { return .expanded }
        if predictedTranslation > 240 { return .compact }
        return projected >= mid ? .expanded : .compact
    }
}

/// Split landscape frames the route in the trailing pane. A bottom sheet still
/// shortens the phone and the narrow landscape card.
enum TravelJournalMapFit {
    static func padding(
        style: TripDetailStyle,
        mapExpanded: Bool,
        mapSize: CGSize,
        topChrome: CGFloat,
        bottomChrome: CGFloat,
        sheetHeight: CGFloat,
        trailingCover: CGFloat,
        homeIndicator: CGFloat,
        coverCardWidth: CGFloat = 0,
        coverCardHeight: CGFloat = 0,
        coverCardIsTrailing: Bool = true
    ) -> UIEdgeInsets {
        if coverCardWidth > 0, !mapExpanded {
            let horizontal = max(mapSize.width * 0.06, 16)
            let cardSide = coverCardWidth + GlassTokens.TravelCornerCardMetrics.tabGap
            let top = max(topChrome, 54)
            let bottom = max(coverCardHeight, 0) + GlassTokens.panelHorizontalInset + max(homeIndicator, 12)
            let leading = horizontal + (coverCardIsTrailing ? 0 : cardSide)
            let trailing = horizontal + (coverCardIsTrailing ? cardSide : 0) + max(trailingCover, 0)
            return UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
        }
        if style == .split, !mapExpanded {
            return TripDetailMapFraming.edgeInsets(
                TripDetailMapFraming.Input(
                    posture: .duoSplit,
                    mapSize: mapSize,
                    topChrome: topChrome,
                    bottomCardHeight: 0,
                    trailingCover: trailingCover,
                    leadingInset: 0,
                    homeIndicator: homeIndicator
                )
            )
        }
        let horizontal = max(mapSize.width * 0.06, 16)
        if mapExpanded {
            let top = max(topChrome, 96)
            let bottom = max(bottomChrome, 83) + 16
            return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
        }
        let top = max(topChrome, 96)
        let bottom = max(sheetHeight, 0) + 24
        return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
    }
}

struct TravelJournalDetailView: View {
    @Bindable var journal: TravelJournal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Query private var places: [SavedPlace]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cameraBox = TripDetailMapCameraBox()
    @State private var selectedTripID: UUID?
    @State private var overlays: [TravelJournalRouteOverlay] = []
    @State private var selectedSegments: [TripDetailRevealedRouteSegment] = []
    @State private var fitCoordinates: [CLLocationCoordinate2D] = []
    @State private var isMapExpanded = false
    @State private var isMapExpandTransitioning = false
    @State private var panelDetent: TravelJournalPanelDetent = .compact
    @State private var dragTranslation: CGFloat = 0
    @State private var panelRisen = false
    @State private var editorDraft: TravelJournalEditorDraft?
    @State private var mapStyleOverride: TripDetailMapStyle?
    @State private var mapViewportSize: CGSize = CGSize(width: 390, height: 844)
    @State private var mapTopChromePoints: CGFloat = 96
    @State private var mapBottomChromePoints: CGFloat = 83
    @State private var mapTrailingInset: CGFloat = 0
    @State private var mapHomeIndicator: CGFloat = 0
    @State private var mapRefitTask: Task<Void, Never>?
    @Environment(\.milehoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var journalPanelCollapsed = false
    @State private var cornerCardExpanded = false
    @State private var coverCardMeasuredHeight: CGFloat = 0
    @State private var coverExpandedLimit: CGFloat = 0
    @State private var coverHeaderBottom: CGFloat?

    private var members: [Trip] {
        journal.trips.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    private var mapStyle: TripDetailMapStyle {
        mapStyleOverride ?? .matching(colorScheme)
    }

    private var panelVisible: Bool { panelRisen && !isMapExpanded }

    /// The split column already leads with the travel title.
    private var showsNavTitle: Bool { layout.tripDetailStyle != .split }

    var body: some View {
        mapRoot
            .ignoresSafeArea(edges: .bottom)
            .glassNavigationChrome()
            .glassMapTopEdgeHidden()
            .navigationTitle(showsNavTitle ? journal.title : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .glassDetailBackNavigation(action: dismiss.callAsFunction)
            .toolbar {
                if showsNavTitle {
                    GlassToolbarNavTitleItem(title: journal.title)
                }
                mapExpandToolbar
            }
            .sheet(item: $editorDraft) { draft in
                TravelJournalEditorSheet(draft: draft)
            }
            .task(id: journal.id) {
                await playPanelEntrance()
            }
            .onChange(of: selectedTripID) { _, _ in
                Task { await loadRoutes() }
            }
            .onChange(of: journal.tripCount) { _, _ in
                Task { await loadRoutes() }
            }
            .onChange(of: panelDetent) { _, _ in
                scheduleMapRefit(delayMilliseconds: 120)
            }
            .onChange(of: cornerCardExpanded) { _, _ in
                scheduleMapRefit(delayMilliseconds: 120)
            }
    }

    private var mapRoot: some View {
        ZStack {
            AtmosphericBackground()
            GeometryReader { geometry in
                mapAndPanel(in: geometry)
            }
        }
    }

    private var mapExpandIconName: String {
        isMapExpanded
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
    }

    private var mapExpandAccessibilityLabel: String {
        isMapExpanded
            ? L10n.string("journal.map.collapse")
            : L10n.string("journal.map.expand")
    }

    @ToolbarContentBuilder
    private var mapExpandToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            GlassToolbarCircleButton(
                systemName: mapExpandIconName,
                action: toggleMapExpanded
            )
            .accessibilityLabel(mapExpandAccessibilityLabel)
        }
        .hideSharedToolbarBackgroundIfAvailable()
    }

    @ViewBuilder
    private func mapAndPanel(in geometry: GeometryProxy) -> some View {
        let mapPeek = mapTopChromePoints + 24
        let panelHeight = livePanelHeight(
            containerHeight: geometry.size.height,
            mapPeek: mapPeek
        )
        if layout.tripDetailStyle == .split {
            if isMapExpanded {
                journalMap
                    .ignoresSafeArea()
                    .background { mapSizeReader }
            } else {
                MilehoundPaneSplit(
                    leadingFillsVertically: true,
                    focusFillsVertically: true,
                    focusBleedsTrailing: true
                ) {
                    journalColumn(in: geometry)
                } focus: {
                    journalMap
                        .ignoresSafeArea()
                        .background { mapSizeReader }
                }
            }
        } else if layout.isClosedCoverLandscape {
            coverCornerMap(in: geometry)
        } else if layout.tripDetailStyle == .floatingPanel {
            MilehoundMapCanvas(panelCollapsed: $journalPanelCollapsed) {
                TravelJournalMapLayer(
                    style: mapStyle,
                    overlays: overlays,
                    selectedSegments: selectedSegments,
                    cameraBox: cameraBox
                )
            } panel: {
                editPanel(height: geometry.size.height, mapPeek: mapPeek, containerHeight: geometry.size.height, embedded: true)
            }
        } else if layout.tripDetailStyle == .stacked {
            VStack(spacing: 0) {
                TravelJournalMapLayer(
                    style: mapStyle,
                    overlays: overlays,
                    selectedSegments: selectedSegments,
                    cameraBox: cameraBox
                )
                .frame(height: geometry.size.height * 0.55)
                editPanel(
                    height: geometry.size.height * 0.45,
                    mapPeek: mapPeek,
                    containerHeight: geometry.size.height,
                    embedded: true
                )
            }
        } else {
            ZStack(alignment: .bottom) {
                TravelJournalMapLayer(
                    style: mapStyle,
                    overlays: overlays,
                    selectedSegments: selectedSegments,
                    cameraBox: cameraBox
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                editPanel(
                    height: panelHeight,
                    mapPeek: mapPeek,
                    containerHeight: geometry.size.height,
                    leadingInset: sheetLeadingInset(in: geometry)
                )
            }
            .onAppear {
                refreshMapChromeInsets(from: geometry)
            }
            .onChange(of: geometry.size) { _, _ in
                refreshMapChromeInsets(from: geometry)
                scheduleMapRefit(animated: false)
            }
        }
    }

    private var journalMap: some View {
        TravelJournalMapLayer(
            style: mapStyle,
            overlays: overlays,
            selectedSegments: selectedSegments,
            cameraBox: cameraBox
        )
    }

    /// Closed cover, landscape. Same pull-up sheet as the phone, at the corner width.
    /// It arrives as the summary. Pulling the grabber up lists the trips and can fill the screen.
    private func coverCornerMap(in geometry: GeometryProxy) -> some View {
        let anchorsTrailing = layoutDirection != .rightToLeft
        let width = GlassTokens.TravelCornerCardMetrics.compactWidth(screenWidth: geometry.size.width)
        let safe = geometry.safeAreaInsets
        // The card ends on the home-indicator inset, level with the bottom of the punch hole
        // under the side tab. With the camera at the top, it ends level with the side tab.
        let homeInset = max(safe.bottom, windowSafeInsets.bottom, 12)
        let bottomInset: CGFloat = {
            let chrome = SideColumnChromeState.shared
            guard let icons = chrome.tabBarFrame,
                  SideColumnChromeResolver.isSideTabBar(icons) else { return homeInset }
            let tab = chrome.sidePillFrame ?? icons
            let tabGap = geometry.frame(in: .global).maxY - tab.maxY
            guard tabGap > 0 else { return homeInset }
            return min(homeInset, tabGap)
        }()
        // Expanded stops just under the navigation bar. The bar is measured in the window,
        // because this reader's top inset does not match where the bar ends on the cover.
        let headerBottom = coverHeaderBottom.map { max($0 - geometry.frame(in: .global).minY, 0) } ?? safe.top
        let topLimit = headerBottom + 8
        let compactCard = coverCompactHeight
        let expandedHeight = max(compactCard + 1, geometry.size.height - topLimit - bottomInset)
        let dragging = abs(dragTranslation) > 0.5
        let base = cornerCardExpanded ? expandedHeight : compactCard
        let liveHeight = min(
            max(base - dragTranslation, compactCard - TravelJournalPanelLayout.rubberBand),
            expandedHeight + TravelJournalPanelLayout.rubberBand
        )
        let card = coverCornerCard
            .frame(width: width, height: liveHeight, alignment: .top)
            .padding(.bottom, bottomInset)
            .padding(.trailing, anchorsTrailing ? GlassTokens.TravelCornerCardMetrics.tabGap : 0)
            .padding(.leading, anchorsTrailing ? 0 : GlassTokens.TravelCornerCardMetrics.tabGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchorsTrailing ? .bottomTrailing : .bottomLeading)
            .offset(y: panelRisen ? 0 : 28)
            .opacity(panelRisen && !isMapExpanded ? 1 : 0)
            .animation(reduceMotion ? nil : MilehoundMotion.sheetRise, value: panelRisen)
            .animation(reduceMotion || dragging ? nil : MilehoundMotion.sheetRise, value: cornerCardExpanded)
            .animation(reduceMotion ? nil : mapExpandAnimation, value: isMapExpanded)
            .allowsHitTesting(panelVisible && !isMapExpanded)

        return ZStack {
            journalMap
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { mapSizeReader }
            card
        }
        .onAppear {
            coverExpandedLimit = expandedHeight
            refreshMapChromeInsets(from: geometry)
            measureCoverHeader()
        }
        .onChange(of: geometry.size) { _, _ in
            coverExpandedLimit = expandedHeight
            refreshMapChromeInsets(from: geometry)
            scheduleMapRefit(animated: false)
            measureCoverHeader()
        }
        .onChange(of: expandedHeight) { _, height in
            coverExpandedLimit = height
        }
    }

    /// Bottom of the visible navigation bar, in window coordinates. Read again after
    /// the bar settles from a rotation.
    private func measureCoverHeader() {
        coverHeaderBottom = visibleNavigationBarBottom() ?? coverHeaderBottom
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if let bottom = visibleNavigationBarBottom() {
                coverHeaderBottom = bottom
            }
        }
    }

    private func visibleNavigationBarBottom() -> CGFloat? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return nil }
        var bottom: CGFloat?
        func walk(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let bar = view as? UINavigationBar {
                let frame = bar.convert(bar.bounds, to: window)
                if frame.height > 1, frame.intersects(window.bounds) {
                    bottom = max(bottom ?? 0, frame.maxY)
                }
                return
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        walk(window)
        return bottom
    }

    private var coverCornerCard: some View {
        let mode: TravelJournalCornerMode = cornerCardExpanded ? .expanded : .compact
        return TravelJournalEditPanel(
            journal: journal,
            trips: members,
            selectedTripID: selectedTripID,
            places: places,
            restHeight: 0,
            isExpanded: cornerCardExpanded,
            cornerMode: mode,
            reduceMotion: reduceMotion,
            onSelectTrip: { selectedTripID = $0 },
            onOpenTrip: { TabSelection.shared.appendTrip($0) },
            onRemoveTrip: removeFromJournal,
            onEdit: { editorDraft = .edit(journal) },
            onToggleExpanded: toggleCornerCard,
            onGrabberDragChanged: { translation in
                dragTranslation = translation
            },
            onGrabberDragEnded: { predicted in
                snapCornerCard(predictedTranslation: predicted)
            },
            onCornerSummaryHeight: noteCoverCardHeight
        )
        .background {
            AtmosphericBackground(style: .lightweight)
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journal.cornerCard")
    }

    /// The compact card is the grabber and summary only, never the expanded height.
    private var coverCompactHeight: CGFloat {
        coverCardMeasuredHeight > 0 ? coverCardMeasuredHeight : 148
    }

    /// Records the summary height. Expanded, the summary unwraps the title and note,
    /// so that taller height must not become the compact height.
    private func noteCoverCardHeight(_ height: CGFloat) {
        guard !cornerCardExpanded, height > 0 else { return }
        guard abs(height - coverCardMeasuredHeight) > 1 else { return }
        coverCardMeasuredHeight = height
        scheduleMapRefit(delayMilliseconds: 80)
    }

    private func toggleCornerCard() {
        MilehoundHaptics.selection()
        withAnimation(reduceMotion ? nil : MilehoundMotion.sheetRise) {
            cornerCardExpanded.toggle()
            dragTranslation = 0
        }
    }

    private func snapCornerCard(predictedTranslation: CGFloat) {
        let compact = coverCompactHeight
        let expanded = max(coverExpandedLimit, compact + 1)
        let base = cornerCardExpanded ? expanded : compact
        let projected = min(max(base - predictedTranslation, compact), expanded)
        let mid = (compact + expanded) / 2
        let next: Bool
        if predictedTranslation < -240 {
            next = true
        } else if predictedTranslation > 240 {
            next = false
        } else {
            next = projected >= mid
        }
        if next != cornerCardExpanded {
            MilehoundHaptics.selection()
        }
        withAnimation(reduceMotion ? nil : MilehoundMotion.sheetRise) {
            cornerCardExpanded = next
            dragTranslation = 0
        }
    }

    /// Leading pane on the wide landscape book. One atmosphere, trips open, no sheet plate.
    private func journalColumn(in geometry: GeometryProxy) -> some View {
        let measuredTop = max(geometry.safeAreaInsets.top, windowSafeInsets.top)
        // Landscape puts the island on the side, so the top inset can be 0 while the
        // inline bar still covers the first row once the pane fills the screen.
        let top = measuredTop + (measuredTop > 20 ? 8 : 44)
        let bottom = max(geometry.safeAreaInsets.bottom, windowSafeInsets.bottom, 12) + 12
        return TravelJournalEditPanel(
            journal: journal,
            trips: members,
            selectedTripID: selectedTripID,
            places: places,
            restHeight: geometry.size.height,
            isExpanded: true,
            fillsColumn: true,
            columnTopInset: top,
            columnBottomInset: bottom,
            reduceMotion: reduceMotion,
            onSelectTrip: { selectedTripID = $0 },
            onOpenTrip: { TabSelection.shared.appendTrip($0) },
            onRemoveTrip: removeFromJournal,
            onEdit: { editorDraft = .edit(journal) },
            onToggleExpanded: {},
            onGrabberDragChanged: { _ in },
            onGrabberDragEnded: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mapSizeReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { noteJournalMap(geo) }
                .onChange(of: geo.size) { _, _ in
                    noteJournalMap(geo)
                }
        }
        .allowsHitTesting(false)
    }

    /// Side-tab column on this Duo sheet. The leading gap copies that trailing inset.
    private func sheetLeadingInset(in geometry: GeometryProxy) -> CGFloat {
        let trailing = MilehoundSideTabGap.trailing(in: geometry, layoutDirection: layoutDirection)
        return layout.duoSheetLeadingInset(matchingTrailingSafeArea: trailing)
    }

    private func editPanel(
        height: CGFloat,
        mapPeek: CGFloat,
        containerHeight: CGFloat,
        embedded: Bool = false,
        leadingInset: CGFloat = 0
    ) -> some View {
        let resolvedLeading = embedded ? 0 : leadingInset
        return HStack(alignment: .bottom, spacing: 0) {
            if resolvedLeading > 0 {
                Color.clear
                    .frame(width: resolvedLeading, height: 0)
                    .allowsHitTesting(false)
            }
            TravelJournalEditPanel(
                journal: journal,
                trips: members,
                selectedTripID: selectedTripID,
                places: places,
                restHeight: height,
                isExpanded: panelDetent == .expanded,
                reduceMotion: reduceMotion,
                onSelectTrip: { selectedTripID = $0 },
                onOpenTrip: { TabSelection.shared.appendTrip($0) },
                onRemoveTrip: removeFromJournal,
                onEdit: { editorDraft = .edit(journal) },
                onToggleExpanded: { togglePanelDetent() },
                onGrabberDragChanged: { translation in
                    dragTranslation = translation
                },
                onGrabberDragEnded: { predicted in
                    snapPanel(
                        predictedTranslation: predicted,
                        containerHeight: containerHeight,
                        mapPeek: mapPeek
                    )
                }
            )
            .frame(maxWidth: .infinity)
            .background {
                AtmosphericBackground(style: .lightweight)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: embedded ? GlassTokens.cardRadius : 18,
                    bottomLeadingRadius: embedded ? GlassTokens.cardRadius : (resolvedLeading > 0 ? 18 : 0),
                    bottomTrailingRadius: embedded ? GlassTokens.cardRadius : (resolvedLeading > 0 ? 18 : 0),
                    topTrailingRadius: embedded ? GlassTokens.cardRadius : 18,
                    style: .continuous
                )
            )
        }
        .offset(y: embedded || panelVisible ? 0 : height + 24)
        .opacity(embedded || panelVisible ? 1 : 0)
        .animation(reduceMotion ? nil : MilehoundMotion.sheetRise, value: panelRisen)
        .animation(reduceMotion ? nil : mapExpandAnimation, value: isMapExpanded)
        .allowsHitTesting(embedded || panelVisible)
    }

    private var mapExpandAnimation: Animation {
        isMapExpanded ? MilehoundMotion.mapExpand : MilehoundMotion.mapCollapse
    }

    @MainActor
    private func playPanelEntrance() async {
        panelRisen = false
        panelDetent = .compact
        dragTranslation = 0
        await loadRoutes()
        withAnimation(reduceMotion ? nil : MilehoundMotion.sheetRise) {
            panelRisen = true
        }
        scheduleMapRefit(delayMilliseconds: 80)
    }

    /// Upright Duo, open or the closed cover. The pulled-up list stops at half the page.
    private var pinsTravelSheetToDuo: Bool {
        layout.isClosedCoverPortrait
            || (layout.layoutClass == .duoOpen && layout.tripDetailStyle == .overlay)
    }

    /// Upright Duo card was a tall phone sheet, so the summary sat on a large empty band.
    private var duoCompactFraction: CGFloat {
        pinsTravelSheetToDuo ? 0.24 : TravelJournalPanelLayout.compactHeightFraction
    }

    /// Pulled-up travel sheet on the upright Duo. Half the window, not the phone's 0.72.
    private var duoExpandedFraction: CGFloat {
        pinsTravelSheetToDuo ? 0.5 : TravelJournalPanelLayout.expandedHeightFraction
    }

    private var duoCompactFloor: CGFloat {
        pinsTravelSheetToDuo ? 220 : TravelJournalPanelLayout.compactMinimum
    }

    private func livePanelHeight(containerHeight: CGFloat, mapPeek: CGFloat) -> CGFloat {
        TravelJournalPanelLayout.draggedHeight(
            detent: panelDetent,
            translation: dragTranslation,
            containerHeight: containerHeight,
            mapPeek: mapPeek,
            compactFraction: duoCompactFraction,
            compactFloor: duoCompactFloor,
            expandedFraction: duoExpandedFraction
        )
    }

    private func togglePanelDetent() {
        MilehoundHaptics.selection()
        withAnimation(reduceMotion ? nil : MilehoundMotion.sheetRise) {
            panelDetent = panelDetent == .compact ? .expanded : .compact
            dragTranslation = 0
        }
    }

    private func snapPanel(
        predictedTranslation: CGFloat,
        containerHeight: CGFloat,
        mapPeek: CGFloat
    ) {
        let next = TravelJournalPanelLayout.snappedDetent(
            predictedTranslation: predictedTranslation,
            from: panelDetent,
            containerHeight: containerHeight,
            mapPeek: mapPeek,
            compactFraction: duoCompactFraction,
            compactFloor: duoCompactFloor,
            expandedFraction: duoExpandedFraction
        )
        if next != panelDetent {
            MilehoundHaptics.selection()
        }
        withAnimation(reduceMotion ? nil : MilehoundMotion.sheetRise) {
            panelDetent = next
            dragTranslation = 0
        }
    }

    private func toggleMapExpanded() {
        let expanding = !isMapExpanded
        MilehoundHaptics.selection()
        let motion = expanding ? MilehoundMotion.mapExpand : MilehoundMotion.mapCollapse
        if reduceMotion {
            isMapExpandTransitioning = false
            isMapExpanded = expanding
            scheduleMapRefit(delayMilliseconds: 40)
            return
        }
        isMapExpandTransitioning = true
        withAnimation(motion) {
            isMapExpanded = expanding
        }
        scheduleMapRefit(delayMilliseconds: 40)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(expanding ? 1400 : 1100))
            isMapExpandTransitioning = false
        }
    }

    private func removeFromJournal(_ trip: Trip) {
        TravelJournalTotals.assign(trip: trip, to: nil, in: modelContext)
        if selectedTripID == trip.id {
            selectedTripID = nil
        }
        try? modelContext.save()
        ToastPresenter.shared.show(.deleted)
    }

    private func loadRoutes() async {
        let trips = members
        guard !trips.isEmpty else {
            overlays = []
            selectedSegments = []
            fitCoordinates = []
            return
        }

        var raw: [(trip: Trip, coordinates: [CLLocationCoordinate2D], samples: [[RouteSample]])] = []
        for trip in trips {
            let pieces = await TripRoutePathCache.shared.path(for: trip, container: modelContext.container)
            let coordinates = pieces.flatMap { $0.map(\.coordinate) }
            guard coordinates.count >= 2 else { continue }
            raw.append((trip, coordinates, pieces))
        }

        guard !raw.isEmpty else {
            overlays = []
            selectedSegments = []
            fitCoordinates = []
            return
        }

        let counts = raw.map(\.coordinates.count)
        let allocated = TravelJournalMapBudget.allocate(pointCounts: counts)

        let domainKeys = raw.map { $0.trip.id.uuidString }
        var nextOverlays: [TravelJournalRouteOverlay] = []
        var nextSelected: [TripDetailRevealedRouteSegment] = []
        let selectedID = selectedTripID ?? raw.first?.trip.id

        for (index, item) in raw.enumerated() {
            let sampled = TravelJournalMapBudget.downsample(item.coordinates, to: allocated[index])
            let isSelected = item.trip.id == selectedID
            let color = StatsChartTheme.sliceColor(
                forStableKey: item.trip.id.uuidString,
                durationStyle: false,
                domainKeys: domainKeys,
                palette: AppSettings.shared.shellPalette,
                scheme: colorScheme
            )
            nextOverlays.append(
                TravelJournalRouteOverlay(
                    id: item.trip.id,
                    coordinates: sampled,
                    color: isSelected ? color.opacity(0.35) : color.opacity(0.4),
                    isSelected: false
                )
            )
            if isSelected {
                let segments = SpeedColoredSegmentBuilder.build(pieces: item.samples)
                nextSelected = segments.map {
                    TripDetailRevealedRouteSegment(
                        id: "\(item.trip.id.uuidString)-\($0.id)",
                        coordinates: $0.coordinates,
                        color: $0.color
                    )
                }
            }
        }

        overlays = nextOverlays
        selectedSegments = nextSelected
        if selectedTripID == nil {
            selectedTripID = selectedID
        }
        if let selected = raw.first(where: { $0.trip.id == selectedID }), !selected.coordinates.isEmpty {
            fitCoordinates = selected.coordinates
        } else {
            fitCoordinates = raw.flatMap(\.coordinates)
        }
        applyFittedCamera(animated: false)
    }

    private func noteJournalMap(_ geo: GeometryProxy) {
        guard geo.size.width > 1, geo.size.height > 1 else { return }
        let previous = mapViewportSize
        mapViewportSize = geo.size
        let window = windowSafeInsets
        let topSafe = max(geo.safeAreaInsets.top, window.top)
        mapTopChromePoints = topSafe + 44
        mapBottomChromePoints = max(geo.safeAreaInsets.bottom, window.bottom, 12)
        mapTrailingInset = MilehoundSideTabGap.trailing(in: geo, layoutDirection: layoutDirection)
        mapHomeIndicator = max(geo.safeAreaInsets.bottom, window.bottom, 12)
        let changed = abs(previous.width - geo.size.width) > 1
            || abs(previous.height - geo.size.height) > 1
        guard changed else { return }
        scheduleMapRefit(animated: false)
    }

    private func refreshMapChromeInsets(from geometry: GeometryProxy) {
        mapViewportSize = geometry.size
        let window = windowSafeInsets
        let topSafe = max(geometry.safeAreaInsets.top, window.top, 54)
        mapTopChromePoints = topSafe + 44
        mapBottomChromePoints = max(window.bottom, 34) + 49
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    /// Height of the corner card, so the route centers in the map above it.
    private var coverCardHeightForFit: CGFloat {
        guard layout.isClosedCoverLandscape, !isMapExpanded else { return 0 }
        if cornerCardExpanded { return coverExpandedLimit }
        return coverCompactHeight
    }

    /// Width of the corner card, so the route centers in the map beside it.
    private var coverCardWidthForFit: CGFloat {
        guard layout.isClosedCoverLandscape, !isMapExpanded else { return 0 }
        return GlassTokens.TravelCornerCardMetrics.compactWidth(screenWidth: mapViewportSize.width)
    }

    private func applyFittedCamera(animated: Bool) {
        let sheetHeight = TravelJournalPanelLayout.height(
            for: panelDetent,
            containerHeight: mapViewportSize.height,
            mapPeek: mapTopChromePoints + 24,
            compactFraction: duoCompactFraction,
            compactFloor: duoCompactFloor,
            expandedFraction: duoExpandedFraction
        )
        let coverWidth = coverCardWidthForFit
        let padding = TravelJournalMapFit.padding(
            style: layout.tripDetailStyle,
            mapExpanded: isMapExpanded,
            mapSize: mapViewportSize,
            topChrome: mapTopChromePoints,
            bottomChrome: mapBottomChromePoints,
            sheetHeight: sheetHeight,
            trailingCover: mapTrailingInset,
            homeIndicator: mapHomeIndicator,
            coverCardWidth: coverWidth,
            coverCardHeight: coverCardHeightForFit,
            coverCardIsTrailing: layoutDirection != .rightToLeft
        )
        guard let region = TripDetailViewModel.regionFitting(
            coordinates: fitCoordinates,
            mapSize: mapViewportSize,
            edgePadding: padding,
            margin: isMapExpanded ? 1.18 : 1.2
        ) else { return }

        let position = MapCameraPosition.region(region)
        if animated, !reduceMotion {
            withAnimation(MilehoundMotion.gentle) {
                cameraBox.position = position
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cameraBox.position = position
            }
        }
    }

    private func scheduleMapRefit(animated: Bool = true, delayMilliseconds: UInt64 = 160) {
        mapRefitTask?.cancel()
        mapRefitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            applyFittedCamera(animated: animated)
        }
    }
}

