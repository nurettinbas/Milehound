import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
private enum TripDetailRevealSession {
    static var completedTripIDs: Set<UUID> = []

    static func markCompleted(_ tripID: UUID) {
        completedTripIDs.insert(tripID)
    }

    static func hasCompleted(_ tripID: UUID) -> Bool {
        completedTripIDs.contains(tripID)
    }
}

/// Resting overlay height — editing growth lives in `TripDetailEditPanel`.
private enum TripDetailPanelLayout {
    static let heightFraction: CGFloat = TripDetailKeyboardLayout.restHeightFraction
    static let editingHeightFraction: CGFloat = TripDetailKeyboardLayout.editingHeightFraction
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Query private var places: [SavedPlace]
    @Bindable private var settings = AppSettings.shared

    @State private var mapCameraBox = TripDetailMapCameraBox()
    /// Used so camera fit spans match the portrait map aspect.
    @State private var mapViewportSize: CGSize = CGSize(width: 390, height: 844)
    /// Last map size. A jump here is a turn; writing the camera then cancels it.
    @State private var laidOutMapSize: CGSize = .zero
    /// Status + transparent nav overlay height in points (not a fraction of a stale size).
    @State private var mapTopChromePoints: CGFloat = 96
    /// Tab bar + home-indicator band the map draws under (`.ignoresSafeArea(.bottom)`).
    @State private var mapBottomChromePoints: CGFloat = 83
    /// Last laid-out panel height — refit uses this, not only the layout fraction.
    @State private var lastLivePanelHeight: CGFloat = 0
    /// Side tab overlapping the map, measured from the window.
    @State private var mapTrailingCover: CGFloat = 0
    /// Leading gap of the upright Duo sheet, so the route centers in the clear map.
    @State private var mapLeadingInset: CGFloat = 0
    @State private var mapHomeIndicator: CGFloat = 34
    @State private var cameraSettle = TripDetailCameraSettle.State()
    @State private var cameraSettleTask: Task<Void, Never>?
    @State private var lastAppliedRegion: MKCoordinateRegion?
    @State private var shareImage: UIImage?
    @State private var shareCaption: String?
    @State private var showShareSheet = false
    @State private var isRenderingShareCard = false
    /// In-place map expand — panel slides away on the same MapKit instance (no sheet).
    @State private var isMapExpanded = false
    /// True while expand/collapse animation runs — freezes glass over the live map.
    @State private var isMapExpandTransitioning = false
    /// Style picker fades in after the panel has largely cleared.
    @State private var showExpandedMapChrome = false
    @State private var mapExpandTransitionTask: Task<Void, Never>?
    /// `nil` until the user picks — then Light/Dark are forced, not system-following.
    @State private var mapStyleOverride: TripDetailMapStyle?
    /// Recorded GPS count — filled after the first paint so opening never faults points.
    @State private var recordedPointCount: Int = 0
    @State private var routeRevealProgress: Double = 0
    @State private var startPinVisible = false
    @State private var endPinVisible = false
    @State private var showAllStops = false
    @State private var didStartDetailReveal = false
    @State private var detailRevealTask: Task<Void, Never>?
    @State private var panelRisen = false
    /// 0 = muted settle veil, 1 = map clear. Held muted until the route path is ready.
    @State private var mapClarity: Double = 0
    @State private var showSharePreview = false
    @State private var pendingSystemShare = false
    @State private var statCountProgress: [String: Double] = [:]
    @State private var speedChartRevealProgress: Double = 0
    @State private var tripDetailViewModel: TripDetailViewModel?
    @State private var routeLoadTask: Task<Void, Never>?
    /// Bumped to ask `TripDetailEditPanel` to resign first responder.
    @State private var keyboardDismissSignal = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glassFrozen: Bool { isMapExpandTransitioning }

    private var panelVisible: Bool { panelRisen && !isMapExpanded }

    private var resolvedViewModel: TripDetailViewModel {
        if let tripDetailViewModel, tripDetailViewModel.belongs(to: trip) {
            return tripDetailViewModel
        }
        return TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: nil
        )
    }

    private var sortedStops: [TripStop] {
        trip.stops.sorted { $0.startedAt < $1.startedAt }
    }

    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.tripDetailRegion) private var tripDetailRegion
    @State private var widePanelCollapsed = false

    var body: some View {
        Group {
            if tripDetailRegion == .details {
                detailsPage
            } else if tripDetailRegion == .map {
                tripDetailMapLayer(interactive: true)
            } else if tripDetailRegion == .stacked {
                stackedBody
            } else if layout.tripDetailStyle == .overlay {
                phoneBody
            } else {
                wideBody
            }
        }
        .animation(
            TrailhoundInterfaceRotation.shared.isRotating
                || TrailhoundInterfaceRotation.shared.suppressReflowAnimation
                ? nil
                : TrailhoundMotion.layoutReflow(reduceMotion: reduceMotion),
            value: layout.layoutClass
        )
        .onChange(of: TrailhoundInterfaceRotation.shared.isRotating) { _, rotating in
            let action = mutateCameraSettle { state in
                TripDetailCameraSettle.reduceTurnFlag(&state, rotating: rotating)
            }
            applyCameraSettle(action, animated: !reduceMotion)
        }
        .onChange(of: layout.layoutClass) { _, _ in
            noteMapPostureChange()
        }
        .onChange(of: layout.tripDetailStyle) { _, _ in
            noteMapPostureChange()
        }
        .onChange(of: layout.isLandscape) { _, _ in
            noteMapPostureChange()
        }
        .onAppear {
            beginTripDetailSession()
        }
        .onChange(of: trip.id) { oldID, newID in
            DevLog.shared.log(
                .tripDetail,
                "trip changed \(oldID.uuidString.prefix(8)) -> \(newID.uuidString.prefix(8))"
            )
            resetTripDetailSession()
            beginTripDetailSession()
        }
        .onStoreSave {
            refreshTripDetailViewModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            guard UIDevice.current.orientation.isValidInterfaceOrientation else { return }
            // The size change and the turn flag own the fit. This only marks one as owed
            // so a hint that arrives before the new size is not forgotten.
            _ = mutateCameraSettle { state in
                state.owed = true
                return .none
            }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            DevLog.shared.log(.tripDetail, "disappear trip=\(trip.id.uuidString.prefix(8))")
        }
    }

    @ViewBuilder
    private var wideBody: some View {
        switch layout.tripDetailStyle {
        case .overlay:
            phoneBody
        case .split:
            TrailhoundPaneSplit(
                leadingFillsVertically: true,
                focusFillsVertically: true,
                focusBleedsTrailing: true
            ) {
                detailsPage
            } focus: {
                tripDetailMapLayer(interactive: true)
                    .ignoresSafeArea()
                    .background { mapSizeReader }
            }
        case .floatingPanel:
            if layout.layoutClass == .phoneLandscape {
                phoneLandscapeMap
            } else {
                TrailhoundMapCanvas(panelCollapsed: $widePanelCollapsed) {
                    tripDetailMapLayer(interactive: true)
                        .background { mapSizeReader }
                } panel: {
                    detailsPage
                }
            }
        case .stacked:
            stackedBody
        }
    }

    private var stackedBody: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                tripDetailMapLayer(interactive: true)
                    .frame(height: geo.size.height * 0.55)
                    .background { mapSizeReader }
                detailsPage
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// Landscape phone: the route fills the screen and the details card rests on the bottom.
    private var phoneLandscapeMap: some View {
        GeometryReader { geo in
            let panelHeight = livePanelHeight(containerHeight: geo.size.height)
            ZStack(alignment: .bottom) {
                tripDetailMapLayer(interactive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .background { mapSizeReader }

                TripDetailEditPanel(
                    trip: trip,
                    viewModel: resolvedViewModel,
                    glassFrozen: glassFrozen,
                    panelRisen: true,
                    restHeight: panelHeight,
                    mapPeek: 24,
                    reduceMotion: reduceMotion,
                    statCountProgress: statCountProgress,
                    speedChartRevealProgress: speedChartRevealProgress,
                    recordedPointCount: $recordedPointCount,
                    keyboardDismissSignal: $keyboardDismissSignal,
                    onDisplayRefresh: { refreshTripDetailViewModel() },
                    onRouteInvalidated: { reloadRouteAfterTrim() }
                )
                .background {
                    AtmosphericBackground(style: .lightweight)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 18,
                        style: .continuous
                    )
                )
                .padding(.horizontal, GlassTokens.panelHorizontalInset)
            }
            .onAppear {
                lastLivePanelHeight = panelHeight
            }
            .onChange(of: panelHeight) { _, newHeight in
                lastLivePanelHeight = newHeight
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var mapSizeReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { noteMapProxy(geo) }
                .onChange(of: geo.size) { _, _ in
                    noteMapProxy(geo)
                }
        }
        .allowsHitTesting(false)
    }

    private var detailsPage: some View {
        GeometryReader { geo in
            TripDetailEditPanel(
                trip: trip,
                viewModel: resolvedViewModel,
                glassFrozen: glassFrozen,
                panelRisen: true,
                restHeight: geo.size.height,
                mapPeek: 24,
                showsGrabber: false,
                reduceMotion: reduceMotion,
                statCountProgress: statCountProgress,
                speedChartRevealProgress: speedChartRevealProgress,
                recordedPointCount: $recordedPointCount,
                keyboardDismissSignal: $keyboardDismissSignal,
                onDisplayRefresh: { refreshTripDetailViewModel() },
                onRouteInvalidated: { reloadRouteAfterTrim() }
            )
        }
        .background {
            // The book already paints one atmosphere. A second wash on this pane
            // is a different shade than the gutter and the shell.
            if paintsOwnAtmosphere {
                AtmosphericBackground(style: .lightweight)
            }
        }
    }

    /// Split and the embedded details pane sit on `TrailhoundPaneSplit`'s atmosphere.
    /// Floating and stacked pages still need their own wash.
    private var paintsOwnAtmosphere: Bool {
        tripDetailRegion == .automatic && layout.tripDetailStyle != .split
    }

    private var phoneBody: some View {
        ZStack {
            AtmosphericBackground()

            GeometryReader { geometry in
                let containerHeight = geometry.size.height
                let panelHeight = livePanelHeight(containerHeight: containerHeight)
                let mapPeek = mapTopChromePoints + 24
                // Full screen: the reader ignores the bottom safe area. The chips sit under
                // the tab, on the home indicator — not a tab-height above it.
                // Always rest height — editing growth is owned by TripDetailEditPanel.
                let expandedLegendInset = max(mapBottomChromePoints - 49, 8)
                let chromeBottomInset = isMapExpanded
                    ? expandedLegendInset
                    : (panelVisible ? panelHeight : mapBottomChromePoints)
                let sheetLeadingInset = sheetLeadingInset(in: geometry)
                ZStack(alignment: .bottom) {
                    // Full-screen map — never resized by the panel (Apple Maps pattern).
                    // Keep interactive from first paint so toggling modes does not rebuild MapKit.
                    tripDetailMapLayer(interactive: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            dismissEditKeyboard()
                        }

                    // Soft settle veil — fades out before the sheet rises (does not remount MapKit).
                    Color.black.opacity(0.42 * (1 - mapClarity))
                        .allowsHitTesting(false)
                        .animation(reduceMotion ? nil : TrailhoundMotion.mapClear, value: mapClarity)

                    // Cheap chrome sits above the map and tracks panel height without resizing MapKit.
                    ZStack(alignment: .topTrailing) {
                        if !networkMonitor.isConnected {
                            Text(L10n.tripMapOfflineHint)
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassChrome(cornerRadius: 14, frozen: glassFrozen)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(12)
                                .opacity(mapClarity)
                        }

                        compactSpeedLegend
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(12)
                            .opacity(mapClarity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, chromeBottomInset)
                    .animation(
                        reduceMotion ? nil : (isMapExpanded
                            ? TrailhoundMotion.mapExpand
                            : TrailhoundMotion.mapCollapse),
                        value: isMapExpanded
                    )
                    .allowsHitTesting(false)

                    HStack(alignment: .bottom, spacing: 0) {
                        if sheetLeadingInset > 0 {
                            Color.clear
                                .frame(width: sheetLeadingInset, height: 0)
                                .allowsHitTesting(false)
                        }
                        TripDetailEditPanel(
                            trip: trip,
                            viewModel: resolvedViewModel,
                            glassFrozen: glassFrozen,
                            panelRisen: panelRisen,
                            restHeight: panelHeight,
                            mapPeek: mapPeek,
                            reduceMotion: reduceMotion,
                            statCountProgress: statCountProgress,
                            speedChartRevealProgress: speedChartRevealProgress,
                            recordedPointCount: $recordedPointCount,
                            keyboardDismissSignal: $keyboardDismissSignal,
                            onDisplayRefresh: { refreshTripDetailViewModel() },
                            onRouteInvalidated: { reloadRouteAfterTrim() }
                        )
                        .frame(maxWidth: .infinity)
                        .background {
                            // Opaque wash — glass cards and the translucent tab bar never sample the map.
                            ZStack {
                                AtmosphericBackground(style: .lightweight)
                            }
                        }
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 18,
                                bottomLeadingRadius: sheetLeadingInset > 0 ? 18 : 0,
                                bottomTrailingRadius: sheetLeadingInset > 0 ? 18 : 0,
                                topTrailingRadius: 18,
                                style: .continuous
                            )
                        )
                    }
                        .offset(y: panelVisible ? 0 : panelHeight + 24)
                        .opacity(panelVisible ? 1 : 0)
                        .animation(reduceMotion ? nil : TrailhoundMotion.sheetRise, value: panelRisen)
                        .animation(
                            reduceMotion ? nil : (isMapExpanded
                                ? TrailhoundMotion.mapExpand
                                : TrailhoundMotion.mapCollapse),
                            value: isMapExpanded
                        )
                        .allowsHitTesting(panelVisible)
                }
                // Content-sized overlay — outside frozen chrome so the picker stays tappable.
                .overlay(alignment: .topTrailing) {
                    if showExpandedMapChrome {
                        expandedMapStylePicker
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    lastLivePanelHeight = panelHeight
                    noteMapProxy(geometry)
                }
                .onChange(of: geometry.size) { _, _ in
                    if !isMapExpanded {
                        lastLivePanelHeight = livePanelHeight(containerHeight: geometry.size.height)
                    }
                    noteMapProxy(geometry)
                }
                .onChange(of: panelHeight) { _, newHeight in
                    guard !isMapExpanded else { return }
                    lastLivePanelHeight = newHeight
                }
            }
        }
        // Extend under the translucent tab bar so the card wash covers it — no map peeking through.
        .ignoresSafeArea(edges: .bottom)
        .glassNavigationChrome()
        .glassMapTopEdgeHidden()
        .accessibilityIdentifier("tripDetail.screen")
        .overlay(alignment: .topLeading) { uiTestRouteProbe }
        .navigationTitle(L10n.tripDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .background(NavigationDismissProbe(onDidPop: endTripDetailSession))
        .glassDetailBackNavigation(action: dismiss.callAsFunction)
        .toolbar {
            GlassToolbarNavTitleItem(title: L10n.tripDetailTitle)
            ToolbarItem(placement: .topBarTrailing) {
                GlassToolbarCluster {
                    GlassToolbarCircleButton(
                        systemName: "square.and.arrow.up",
                        isLoading: isRenderingShareCard,
                        action: { Task { await renderShareCard() } }
                    )
                    .disabled(isRenderingShareCard)
                    .accessibilityLabel(L10n.share)

                    GlassToolbarCircleButton(
                        systemName: isMapExpanded
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        action: toggleMapExpanded
                    )
                    .accessibilityLabel(isMapExpanded ? L10n.mapExitFullscreen : L10n.mapFullscreen)
                }
            }
            .hideSharedToolbarBackgroundIfAvailable()
        }
        .sheet(isPresented: $showSharePreview, onDismiss: {
            if pendingSystemShare {
                pendingSystemShare = false
                showShareSheet = true
            } else {
                shareImage = nil
                shareCaption = nil
            }
        }) {
            if let shareImage {
                TripSharePreviewSheet(
                    image: shareImage,
                    caption: shareCaption,
                    onShare: {
                        pendingSystemShare = true
                        showSharePreview = false
                    },
                    onClose: {
                        pendingSystemShare = false
                        showSharePreview = false
                    }
                )
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            shareImage = nil
            shareCaption = nil
            pendingSystemShare = false
        }) {
            if let shareImage {
                SocialImageShareSheet(image: shareImage, caption: shareCaption)
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if isRenderingShareCard {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        TrailhoundBrandMark(showsWordmark: true, symbolSize: 56)
                        ProgressView()
                            .controlSize(.large)
                        Text(L10n.shareCardPreparing)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(28)
                    .glassCard(cornerRadius: 16, contentInset: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRenderingShareCard)
    }

    @ViewBuilder
    private var uiTestRouteProbe: some View {
        if UITestSupport.isEnabled {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("tripDetail.routeIdentity")
                .accessibilityLabel(resolvedViewModel.routeIdentityLabel(for: trip))
        }
    }

    private func beginTripDetailSession() {
        DevLog.shared.log(.tripDetail, "appear trip=\(trip.id.uuidString.prefix(8))")
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        if tripDetailViewModel?.belongs(to: trip) != true {
            tripDetailViewModel = TripDetailViewModel(
                trip: trip,
                places: places,
                privacyRadius: settings.privacyRadiusMeters,
                displayPieces: nil
            )
        }

        if TripDetailRevealSession.hasCompleted(trip.id),
           TripDetailViewModel.reusablePieces(from: tripDetailViewModel, for: trip) != nil {
            mapClarity = 1
            panelRisen = true
            didStartDetailReveal = true
            routeRevealProgress = 1
            startPinVisible = true
            endPinVisible = true
            if !TrailhoundInterfaceRotation.shared.isRotating {
                performCameraSettle(animated: false)
            }
            return
        }

        // Keep legend muted until the path is ready — map itself stays visible (no black veil).
        mapClarity = 0
        panelRisen = false
        didStartDetailReveal = false
        showAllStops = false
        recordedPointCount = 0
        routeRevealProgress = 0
        startPinVisible = false
        endPinVisible = false

        // Frame endpoints immediately so MapKit never sits on .automatic (the device location).
        // A turn in progress keeps the fit owed until the window settles.
        if TrailhoundInterfaceRotation.shared.isRotating {
            _ = mutateCameraSettle { state in
                TripDetailCameraSettle.reduceRequest(&state, frame: currentCameraFrame(), rotating: true)
            }
        } else {
            performCameraSettle(animated: false)
        }

        routeLoadTask?.cancel()
        routeLoadTask = Task { @MainActor in
            await loadDisplayPathAndReveal()
        }
    }

    private func endTripDetailSession() {
        DevLog.shared.log(.tripDetail, "popped trip=\(trip.id.uuidString.prefix(8))")
        logTripDetailDiagnostics(context: "disappear")
        if routeRevealProgress >= 0.95 {
            TripDetailRevealSession.markCompleted(trip.id)
        }
        resetTripDetailSession()
        // The detail map is the only screen that needs every GPS point; holding them past
        // dismissal is how browsing a long library grows memory without bound.
        trip.invalidatePointCaches()
    }

    /// Drops every task and piece of state tied to the trip currently on screen.
    private func resetTripDetailSession() {
        detailRevealTask?.cancel()
        detailRevealTask = nil
        routeLoadTask?.cancel()
        routeLoadTask = nil
        cameraSettleTask?.cancel()
        cameraSettleTask = nil
        mapExpandTransitionTask?.cancel()
        mapExpandTransitionTask = nil
        didStartDetailReveal = false
        showAllStops = false
        recordedPointCount = 0
        isMapExpanded = false
        isMapExpandTransitioning = false
        showExpandedMapChrome = false
    }

    private func loadDisplayPathAndReveal() async {
        let requestedTripID = trip.id
        let pieces = await TripRoutePathCache.shared.path(
            for: trip,
            container: modelContext.container
        )
        guard !Task.isCancelled, trip.id == requestedTripID else { return }

        tripDetailViewModel = TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: pieces
        )

        // Defer faulting recorded points until after the first paint + path are ready.
        await Task.yield()
        guard !Task.isCancelled else { return }
        recordedPointCount = trip.points.count
        refreshPersistedFuelEstimate()

        let plan = TripDetailRevealPolicy.animationPlan(
            pointCount: resolvedViewModel.displayPointCount,
            reduceMotion: reduceMotion
        )

        if !plan.shouldAnimate || TripDetailRevealSession.hasCompleted(trip.id) {
            finishDetailRevealInstant()
            logTripDetailDiagnostics(context: "appear instant")
        } else {
            startDetailReveal(plan: plan)
            logTripDetailDiagnostics(context: "appear animate")
        }
    }

    private func startDetailReveal(plan: TripDetailRevealPolicy.AnimationPlan) {
        guard !didStartDetailReveal else { return }
        didStartDetailReveal = true

        routeRevealProgress = 0
        startPinVisible = false
        endPinVisible = false
        showAllStops = false
        mapClarity = 0
        panelRisen = false
        statCountProgress = Dictionary(
            uniqueKeysWithValues: resolvedViewModel.summaryMetrics.map { ($0.id, 0.0) }
        )
        speedChartRevealProgress = 0

        performCameraSettle(animated: false)

        detailRevealTask?.cancel()
        detailRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }

            // Beat: map clear
            withAnimation(TrailhoundMotion.mapClear) {
                mapClarity = 1
            }

            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }

            // Beat: frosted sheet rise
            withAnimation(TrailhoundMotion.sheetRise) {
                panelRisen = true
            }

            requestCameraSettle(animated: !reduceMotion)

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }

            // Beat: start pin → route draw → end pin
            withAnimation(TrailhoundMotion.pinPop) {
                startPinVisible = true
            }

            await runContentReveal(plan: plan)
        }
    }

    private func runContentReveal(plan: TripDetailRevealPolicy.AnimationPlan) async {
        let metrics = resolvedViewModel.summaryMetrics
        let ticks = max(plan.tickCount, 1)
        let stepSleep = Duration.milliseconds(plan.stepSleepMilliseconds)

        for tick in 1...ticks {
            try? await Task.sleep(for: stepSleep)
            guard !Task.isCancelled else { return }
            let raw = Self.smoothstep(Double(tick) / Double(ticks))
            let progress = TripDetailRevealPolicy.quantizedProgress(
                rawProgress: raw,
                tick: tick,
                tickCount: ticks
            )
            routeRevealProgress = progress
            for metric in metrics {
                statCountProgress[metric.id] = progress
            }
            speedChartRevealProgress = progress
        }

        routeRevealProgress = 1
        for metric in metrics {
            statCountProgress[metric.id] = 1
        }
        speedChartRevealProgress = 1
        showAllStops = true

        TripDetailRevealSession.markCompleted(trip.id)

        withAnimation(TrailhoundMotion.pinPop) {
            endPinVisible = true
        }
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    private func finishDetailRevealInstant() {
        didStartDetailReveal = true
        detailRevealTask?.cancel()
        detailRevealTask = nil
        routeRevealProgress = 1
        startPinVisible = true
        endPinVisible = true
        showAllStops = true
        mapClarity = 1
        panelRisen = true
        statCountProgress = Dictionary(
            uniqueKeysWithValues: resolvedViewModel.summaryMetrics.map { ($0.id, 1.0) }
        )
        speedChartRevealProgress = 1
        TripDetailRevealSession.markCompleted(trip.id)
        // Full-screen map: frame the route into the gap above the live panel.
        requestCameraSettle(animated: false)
    }

    private func setMapCamera(_ position: MapCameraPosition) {
        // A camera write while the window is turning cancels the orientation change.
        guard !TrailhoundInterfaceRotation.shared.isRotating else { return }
        // Update binding only — remounting Map (e.g. via .id) blanks tiles and flashes black.
        mapCameraBox.position = position
    }

    /// Fit the route into the map that is actually on screen.
    /// A landscape phone rests a card on the bottom; a split pane has no card over the map.
    private var restingMapPanelHeight: CGFloat {
        switch layout.tripDetailStyle {
        case .split, .stacked:
            return 0
        case .floatingPanel where layout.layoutClass != .phoneLandscape:
            return 0
        default:
            if lastLivePanelHeight > 0 { return lastLivePanelHeight }
            return mapViewportSize.height * TripDetailPanelLayout.heightFraction
        }
    }

    private var mapFramingPosture: TripDetailMapFraming.Posture {
        if isMapExpanded { return .expanded }
        switch layout.tripDetailStyle {
        case .split:
            return .duoSplit
        case .stacked:
            return .stacked
        case .floatingPanel:
            return layout.layoutClass == .phoneLandscape ? .phoneLandscape : .padTrailing
        case .overlay:
            return .sheet
        }
    }

    private func currentCameraFrame() -> TripDetailMapFraming.Input {
        let posture = mapFramingPosture
        let card: CGFloat
        switch posture {
        case .sheet, .phoneLandscape:
            card = restingMapPanelHeight
        case .duoSplit, .stacked, .padTrailing, .expanded:
            card = 0
        }
        let trailing: CGFloat
        switch posture {
        case .phoneLandscape, .duoSplit, .sheet:
            trailing = mapTrailingCover
        case .padTrailing, .stacked, .expanded:
            trailing = 0
        }
        return TripDetailMapFraming.Input(
            posture: posture,
            mapSize: mapViewportSize,
            topChrome: mapTopChromePoints,
            bottomCardHeight: card,
            trailingCover: trailing,
            leadingInset: posture == .sheet ? mapLeadingInset : 0,
            homeIndicator: mapHomeIndicator
        )
    }

    private func noteMapProxy(_ geo: GeometryProxy) {
        guard geo.size.width > 1, geo.size.height > 1 else { return }
        refreshMapChromeInsets(from: geo)
        mapTrailingCover = TrailhoundSideTabGap.trailing(in: geo, layoutDirection: layoutDirection)
        mapLeadingInset = sheetLeadingInset(in: geo)
        mapHomeIndicator = max(geo.safeAreaInsets.bottom, windowSafeInsets.bottom, 12)
        if !isMapExpanded,
           layout.tripDetailStyle == .overlay
            || (layout.layoutClass == .phoneLandscape && layout.tripDetailStyle == .floatingPanel) {
            lastLivePanelHeight = livePanelHeight(containerHeight: geo.size.height)
        }
        let previous = laidOutMapSize
        let looksLikeTurn = TrailhoundLayoutResolver.viewportChangeCancelsRotation(from: previous, to: geo.size)
        laidOutMapSize = geo.size
        let action = mutateCameraSettle { state in
            TripDetailCameraSettle.reduce(
                &state,
                layout: currentCameraFrame(),
                rotating: TrailhoundInterfaceRotation.shared.isRotating,
                looksLikeTurn: looksLikeTurn
            )
        }
        applyCameraSettle(action, animated: !reduceMotion)
    }

    private func noteMapPostureChange() {
        guard mapViewportSize.width > 1, mapViewportSize.height > 1 else { return }
        let rotating = TrailhoundInterfaceRotation.shared.isRotating
        let action = mutateCameraSettle { state in
            TripDetailCameraSettle.reduce(
                &state,
                layout: currentCameraFrame(),
                rotating: rotating,
                looksLikeTurn: rotating
            )
        }
        applyCameraSettle(action, animated: !reduceMotion)
    }

    private func requestCameraSettle(animated: Bool) {
        let action = mutateCameraSettle { state in
            TripDetailCameraSettle.reduceRequest(
                &state,
                frame: currentCameraFrame(),
                rotating: TrailhoundInterfaceRotation.shared.isRotating
            )
        }
        applyCameraSettle(action, animated: animated)
    }

    private func applyCameraSettle(_ action: TripDetailCameraSettle.Action, animated: Bool) {
        switch action {
        case .none:
            break
        case .waitForQuiet:
            scheduleQuietSettle(animated: animated)
        case .fit:
            performCameraSettle(animated: animated)
        }
    }

    /// One fit after layout stops moving. A turn that is still going keeps the fit owed.
    private func scheduleQuietSettle(animated: Bool) {
        cameraSettleTask?.cancel()
        cameraSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            while TrailhoundInterfaceRotation.shared.isRotating {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let stillRotating = TrailhoundInterfaceRotation.shared.isRotating
            let action = mutateCameraSettle { state in
                TripDetailCameraSettle.reduceQuietElapsed(&state, stillRotating: stillRotating)
            }
            applyCameraSettle(action, animated: animated)
        }
    }

    private func performCameraSettle(animated: Bool) {
        guard !TrailhoundInterfaceRotation.shared.isRotating else {
            _ = mutateCameraSettle { state in
                state.owed = true
                state.rotating = true
                return .none
            }
            return
        }
        let frame = currentCameraFrame()
        guard let region = fittedMapRegion(frame) else {
            _ = mutateCameraSettle { state in
                state.frame = frame
                state.owed = true
                return .none
            }
            return
        }
        _ = mutateCameraSettle { state in
            state.frame = frame
            state.owed = false
            state.rotating = false
            return .none
        }
        if let lastAppliedRegion,
           !TripDetailCameraMotion.shouldWrite(
            current: lastAppliedRegion,
            proposed: region,
            mapSize: frame.mapSize
           ) {
            return
        }
        applyFittedCamera(
            region: region,
            animated: animated && !reduceMotion,
            animation: TrailhoundMotion.gentle
        )
        lastAppliedRegion = region
    }

    private func mutateCameraSettle(
        _ body: (inout TripDetailCameraSettle.State) -> TripDetailCameraSettle.Action
    ) -> TripDetailCameraSettle.Action {
        var copy = cameraSettle
        let action = body(&copy)
        cameraSettle = copy
        return action
    }

    private func livePanelHeight(containerHeight: CGFloat) -> CGFloat {
        containerHeight * TripDetailPanelLayout.heightFraction
    }

    /// `GeometryReader` under `.ignoresSafeArea(.bottom)` reports a zero bottom inset.
    /// Read the key window so the tab bar + home indicator are real points.
    private func refreshMapChromeInsets(from geometry: GeometryProxy) {
        mapViewportSize = geometry.size
        let window = windowSafeInsets
        let topSafe = max(geometry.safeAreaInsets.top, window.top, 54)
        mapTopChromePoints = topSafe + 44
        // 49 = standard UITabBar content height above the home indicator.
        mapBottomChromePoints = max(window.bottom, 34) + 49
    }

    /// Side-tab column on this Duo sheet. The leading gap copies that trailing inset.
    private func sheetLeadingInset(in geometry: GeometryProxy) -> CGFloat {
        let trailing = TrailhoundSideTabGap.trailing(in: geometry, layoutDirection: layoutDirection)
        return layout.duoSheetLeadingInset(matchingTrailingSafeArea: trailing)
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    private func fittedMapRegion(_ frame: TripDetailMapFraming.Input) -> MKCoordinateRegion? {
        let size = frame.mapSize
        guard size.width > 1, size.height > 1 else { return nil }
        return resolvedViewModel.mapRegion(
            mapSize: size,
            edgePadding: TripDetailMapFraming.edgeInsets(frame),
            margin: frame.posture == .expanded ? 1.18 : 1.2
        )
    }

    private func applyFittedCamera(
        region: MKCoordinateRegion,
        animated: Bool,
        animation: Animation = TrailhoundMotion.gentle
    ) {
        // Use the fitted region directly. Converting to MapCamera + a fudged altitude
        // zooms in (~1.55× max-span) and clips the route off-center under the tab bar.
        let position = MapCameraPosition.region(region)
        if animated, !reduceMotion {
            withAnimation(animation) {
                setMapCamera(position)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                setMapCamera(position)
            }
        }
    }

    /// Immediate fit for the full-screen map toggle. Posture changes go through the settle.
    private func refitMapToVisibleGap(
        animated: Bool = true,
        animation: Animation = TrailhoundMotion.gentle
    ) {
        guard !TrailhoundInterfaceRotation.shared.isRotating else {
            _ = mutateCameraSettle { state in
                state.owed = true
                state.rotating = true
                return .none
            }
            return
        }
        let frame = currentCameraFrame()
        guard let region = fittedMapRegion(frame) else { return }
        if let lastAppliedRegion,
           !TripDetailCameraMotion.shouldWrite(
            current: lastAppliedRegion,
            proposed: region,
            mapSize: frame.mapSize
           ) {
            return
        }
        applyFittedCamera(region: region, animated: animated, animation: animation)
        lastAppliedRegion = region
    }

    private func toggleMapExpanded() {
        let expanding = !isMapExpanded
        cameraSettleTask?.cancel()
        mapExpandTransitionTask?.cancel()
        TrailhoundHaptics.selection()
        dismissEditKeyboard()

        let motion = expanding ? TrailhoundMotion.mapExpand : TrailhoundMotion.mapCollapse
        let durationMs: UInt64 = expanding ? 1400 : 1100
        let chromeFadeInMs: UInt64 = 750

        if reduceMotion {
            isMapExpandTransitioning = false
            showExpandedMapChrome = expanding
            isMapExpanded = expanding
            refitMapToVisibleGap(animated: false)
            return
        }

        isMapExpandTransitioning = true
        if !expanding {
            withAnimation(TrailhoundMotion.gentle) {
                showExpandedMapChrome = false
            }
        }

        withAnimation(motion) {
            isMapExpanded = expanding
        }
        refitMapToVisibleGap(animated: true, animation: motion)

        mapExpandTransitionTask = Task { @MainActor in
            if expanding {
                try? await Task.sleep(for: .milliseconds(chromeFadeInMs))
                guard !Task.isCancelled else { return }
                withAnimation(TrailhoundMotion.gentle) {
                    showExpandedMapChrome = true
                }
                try? await Task.sleep(for: .milliseconds(durationMs - chromeFadeInMs))
            } else {
                try? await Task.sleep(for: .milliseconds(durationMs))
            }
            guard !Task.isCancelled else { return }
            isMapExpandTransitioning = false
        }
    }

    private var mapStyle: TripDetailMapStyle {
        mapStyleOverride ?? .matching(colorScheme)
    }

    private var expandedMapStylePicker: some View {
        Picker(L10n.mapStylePicker, selection: Binding(
            get: { mapStyle },
            set: { mapStyleOverride = $0 }
        )) {
            Text(L10n.mapStyleLight).tag(TripDetailMapStyle.standard)
            Text(L10n.mapStyleDark).tag(TripDetailMapStyle.dark)
        }
        .pickerStyle(.segmented)
        .glassSegmentedStyle()
        .frame(width: 180)
        .padding(8)
        .glassChrome(cornerRadius: 10, frozen: glassFrozen)
    }

    /// Upright Duo map: the phone caption reads large on the wide sheet.
    private var duoOverlaySheet: Bool {
        layout.layoutClass == .duoOpen && layout.tripDetailStyle == .overlay
    }

    private var compactSpeedLegend: some View {
        HStack(spacing: duoOverlaySheet ? 6 : 8) {
            legendChip(color: .green, text: L10n.speedLegendSlow)
            legendChip(color: .yellow, text: L10n.speedLegendMedium)
            legendChip(color: .red, text: L10n.speedLegendFast)
        }
        .padding(.horizontal, duoOverlaySheet ? 8 : 10)
        .padding(.vertical, duoOverlaySheet ? 4 : 6)
        .foregroundStyle(legendInk)
        .glassChrome(cornerRadius: 14, frozen: glassFrozen)
    }

    /// Light glass well over the map uses the white type hierarchy.
    private var legendInk: Color {
        GlassText.primary(for: colorScheme)
    }

    private func legendChip(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2)
                .scaleEffect(0.75)
        }
    }

    private func mapStops(showAll: Bool) -> [TripDetailMapStop] {
        let vm = resolvedViewModel
        return sortedStops.map { stop in
            TripDetailMapStop(
                id: String(describing: stop.persistentModelID),
                coordinate: stop.coordinate,
                revealProgress: showAll ? 0 : vm.annotationRevealProgress(forStopAt: stop.coordinate)
            )
        }
    }

    @ViewBuilder
    private func tripDetailMapLayer(
        interactive: Bool,
        revealProgress: Double? = nil,
        forceShowAllStops: Bool = false
    ) -> some View {
        let progress = revealProgress ?? routeRevealProgress
        let settled = progress >= TripDetailRevealOverlays.settleProgress
        let showStops = forceShowAllStops || showAllStops || settled
        let stroke = TripDetailRevealOverlays.stroke(
            progress: progress,
            coloredSegments: settled
                ? resolvedViewModel.revealedSpeedColoredSegments(progress: progress)
                : [],
            fallbackCoordinates: resolvedViewModel.revealedFallbackCoordinates(progress: progress)
        )

        TripDetailMapLayer(
            style: mapStyle,
            interactive: interactive,
            routeRevealProgress: progress,
            drawCasing: stroke.drawCasing,
            revealedItems: stroke.revealedItems,
            revealedFallback: stroke.revealedFallback,
            startCoordinate: resolvedViewModel.routeStartCoordinate,
            endCoordinate: resolvedViewModel.routeEndCoordinate,
            startPinVisible: revealProgress == nil ? startPinVisible : true,
            endPinVisible: revealProgress == nil ? endPinVisible : true,
            showAllStops: showStops,
            stops: mapStops(showAll: showStops),
            reduceMotion: reduceMotion,
            cameraBox: mapCameraBox
        )
        .equatable()
    }

    private func renderShareCard() async {
        guard !isRenderingShareCard else { return }
        isRenderingShareCard = true
        defer { isRenderingShareCard = false }

        let privacyRadius = settings.privacyRadiusMeters
        guard let image = await TripShareCardRenderer.render(
            trip: trip,
            places: places,
            privacyRadius: privacyRadius,
            palette: shellPalette,
            scheme: colorScheme
        ) else {
            AppErrorPresenter.shared.present(L10n.string("share.card.error"))
            return
        }
        shareImage = image
        shareCaption = TripShareCaption.build(
            trip: trip,
            places: places,
            privacyRadius: privacyRadius
        )
        showSharePreview = true
    }

    private func dismissEditKeyboard() {
        keyboardDismissSignal += 1
        KeyboardDismiss.dismiss()
    }

    private func refreshPersistedFuelEstimate() {
        guard TripDerivedMetrics.refreshPersistedFuel(for: trip, in: modelContext) else { return }
        try? modelContext.save()
        refreshTripDetailViewModel()
    }

    private func refreshTripDetailViewModel() {
        tripDetailViewModel = TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: TripDetailViewModel.reusablePieces(from: tripDetailViewModel, for: trip)
        )
    }

    private func reloadRouteAfterTrim() {
        routeLoadTask?.cancel()
        routeLoadTask = Task { @MainActor in
            await loadDisplayPathAndReveal()
        }
    }

    private func logTripDetailDiagnostics(context: String) {
        let points = trip.sortedPoints
        let speedPointCount = points.filter { ($0.speedMps ?? 0) > 0 }.count
        let sampleCount = resolvedViewModel.speedSamples.count
        // colorSegs = speed-band polylines; routePieces = real gap splits from RouteDisplayPath.
        let colorSegCount = resolvedViewModel.speedColoredSegments.count
        let routePieceCount = resolvedViewModel.displayPieces?.count ?? 0
        let routeGapCount = max(0, routePieceCount - 1)

        DevLog.shared.log(
            .tripDetail,
            "\(context) trip=\(trip.id.uuidString.prefix(8)) points=\(points.count) displayPts=\(resolvedViewModel.displayPointCount) speedPts=\(speedPointCount) chartSamples=\(sampleCount) routePieces=\(routePieceCount) routeGaps=\(routeGapCount) colorSegs=\(colorSegCount) reveal=\(Int(routeRevealProgress * 100))% chartReveal=\(Int(speedChartRevealProgress * 100))%"
        )

        if points.count >= 2, sampleCount == 0 {
            DevLog.shared.warning(
                .tripDetail,
                "speed chart hidden (no speedMps>0 samples); map may show single-color route"
            )
        }
        if routeRevealProgress < 0.95, context.hasPrefix("disappear") {
            DevLog.shared.warning(
                .tripDetail,
                "left detail before reveal finished — next open may flash empty until instant reveal"
            )
        }
    }
}

private struct TripSharePreviewSheet: View {
    let image: UIImage
    let caption: String?
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground().ignoresSafeArea()

                VStack(spacing: 16) {
                    TrailhoundBrandMark(showsWordmark: true, symbolSize: 44)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                        .padding(.horizontal, 20)

                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.footnote)
                            .glassSecondaryInk()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .lineLimit(4)
                    }

                    Button(action: onShare) {
                        Label(L10n.share, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .trailhoundProminentButton()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .padding(.top, 8)
            }
            .navigationTitle(L10n.shareCardPreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationChrome()
            .onGlassShell()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        GlassToolbarTitle(title: L10n.actionClose)
                    }
                }
            }
        }
    }
}

// MARK: - Speed chart route draw

struct SpeedChartRouteCanvas: View {
    let samples: [(id: Int, date: Date, speedKmh: Double)]
    let maxKmh: Double
    let progress: Double
    let tripStartedAt: Date
    let tripEndedAt: Date
    /// Typical spacing between plotted samples; the gap threshold scales off it.
    let sampleMedianIntervalSeconds: TimeInterval

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    private var gapBreakSeconds: TimeInterval {
        SpeedChartSeries.gapBreakSeconds(medianIntervalSeconds: sampleMedianIntervalSeconds)
    }

    private var brandColor: Color { shellPalette.tintColor(for: colorScheme) }

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 2
            let baselineY = size.height - inset
            let revealed = SpeedChartSeries.revealedSamples(
                from: samples.map { ($0.date, $0.speedKmh) },
                progress: progress,
                gapBreakSeconds: gapBreakSeconds
            )
            let points = SpeedChartSeries.strokePoints(
                samples: revealed,
                gapBreakSeconds: gapBreakSeconds,
                project: { date, speedKmh in
                    projectedPoint(date: date, speedKmh: speedKmh, in: size, inset: inset)
                },
                baselineY: baselineY
            )
            guard !points.isEmpty else { return }

            if points.count == 1 {
                var dot = Path()
                dot.addEllipse(in: CGRect(x: points[0].x - 2, y: points[0].y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(brandColor))
                return
            }

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.addLine(to: point)
            }

            var area = Path()
            area.move(to: CGPoint(x: points[0].x, y: baselineY))
            area.addLine(to: points[0])
            for point in points.dropFirst() {
                area.addLine(to: point)
            }
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [brandColor.opacity(0.28), brandColor.opacity(0.04)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                line,
                with: .color(brandColor.opacity(0.35)),
                style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                line,
                with: .color(brandColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            if progress < 0.995, let tip = points.last {
                var glow = Path()
                glow.addEllipse(in: CGRect(x: tip.x - 4.5, y: tip.y - 4.5, width: 9, height: 9))
                context.fill(glow, with: .color(brandColor.opacity(0.28)))

                var tipDot = Path()
                tipDot.addEllipse(in: CGRect(x: tip.x - 2.5, y: tip.y - 2.5, width: 5, height: 5))
                context.fill(tipDot, with: .color(brandColor))
                context.stroke(tipDot, with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private func projectedPoint(date: Date, speedKmh: Double, in size: CGSize, inset: CGFloat) -> CGPoint {
        let dateSpan = max(tripEndedAt.timeIntervalSince(tripStartedAt), 1)
        let drawWidth = max(size.width - inset * 2, 1)
        let drawHeight = max(size.height - inset * 2, 1)
        let baselineY = size.height - inset
        let speedMax = max(maxKmh, 1)
        let xFraction = date.timeIntervalSince(tripStartedAt) / dateSpan
        let yFraction = min(1, max(0, speedKmh / speedMax))
        return CGPoint(
            x: inset + CGFloat(xFraction) * drawWidth,
            y: baselineY - CGFloat(yFraction) * drawHeight
        )
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: PreviewData.sampleTrip)
    }
    .modelContainer(PreviewData.shared.container)
    .environment(NetworkMonitor.shared)
}
