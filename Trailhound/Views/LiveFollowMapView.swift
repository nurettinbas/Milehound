import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

/// Optional full-screen live follow while a trip is recording.
///
/// Presented from the trips list; does not own recording lifecycle. Open fades the map in
/// while the road vehicle mark flies into the nav puck. Close expands the HUD then rises.
struct LiveFollowMapView: View {
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String = "car.fill"
    /// Card + road-vehicle frames for close morph / open hero flight.
    var cardAnchor: RecordingCardAnchor
    /// Split / fold pane. The map fills that pane; the HUD stays inside it.
    var fillsPane: Bool = false
    /// Upright fold only. The Apple Maps mark sits in the pane's bottom corner, on the hinge.
    var pinsAttributionToBottomCorner: Bool = false
    /// False while another tab is selected. The trips page stays mounted.
    var isSceneVisible: Bool = true
    var onClose: () -> Void
    var onStop: (RecordingCardAnchor) -> Void

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(LocationService.self) private var locationService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.foldPaneHeaderBottom) private var foldHeaderBottom
    @Environment(\.layoutDirection) private var layoutDirection
    @Bindable private var settings = AppSettings.shared

    @State private var session = LiveFollowSession()
    @State private var isFollowing = true
    @State private var mapClarity: Double = 0
    @State private var chromeReveal: Double = 0
    /// 0 = road vehicle at list card; 1 = nav puck on the map.
    @State private var heroFlight: CGFloat = 0
    @State private var heroOpacity: Double = 1
    /// Keeps the SwiftUI hero mounted during the open handoff crossfade.
    @State private var showHeroOverlay = true
    @State private var puckRevealed = false
    /// MapKit puck alpha — crossfades with `heroOpacity` at handoff.
    @State private var puckAlpha: CGFloat = 1
    @State private var puckFadeToken = 0
    /// Map-projected puck circle center (overlay-local). Locked once before the open flight.
    @State private var projectedHeroDest: CGPoint?
    @State private var lockProjectedHeroDest = false
    @State private var mapMounted = false
    @State private var isClosing = false
    /// After open handoff finishes — MapKit puck pulse / chrome settle. Follow camera
    /// already runs during the hero flight so the landing cannot drift at speed.
    @State private var openSettled = false
    @State private var hudAnchorBox = RecordingCardAnchorBox()
    @State private var displayLink = DisplayLinkClock()
    @State private var pausePinCoordinates: [CLLocationCoordinate2D] = []
    @State private var wasPaused = false
    @State private var idleLockHeld = false
    /// Local 2D/3D mirror — avoids rebuilding the MapKit host on every settings write.
    @State private var uses3DLocal = true
    /// Bumped to ask MapKit to fit start + traveled path + puck (north-up 2D).
    @State private var overviewRequestToken = 0
    @State private var recenterRequestToken = 0
    /// First recorded breadcrumb — kept for the cover's lifetime so the start flag
    /// cannot vanish if the live array is briefly empty.
    @State private var latchedStartCoordinate: CLLocationCoordinate2D?
    @State private var showsDestinationSheet = false
    @State private var routeCardCollapsed = false
    @Namespace private var destinationZoom
    @Environment(\.modelContext) private var modelContext

    private var uses3D: Bool { uses3DLocal }

    private var isPaused: Bool {
        recordingService.state == .paused
    }

    private var tipCoordinate: CLLocationCoordinate2D? {
        session.vehicleCoordinate
            ?? locationService.lastLocation?.coordinate
            ?? recordingService.liveBreadcrumbCoordinates.last
    }

    private var startPinCoordinate: CLLocationCoordinate2D? {
        // Read the fallback only when needed — touching `lastLocation` here would
        // subscribe the whole body to every GPS fix.
        if let latched = latchedStartCoordinate { return latched }
        return LiveFollowMapPinBuilder.resolvedStartCoordinate(
            latched: nil,
            breadcrumbStart: recordingService.liveBreadcrumbCoordinates.first,
            fallback: locationService.lastLocation?.coordinate
        )
    }

    private var tripStopCoordinates: [CLLocationCoordinate2D] {
        recordingService.liveStopCoordinates
    }

    private var mapPins: [LiveFollowMapPin] {
        LiveFollowMapPinBuilder.pins(
            startCoordinate: startPinCoordinate,
            pauseCoordinates: pausePinCoordinates,
            tripStopCoordinates: tripStopCoordinates,
            destinationCoordinate: recordingService.plannedRoute.destination?.coordinate
        )
    }

    /// Hero overlay while flying / crossfading onto the map puck.
    private var showHeroFlight: Bool {
        showHeroOverlay
    }

    /// `GeometryReader` under `.ignoresSafeArea()` reports zero insets — read the key window instead.
    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    var body: some View {
        GeometryReader { geo in
            let safe = windowSafeInsets
            let topInset = max(geo.safeAreaInsets.top, safe.top)
            let bottomInset = max(geo.safeAreaInsets.bottom, safe.bottom)
            let containerGlobal = geo.frame(in: .global)
            let sourceGlobal = LiveFollowPresentation.sourceRect(
                from: cardAnchor,
                fallbackContainer: containerGlobal
            )
            let origin = containerGlobal.origin
            let heroSourceGlobal = LiveFollowPresentation.heroSourceRect(
                from: cardAnchor,
                cardFallback: sourceGlobal
            )
            let heroSourceLocal = heroSourceGlobal.offsetBy(dx: -origin.x, dy: -origin.y)
            let heroDest = projectedHeroDest
                ?? LiveFollowPresentation.heroDestCenter(in: geo.size, uses3D: uses3D)
            let dimOpacity = mapMounted ? 0.42 * (1 - mapClarity) : 0.0

            ZStack(alignment: .topLeading) {
                // Transparent cover must still eat taps so the trips list underneath cannot scroll.
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                if mapMounted {
                    mapLayer
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .opacity(mapClarity)

                    if isPaused {
                        pausedOverlay
                            .transition(.opacity)
                    }
                }

                Color.black.opacity(dimOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            // Chrome + hero above MapKit (Map often ignores sibling z-order).
            .overlay {
                ZStack {
                    settledChromeStack(
                        topInset: topInset,
                        bottomInset: bottomInset,
                        leadingInset: leadingChromeInset(safe: safe),
                        hudLeadingInset: hudLeadingInset(safe: safe),
                        gpsClearance: gpsCameraClearance(safe: safe),
                        controlLift: duoCoverControlLift(safe: safe)
                    )

                    CardExpandBackSwipeStrip(
                        enabled: !isClosing,
                        topClearance: topInset + CardExpandBackSwipe.headerClearance,
                        onClose: { beginClose() }
                    )
                    .zIndex(3)

                    if showHeroFlight {
                        LiveFollowVehicleHero(
                            progress: heroFlight,
                            sourceLocal: heroSourceLocal,
                            destCenter: heroDest,
                            vehiclePhoto: vehiclePhoto,
                            vehicleSystemImage: vehicleSystemImage,
                            plateColor: liveFollowPlateColor,
                            chevronColors: liveFollowChevronColors
                        )
                        .opacity(heroOpacity)
                        .allowsHitTesting(false)
                        .zIndex(40)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isSceneVisible ? 1 : 0)
        .animation(nil, value: isSceneVisible)
        .allowsHitTesting(isSceneVisible)
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: isPaused)
        .statusBarHidden(false)
        .onAppear {
            uses3DLocal = settings.liveFollowMap3DEnabled
            latchStartCoordinateIfNeeded()
            retainIdleLock()
            wasPaused = isPaused
            runOpenSequence()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_800))
                guard !isClosing else { return }
                forceOpenSettledIfNeeded()
            }
        }
        .onDisappear {
            stopDisplayLink()
            releaseIdleLock()
        }
        .onChange(of: mapMounted) { _, mounted in
            if mounted {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }
        .onChange(of: isFollowing) { _, value in
            session.isFollowing = value
        }
        .onChange(of: openSettled) { _, value in
            session.openSettled = value
        }
        .onChange(of: isClosing) { _, value in
            session.isClosing = value
        }
        .onChange(of: isPaused) { _, paused in
            session.isPaused = paused
            handlePauseChromeChange(paused)
        }
        .onChange(of: reduceMotion) { _, value in
            session.reduceMotion = value
        }
        .onChange(of: recordingService.state.isActiveSession) { _, isActive in
            if !isActive {
                // Parent clears the cover; skip reverse morph (list card is gone).
                onClose()
            }
        }
        .onChange(of: settings.liveFollowMap3DEnabled) { _, enabled in
            guard mapMounted else { return }
            guard uses3DLocal != enabled else { return }
            uses3DLocal = enabled
            session.applyDimensionMode(enabled)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { beginClose() }
        .toolbar {
            if placesBackInHeader {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        TrailhoundHaptics.selection()
                        beginClose()
                    } label: {
                        GlassToolbarSymbol(systemName: "chevron.backward")
                    }
                    .accessibilityLabel(L10n.string("onboarding.back"))
                    .accessibilityIdentifier("liveMap.close")
                }
            }
        }
        .sheet(isPresented: $showsDestinationSheet) {
            LiveFollowDestinationSheet(
                currentDestination: recordingService.plannedRoute.destination,
                searchCenter: routeOrigin,
                onPick: { destination in
                    recordingService.plannedRoute.setDestination(destination, origin: routeOrigin)
                    setDestinationSheet(false)
                },
                onClear: {
                    recordingService.plannedRoute.clear()
                    setDestinationSheet(false)
                },
                onDismiss: { setDestinationSheet(false) }
            )
            .environment(recordingService)
            .environment(\.trailhoundLayout, layout)
            .environment(\.shellPalette, shellPalette)
            .modelContext(modelContext)
            .glassSheetZoom(from: LiveFollowDestinationSheet.zoomID, in: destinationZoom)
        }
    }

    private func setDestinationSheet(_ shown: Bool) {
        var transaction = Transaction()
        transaction[LiveFollowSheetTransition.self] = true
        withTransaction(transaction) {
            showsDestinationSheet = shown
        }
    }

    /// Where the planned route starts: the live vehicle, else the last fix or breadcrumb.
    /// UI tests on a simulator without GPS use a fixed seed origin.
    private var routeOrigin: CLLocationCoordinate2D? {
        tipCoordinate ?? (UITestSupport.seedsPlannedRoute ? UITestSupport.plannedRouteSeedOrigin : nil)
    }

    private func settledChromeStack(
        topInset: CGFloat,
        bottomInset: CGFloat,
        leadingInset: CGFloat,
        hudLeadingInset: CGFloat,
        gpsClearance: CGFloat,
        controlLift: CGFloat
    ) -> some View {
        let hudBottom = pinsHUDToLeadingCorner
            ? LiveFollowPresentation.settledBottomPadding + (landscapeDuoCover ? 10 : 28)
            : LiveFollowPresentation.settledBottomPadding + bottomInset
        let portraitCoverDrop: CGFloat = portraitDuoCover ? 16 : 0
        let chromeTop = topInset + 8 + portraitCoverDrop
        let coverCameraLeads = landscapeDuoCover && leadingInset > 12
        let backTop: CGFloat = if !landscapeDuoCover {
            chromeTop
        } else if coverCameraLeads {
            duoCoverBackTop(topInset: topInset, leadingInset: leadingInset)
        } else {
            max(topInset, 22)
        }
        let cardLeading = (landscapeDuoCover ? 10 : leadingInset) + 52
        // The title bar can sit below the safe top, and Back is in that bar.
        let cardTop: CGFloat = if coverCameraLeads {
            max(topInset, 32)
        } else if placesBackInHeader {
            max(backTop, foldHeaderBottom + 8)
        } else {
            backTop
        }
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
            topChrome(gpsClearance: gpsClearance, showsBack: !landscapeDuoCover && !placesBackInHeader)
                .padding(.leading, leadingInset)
                .padding(.trailing, GlassTokens.panelHorizontalInset)
                .padding(.top, chromeTop)
                .opacity(chromeReveal)
                .zIndex(2)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
            LiveFollowHUD(
                tight: layout.isLandscape || landscapeDuoCover,
                    isPaused: isPaused,
                    uses3D: uses3DLocal,
                    isFollowing: isFollowing,
                    stats: nil,
                    onPause: { togglePause() },
                    onStop: {
                        onStop(hudAnchorBox.value.width > 0 ? hudAnchorBox.value : cardAnchor)
                    },
                    onSelectDimension: { setDimensionMode($0) },
                    onOverview: { requestOverview() },
                    onRecenter: { requestRecenter() },
                    trailingColumnLift: controlLift
                ) {
                    EmptyView()
                }
                .background {
                    GeometryReader { geo in
                        let frame = geo.frame(in: .global)
                        Color.clear
                            .onAppear { updateHUDAnchor(frame) }
                            .onChange(of: frame.origin.y) { _, _ in updateHUDAnchor(frame) }
                            .onChange(of: frame.size.width) { _, _ in updateHUDAnchor(frame) }
                            .onChange(of: frame.size.height) { _, _ in updateHUDAnchor(frame) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, hudLeadingInset)
            .padding(.trailing, 12)
            .padding(.bottom, hudBottom)
                .opacity(chromeReveal)
            }
            destinationCard(
                top: cardTop,
                leading: cardLeading,
                trailing: landscapeDuoCover ? 12 : 76
            )
                .opacity(chromeReveal)
                .zIndex(2)

            if landscapeDuoCover {
                backButton
                    .padding(.leading, 10)
                    .padding(.top, backTop)
                    .opacity(chromeReveal)
                    .zIndex(3)
            }
        }
    }

    /// Portrait cover: 19% shorter than the gap between Back and the camera, centered in that gap.
    private struct PortraitCoverDestinationCenter: ViewModifier {
        var leading: CGFloat
        var camera: CGFloat
        var fraction: CGFloat

        func body(content: Content) -> some View {
            PortraitCoverDestinationLayout(leading: leading, camera: camera, fraction: fraction) {
                content
            }
        }
    }

    private struct PortraitCoverDestinationLayout: Layout {
        var leading: CGFloat
        var camera: CGFloat
        var fraction: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let child = subviews.first else { return .zero }
            let offered = proposal.width ?? child.sizeThatFits(.unspecified).width
            let slot = max(0, offered - leading - camera)
            let childWidth = slot * fraction
            let size = child.sizeThatFits(ProposedViewSize(width: childWidth, height: nil))
            return CGSize(width: offered, height: size.height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard let child = subviews.first else { return }
            let slot = max(0, bounds.width - leading - camera)
            let childWidth = slot * fraction
            let size = child.sizeThatFits(ProposedViewSize(width: childWidth, height: nil))
            let x = bounds.minX + leading + (slot - childWidth) / 2
            child.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: childWidth, height: size.height)
            )
        }
    }

    /// Closed portrait cover is a short phone. The corner camera sits lower than the status inset.
    private var portraitDuoCover: Bool {
        !layout.isLandscape
            && layout.layoutClass == .phone
            && layout.centersOnboardingColumn
    }

    /// Closed landscape cover: the card sits on the trailing side, its right edge on Stop’s inset.
    @ViewBuilder
    private func destinationCard(top: CGFloat, leading: CGFloat, trailing: CGFloat) -> some View {
        let card = LiveFollowRouteCard(
            plannedRoute: recordingService.plannedRoute,
            isCollapsed: $routeCardCollapsed,
            collapsedAlignment: landscapeDuoCover ? .trailing : .leading
        ) {
            setDestinationSheet(true)
        }
        .glassSheetZoomSource(id: LiveFollowDestinationSheet.zoomID, in: destinationZoom)
        if landscapeDuoCover {
            card
                .containerRelativeFrame(.horizontal) { width, _ in
                    max(0, width - 24) * 0.85 * 0.70
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .padding(.top, top)
        } else if portraitDuoCover {
            card
                .modifier(
                    PortraitCoverDestinationCenter(
                        leading: leading,
                        camera: 92,
                        fraction: 0.81
                    )
                )
                .padding(.top, top)
        } else if placesBackInHeader {
            card
                .containerRelativeFrame(.horizontal) { width, _ in
                    max(0, width - leading - trailing) * 0.70 * 0.85
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, top)
        } else {
            card
                .padding(.leading, leading)
                .padding(.trailing, trailing)
                .padding(.top, top)
        }
    }

    /// Closed landscape cover. Pause and Stop lift only when the punch hole is in the
    /// trailing corner. A top-leading camera leaves them on the bottom edge.
    private func duoCoverControlLift(safe: UIEdgeInsets) -> CGFloat {
        guard landscapeDuoCover else { return 0 }
        let trailing = layoutDirection == .rightToLeft ? safe.left : safe.right
        let leading = layoutDirection == .rightToLeft ? safe.right : safe.left
        guard trailing > leading, trailing > 20 else { return 0 }
        return min(max(trailing, 52), 88)
    }

    /// Closed landscape cover: the punch hole owns the top corner. The circle sits under it.
    private func duoCoverBackTop(topInset: CGFloat, leadingInset: CGFloat) -> CGFloat {
        let holeBand = leadingInset > 12 ? leadingInset : 52
        return max(topInset, holeBand) + 6
    }

    private var mapLayer: some View {
        LiveFollowMapKitView(
            pinsAttributionToBottomCorner: pinsAttributionToBottomCorner,
            centersOnScreenMidpoint: true,
            session: session,
            isFollowing: isFollowing && !isClosing,
            isPaused: isPaused,
            hudAnchor: hudAnchorBox,
            overviewRequestToken: overviewRequestToken,
            recenterRequestToken: recenterRequestToken,
            pins: mapPins,
            vehiclePhoto: vehiclePhoto,
            vehicleSystemImage: vehicleSystemImage,
            puckRevealed: puckRevealed,
            puckAlpha: puckAlpha,
            puckFadeToken: puckFadeToken,
            isMoving: openSettled && !isPaused,
            onUserBreakFollow: {
                guard !isPaused, isFollowing else { return }
                isFollowing = false
                session.isFollowing = false
            },
            onPuckCircleScreenPoint: { point in
                guard !lockProjectedHeroDest else { return }
                Task { @MainActor in
                    guard !self.lockProjectedHeroDest else { return }
                    if self.projectedHeroDest == nil {
                        self.projectedHeroDest = point
                    } else if let current = self.projectedHeroDest,
                              abs(current.x - point.x) > 0.5
                                || abs(current.y - point.y) > 0.5
                    {
                        self.projectedHeroDest = point
                    }
                }
            },
            routeStrokeColor: LiveFollowRouteStrokeStyle.solidColor(
                for: shellPalette,
                scheme: colorScheme
            ),
            puckPlateColor: UIColor(liveFollowPlateColor),
            puckChevronColors: liveFollowChevronColors.map { UIColor($0) },
            themeSignature: "\(shellPalette.rawValue)-\(colorScheme == .dark ? "d" : "l")",
            isSceneVisible: isSceneVisible
        )
    }

    /// Full-screen wash + centered pause callout. Pass-through so Resume/Stop stay tappable.
    private var pausedOverlay: some View {
        ZStack {
            Color.orange.opacity(0.16)
                .ignoresSafeArea()

            pauseStatusChip(font: .title3.weight(.bold), iconSize: 22, horizontal: 18, vertical: 10)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .allowsHitTesting(false)
    }

    /// Opaque amber + white type — glass + `.primary` washes out on a light map.
    private func pauseStatusChip(
        font: Font,
        iconSize: CGFloat,
        horizontal: CGFloat,
        vertical: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: iconSize, weight: .semibold))
            Text(L10n.recordingPaused)
                .font(font)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, horizontal)
        .padding(.vertical, vertical)
        .background(TrailhoundBrandColors.paused, in: Capsule())
        .compositingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.recordingPaused)
    }

    private var backButton: some View {
        Button {
            TrailhoundHaptics.selection()
            beginClose()
        } label: {
            GlassNavCircleIcon(systemName: "chevron.backward")
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(L10n.string("onboarding.back"))
        .accessibilityIdentifier("liveMap.close")
    }

    private func topChrome(gpsClearance: CGFloat, showsBack: Bool) -> some View {
        HStack(spacing: 8) {
            if showsBack {
                backButton
            }

            if isPaused {
                pauseStatusChip(font: .caption.weight(.bold), iconSize: 13, horizontal: 8, vertical: 6)
                    .fixedSize(horizontal: true, vertical: true)
            }

            if showsGPSBadge, gpsBadgeLeads {
                gpsBadge
            }

            Spacer(minLength: 4)

            if !networkMonitor.isConnected, recordingService.plannedRoute.destination == nil {
                Text(L10n.tripMapOfflineHint)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassChrome(cornerRadius: 14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if showsGPSBadge, !gpsBadgeLeads {
                gpsBadge
                    .padding(.trailing, gpsClearance)
            }
        }
    }

    /// Phone and iPad: on the leading edge, beside Back. The open Duo and the
    /// closed landscape cover keep it trailing, clear of the corner camera.
    private var gpsBadgeLeads: Bool {
        layout.layoutClass != .duoOpen && !landscapeDuoCover
    }

    /// "GPS good" stays off the map. Weak and lost still show.
    private var showsGPSBadge: Bool {
        session.displayedGPSQuality != .good
    }

    private var gpsBadge: some View {
        GPSQualityBadge(quality: session.displayedGPSQuality, compact: true)
            .fixedSize(horizontal: true, vertical: true)
    }

    /// Camera hole on the leading edge: the top row clears it. The stat stack sits lower, beside empty bezel, so it does not.
    private func leadingChromeInset(safe: UIEdgeInsets) -> CGFloat {
        let hole = layoutDirection == .rightToLeft ? safe.right : safe.left
        if hole >= 44 { return hole + 8 }
        return 12
    }

    /// Duration, speed, and distance. Landscape keeps them on the pane edge in both rotations.
    private func hudLeadingInset(safe: UIEdgeInsets) -> CGFloat {
        if layout.isLandscape { return 8 }
        return leadingChromeInset(safe: safe)
    }

    /// The punch-hole sits in the trailing corner, and the map ignores that inset.
    /// Landscape reports it as the side safe area; portrait does not, so keep a fixed nudge.
    private func gpsCameraClearance(safe: UIEdgeInsets) -> CGFloat {
        let trailing = layoutDirection == .rightToLeft ? safe.left : safe.right
        if trailing >= 20 { return trailing + 36 }
        guard layout.pinsOverlayCloseLeading else { return 0 }
        return layout.isLandscape ? 64 : 72
    }

    private func togglePause() {
        let toggle = {
            if isPaused {
                recordingService.resumeRecording()
            } else {
                recordingService.pauseRecording()
            }
        }
        if reduceMotion {
            toggle()
        } else {
            withAnimation(TrailhoundMotion.recordingToggle) {
                toggle()
            }
        }
    }

    private func setDimensionMode(_ enabled3D: Bool) {
        uses3DLocal = enabled3D
        settings.liveFollowMap3DEnabled = enabled3D
        session.applyDimensionMode(enabled3D)
    }

    private func requestOverview() {
        isFollowing = false
        session.isFollowing = false
        overviewRequestToken += 1
    }

    private func requestRecenter() {
        isFollowing = true
        session.isFollowing = true
        session.applyDimensionMode(uses3DLocal)
        recenterRequestToken += 1
    }

    /// Open upright Duo. The back circle belongs in the window title bar, not on the map.
    private var placesBackInHeader: Bool {
        layout.pinsRecordingCardToFold
    }

    /// Closed landscape Duo. The cover is the whole screen, so the card stays small and leading.
    private var landscapeDuoCover: Bool {
        !fillsPane && layout.layoutClass == .phoneLandscape && !layout.isPhoneBook
    }

    private var pinsHUDToLeadingCorner: Bool {
        layout.isLandscape || pinsAttributionToBottomCorner || landscapeDuoCover
    }

    @MainActor
    private func runOpenSequence() {
        // Lock camera to the follow pose BEFORE Map appears — never fade in from .automatic.
        openSettled = false
        mapClarity = 0
        chromeReveal = 0
        heroFlight = 0
        heroOpacity = 1
        showHeroOverlay = true
        puckRevealed = false
        puckAlpha = 1
        projectedHeroDest = nil
        lockProjectedHeroDest = false
        prepareMapMount()

        if reduceMotion {
            mapClarity = 1
            chromeReveal = 1
            heroFlight = 1
            heroOpacity = 0
            showHeroOverlay = false
            puckAlpha = 1
            puckRevealed = true
            openSettled = true
            lockProjectedHeroDest = true
            return
        }

        // One shared fade for map + hero so they stay synchronized (tiles can catch up underneath).
        Task { @MainActor in
            // Let MapKit paint the first frame at the final camera while still invisible,
            // and publish a projected landing pixel for the hero arc.
            try? await Task.sleep(for: .milliseconds(50))
            guard !isClosing else { return }
            try? await Task.sleep(for: .milliseconds(16))
            guard !isClosing else { return }
            lockProjectedHeroDest = true
            withAnimation(
                TrailhoundMotion.liveFollowReveal,
                completionCriteria: .logicallyComplete
            ) {
                mapClarity = 1
                chromeReveal = 1
                heroFlight = 1
            } completion: {
                guard !self.isClosing else { return }
                Task { @MainActor in
                    await self.runOpenHandoff()
                }
            }
        }
    }

    /// Reveal MapKit puck under the hero and crossfade. Follow camera is already live.
    @MainActor
    private func runOpenHandoff() async {
        guard !isClosing else { return }
        // Add puck invisible under the hero; give MapKit a beat to materialize the view.
        puckAlpha = 0
        puckRevealed = true
        try? await Task.sleep(for: .milliseconds(32))
        guard !isClosing else { return }

        puckFadeToken += 1
        puckAlpha = 1
        withAnimation(
            TrailhoundMotion.liveFollowHandoff,
            completionCriteria: .logicallyComplete
        ) {
            heroOpacity = 0
        } completion: {
            guard !self.isClosing else { return }
            self.showHeroOverlay = false
            self.openSettled = true
        }
    }

    /// If the open-handoff animation completion never fires, still reveal the map and unlock follow.
    @MainActor
    private func forceOpenSettledIfNeeded() {
        guard !isClosing else { return }
        if mapClarity < 1 { mapClarity = 1 }
        if chromeReveal < 1 { chromeReveal = 1 }
        if heroOpacity > 0 { heroOpacity = 0 }
        if showHeroOverlay { showHeroOverlay = false }
        if puckAlpha < 1 { puckAlpha = 1 }
        if !puckRevealed { puckRevealed = true }
        if !openSettled { openSettled = true }
        lockProjectedHeroDest = true
    }

    /// Inserts the map tree after the follow camera is already written (no world→local fly-in).
    @MainActor
    private func prepareMapMount() {
        guard !isClosing, !mapMounted else { return }
        bootstrapCamera()
        latchStartCoordinateIfNeeded()
        mapMounted = true
    }

    @MainActor
    private func beginClose() {
        guard !isClosing else { return }
        isClosing = true
        openSettled = false
        stopDisplayLink()
        releaseIdleLock()

        if reduceMotion {
            showHeroOverlay = true
            heroOpacity = 1
            heroFlight = 1
            puckRevealed = false
            puckAlpha = 1
            mapClarity = 0
            chromeReveal = 0
            heroFlight = 0
            mapMounted = false
            onClose()
            return
        }

        Task { @MainActor in
            await runCloseHandoffThenFlight()
        }
    }

    /// Crossfade MapKit puck → SwiftUI hero, then fly the hero back to the list card.
    @MainActor
    private func runCloseHandoffThenFlight() async {
        // Remount hero at the landing spot, invisible, then fade it in over the puck.
        showHeroOverlay = true
        heroFlight = 1
        heroOpacity = 0

        puckFadeToken += 1
        puckAlpha = 0
        withAnimation(
            TrailhoundMotion.liveFollowHandoff,
            completionCriteria: .logicallyComplete
        ) {
            heroOpacity = 1
        } completion: {
            Task { @MainActor in
                guard self.isClosing else { return }
                self.puckRevealed = false
                self.puckAlpha = 1
                withAnimation(
                    TrailhoundMotion.liveFollowReveal,
                    completionCriteria: .logicallyComplete
                ) {
                    self.mapClarity = 0
                    self.chromeReveal = 0
                    self.heroFlight = 0
                } completion: {
                    self.mapMounted = false
                    self.onClose()
                }
            }
        }
    }

    private func updateHUDAnchor(_ frame: CGRect) {
        guard frame.width > 0 else { return }
        hudAnchorBox.value = RecordingCardAnchor(
            minX: frame.minX,
            minY: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    private func bootstrapCamera() {
        session.locationService = locationService
        session.recordingService = recordingService
        session.isPaused = isPaused
        session.isFollowing = isFollowing
        session.openSettled = openSettled
        session.isClosing = isClosing
        session.bootstrap(
            uses3D: uses3D,
            reduceMotion: reduceMotion,
            location: locationService.lastLocation,
            tip: recordingService.liveBreadcrumbCoordinates.last
        )
        session.setDisplayedGPSQuality(locationService.gpsQuality)
    }

    @MainActor
    private func startDisplayLink() {
        syncSessionFlags()
        displayLink.onTick = { [session] dt in
            session.handleDisplayTick(dt: dt)
            // Start pin fallback for a session opened before the first breadcrumb —
            // latched here (not via onChange) so the body never observes breadcrumbs.
            if latchedStartCoordinate == nil {
                latchStartCoordinateIfNeeded()
            }
        }
        displayLink.start()
    }

    @MainActor
    private func stopDisplayLink() {
        displayLink.stop()
        displayLink.onTick = nil
    }

    private func syncSessionFlags() {
        session.locationService = locationService
        session.recordingService = recordingService
        session.isPaused = isPaused
        session.isFollowing = isFollowing
        session.openSettled = openSettled
        session.isClosing = isClosing
        session.uses3D = uses3D
        session.reduceMotion = reduceMotion
    }

    private func handlePauseChromeChange(_ paused: Bool) {
        defer { wasPaused = paused }
        guard paused, !wasPaused else { return }
        if let coordinate = tipCoordinate {
            pausePinCoordinates.append(coordinate)
        }
    }

    private func retainIdleLock() {
        guard !idleLockHeld else { return }
        ScreenIdleLock.shared.retain()
        idleLockHeld = true
    }

    private func releaseIdleLock() {
        guard idleLockHeld else { return }
        ScreenIdleLock.shared.release()
        idleLockHeld = false
    }

    private func latchStartCoordinateIfNeeded() {
        if latchedStartCoordinate == nil,
           let first = recordingService.liveBreadcrumbCoordinates.first
        {
            latchedStartCoordinate = first
        }
    }

    private var liveFollowPlateColor: Color {
        shellPalette.tintColor(for: colorScheme)
    }

    private var liveFollowChevronColors: [Color] {
        let atm = shellPalette.atmosphere(for: colorScheme)
        return [atm.glow.color, atm.tint.color, atm.chrome.color]
    }

    /// Map recorded GPS runs onto polyline segments. Runs are already split at gaps;
    /// pieces with fewer than two points cannot form a stroke and are dropped.
    ///
    /// The live map no longer routes geometry through SwiftUI at all (the coordinator
    /// pulls it from the session on display ticks); this stays as the pure mapping
    /// used by tests and any future list-side consumers.
    static func polylineSegments(
        from liveSegments: [[CLLocationCoordinate2D]]
    ) -> [LiveFollowPolylineSegment] {
        liveSegments.enumerated().compactMap { index, coords in
            guard coords.count >= 2 else { return nil }
            return LiveFollowPolylineSegment(id: "live-\(index)-0", coordinates: coords)
        }
    }
}

/// Open hero: road vehicle mark flies from the recording card into the nav-puck look.
///
/// Arc placement uses `LiveFollowHeroArcPlacement` (`AnimatableModifier`) so SwiftUI
/// samples the Bezier each frame — a View-level `Animatable` conformance trips Swift 6
/// main-actor isolation with `UIImage`.
struct LiveFollowVehicleHero: View {
    var progress: CGFloat
    var sourceLocal: CGRect
    var destCenter: CGPoint
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var plateColor: Color
    var chevronColors: [Color]

    private let puckCircle: CGFloat = 56
    private let chevronSize = CGSize(width: 52, height: 38)
    private let chevronOverlap: CGFloat = 18

    var body: some View {
        let t = LiveFollowPresentation.clampedProgress(progress)
        let side = LiveFollowPresentation.lerp(
            max(min(sourceLocal.width, sourceLocal.height) * 0.55, 36),
            puckCircle,
            t
        )
        let puckChrome = t
        let frameHeight = side + chevronSize.height - chevronOverlap * puckChrome + 14
        let frameWidth = max(side, chevronSize.width) + 24

        ZStack(alignment: .top) {
            Circle()
                .fill(Color.black.opacity(0.22 * puckChrome))
                .frame(width: side + 10, height: side + 10)

            ZStack {
                Circle()
                    .fill(plateColor)

                if let vehiclePhoto {
                    Image(uiImage: vehiclePhoto)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: vehicleSystemImage)
                        .font(.system(size: side * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side * (1 - 0.12 * puckChrome), height: side * (1 - 0.12 * puckChrome))
            .clipShape(Circle())
            .padding(LiveFollowPresentation.lerp(0, 8, t))
            .background {
                Circle()
                    .fill(plateColor)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35 + 0.65 * puckChrome), lineWidth: 2 + 3 * puckChrome)
            }
            .frame(width: side, height: side)

            LiveFollowNavChevron()
                .fill(
                    LinearGradient(
                        colors: chevronColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    LiveFollowNavChevron()
                        .stroke(
                            .white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(width: chevronSize.width, height: chevronSize.height)
                .offset(y: side - chevronOverlap * puckChrome)
                .opacity(puckChrome)
                .scaleEffect(0.7 + 0.3 * puckChrome, anchor: .top)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .frame(width: frameWidth, height: frameHeight)
        .modifier(
            LiveFollowHeroArcPlacement(
                progress: progress,
                from: CGPoint(x: sourceLocal.midX, y: sourceLocal.midY),
                to: destCenter,
                sourceSide: max(min(sourceLocal.width, sourceLocal.height) * 0.55, 36),
                puckSide: puckCircle,
                chevronHeight: chevronSize.height,
                chevronOverlap: chevronOverlap
            )
        )
        .accessibilityHidden(true)
    }
}

/// Samples the Bezier path as `progress` animates (avoids straight-line `.position` lerp).
private struct LiveFollowHeroArcPlacement: AnimatableModifier {
    var progress: CGFloat
    var from: CGPoint
    var to: CGPoint
    var sourceSide: CGFloat
    var puckSide: CGFloat
    var chevronHeight: CGFloat
    var chevronOverlap: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = LiveFollowPresentation.clampedProgress(progress)
        let circleCenter = LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: t)
        let side = LiveFollowPresentation.lerp(sourceSide, puckSide, t)
        let frameHeight = side + chevronHeight - chevronOverlap * t + 14
        let frameCenterY = circleCenter.y + (frameHeight / 2 - side / 2)
        content.position(x: circleCenter.x, y: frameCenterY)
    }
}

/// Circle photo badge with a filled heading chevron overlapping the bottom — matches the live-map puck.
struct LiveFollowPuckMark: View {
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var isMoving: Bool
    var reduceMotion: Bool
    var plateColor: Color
    var chevronColors: [Color]

    private let circleSize: CGFloat = 56
    private let photoBorder: CGFloat = 5
    /// Air between the photo and the inner edge of the white ring.
    private let photoGap: CGFloat = 3
    private let chevronSize = CGSize(width: 52, height: 38)
    /// How far the chevron sits up onto the circle.
    private let chevronOverlap: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                photoBadge
                    .frame(width: circleSize, height: circleSize)

                filledChevron
                    .frame(width: chevronSize.width, height: chevronSize.height)
                    .offset(y: circleSize - chevronOverlap)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.36), radius: 6, y: 3)
        }
        .frame(
            width: max(circleSize, chevronSize.width) + 24,
            height: circleSize + chevronSize.height - chevronOverlap + 14
        )
        .offset(y: -circleSize / 2 + 8)
        .accessibilityHidden(true)
    }

    private var filledChevron: some View {
            LiveFollowNavChevron()
            .fill(
                LinearGradient(
                    colors: chevronColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                LiveFollowNavChevron()
                    .stroke(
                        .white,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
    }

    private var photoBadge: some View {
        ZStack {
            Circle()
                .fill(plateColor)

            photoContent
                .padding(photoBorder + photoGap)
                .clipShape(Circle())

            Circle()
                .strokeBorder(.white, lineWidth: photoBorder)
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if let vehiclePhoto {
            Image(uiImage: vehiclePhoto)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: vehicleSystemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// GPS puck: filled arrow pointing up, shallow notch at the bottom.
private struct LiveFollowNavChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let points = [
            CGPoint(x: w * 0.50, y: h * 0.04),
            CGPoint(x: w * 0.97, y: h * 0.92),
            CGPoint(x: w * 0.50, y: h * 0.72),
            CGPoint(x: w * 0.03, y: h * 0.92)
        ]
        let radius = min(w, h) * 0.12
        let cg = CGMutablePath()
        let last = points[points.count - 1]
        let first = points[0]
        cg.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            cg.addArc(tangent1End: current, tangent2End: next, radius: radius)
        }
        cg.closeSubpath()
        return Path(cg)
    }
}

/// Marks the destination sheet's present and dismiss, and the route card's collapse. The live map
/// cover turns animations off for everything else, which would make them pop instead of moving.
struct LiveFollowSheetTransition: TransactionKey {
    static let defaultValue = false
}

/// One plate: the destination row on top, the next turn underneath. The row is the button.
/// Collapsed, the plate shrinks into one glass circle so the whole map shows; a tap widens it back.
struct LiveFollowRouteCard: View {
    var plannedRoute: PlannedRouteStore
    @Binding var isCollapsed: Bool
    /// Where the circle rests inside the card's slot.
    var collapsedAlignment: Alignment = .leading
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph

    private static let morphID = "liveMap.routeCard"

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    /// Dark map glass is a mid blue plate; the palette tint disappears on it.
    private var bannerInk: Color {
        colorScheme == .dark ? Color.white : shellPalette.tintColor(for: colorScheme)
    }

    /// Taller than the old bottom card: padding and type both grow by this much.
    private var heightScale: CGFloat { 1.25 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let content = LiveFollowRouteChipHost.content(for: plannedRoute, now: context.date)
            let missed = plannedRoute.missedTurn
            let rerouting = plannedRoute.isRerouting
            let maneuver = (missed || rerouting) ? nil : plannedRoute.upcomingManeuver
            ZStack(alignment: collapsedAlignment) {
                if isCollapsed {
                    collapsedButton(content: content, missed: missed, rerouting: rerouting, maneuver: maneuver)
                        .matchedGeometryEffect(id: Self.morphID, in: morph)
                        .transition(.opacity)
                } else {
                    expandedCard(content: content, missed: missed, rerouting: rerouting, maneuver: maneuver)
                        .matchedGeometryEffect(id: Self.morphID, in: morph)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsedAlignment)
        }
    }

    private func expandedCard(
        content: RecordingRouteChip.Content,
        missed: Bool,
        rerouting: Bool,
        maneuver: UpcomingManeuver?
    ) -> some View {
        let showsBanner = missed || rerouting || maneuver != nil
        return VStack(spacing: 0) {
            HStack(spacing: 6 * heightScale) {
                RecordingRouteChip(
                    content: content,
                    action: action,
                    wide: true,
                    embedded: true,
                    heightScale: heightScale
                )
                .frame(maxWidth: .infinity)
                Button {
                    setCollapsed(true)
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11 * heightScale, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: Self.collapseSide, height: Self.collapseSide)
                        .background { TrailhoundTintCapsule() }
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityLabel(L10n.string("recording.live_map.route.hide"))
                .accessibilityIdentifier("liveMap.route.collapse")
            }
            .padding(.horizontal, 8 * heightScale)
            .padding(.top, 8 * heightScale)
            .padding(.bottom, showsBanner ? 6 * heightScale : 8 * heightScale)
            if showsBanner {
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.35))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
                banner(missed: missed, rerouting: rerouting, maneuver: maneuver)
                    .padding(.horizontal, 10 * heightScale)
                    .padding(.top, 6 * heightScale)
                    .padding(.bottom, 8 * heightScale)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .liveMapHUDPlate(shape)
    }

    /// Same tint disc as the destination row, inside one HUD glass plate. The glyph is the card's state.
    /// With an estimate the plate is a chip: the red minutes left and the distance. Otherwise a circle.
    private func collapsedButton(
        content: RecordingRouteChip.Content,
        missed: Bool,
        rerouting: Bool,
        maneuver: UpcomingManeuver?
    ) -> some View {
        let side = GlassTokens.toolbarControlCircleSide
        let disc = ZStack {
            TrailhoundTintCapsule()
                .frame(width: Self.collapsedDiscSide, height: Self.collapsedDiscSide)
            if rerouting || content == .loading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white)
            } else {
                Image(systemName: collapsedSymbol(content: content, missed: missed, maneuver: maneuver))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        return Button {
            setCollapsed(false)
        } label: {
            if case let .estimate(distance, countdown, _) = content {
                HStack(spacing: 8) {
                    disc
                    HStack(spacing: 0) {
                        Text(countdown)
                            .foregroundStyle(RecordingRouteChip.countdownInk)
                        Text(" · \(distance)")
                            .foregroundStyle(bannerInk)
                    }
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                }
                .padding(.leading, (side - Self.collapsedDiscSide) / 2)
                .padding(.trailing, 14)
                .frame(height: side)
                .contentShape(Capsule())
                .liveMapHUDPlate(Capsule(), interactive: true)
            } else {
                disc
                    .frame(width: side, height: side)
                    .contentShape(Circle())
                    .liveMapHUDPlate(Circle(), interactive: true)
            }
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(L10n.string("recording.live_map.route.show"))
        .accessibilityValue(collapsedAccessibilityValue(content))
        .accessibilityIdentifier("liveMap.route.expand")
    }

    private func collapsedAccessibilityValue(_ content: RecordingRouteChip.Content) -> String {
        guard case let .estimate(distance, countdown, _) = content else { return "" }
        return "\(countdown), \(distance)"
    }

    private func collapsedSymbol(
        content: RecordingRouteChip.Content,
        missed: Bool,
        maneuver: UpcomingManeuver?
    ) -> String {
        if missed { return "arrow.turn.up.right" }
        if let maneuver { return ManeuverIcon.systemImage(for: maneuver.instruction) }
        switch content {
        case .setDestination: return "flag.fill"
        case .offline: return "wifi.slash"
        case .failed: return "exclamationmark.triangle.fill"
        case .loading, .estimate: return "flag.checkered"
        }
    }

    private static let collapseSide: CGFloat = 30
    private static let collapsedDiscSide: CGFloat = 34

    /// The live map turns animations off; this flag lets the morph through.
    private func setCollapsed(_ collapsed: Bool) {
        TrailhoundHaptics.selection()
        var transaction = Transaction(
            animation: reduceMotion
                ? nil
                : (collapsed ? TrailhoundMotion.liveMapHintCollapse : TrailhoundMotion.liveMapHintPop)
        )
        transaction[LiveFollowSheetTransition.self] = true
        withTransaction(transaction) {
            isCollapsed = collapsed
        }
    }

    @ViewBuilder
    private func banner(missed: Bool, rerouting: Bool, maneuver: UpcomingManeuver?) -> some View {
        VStack(spacing: 4) {
            if missed {
                bannerRow(
                    L10n.string("recording.live_map.route.missed_turn"),
                    systemImage: "arrow.turn.up.right",
                    showsProgress: false,
                    identifier: "liveMap.route.missed"
                )
            }
            if rerouting {
                bannerRow(
                    L10n.string("recording.live_map.route.rerouting"),
                    systemImage: nil,
                    showsProgress: true,
                    identifier: "liveMap.route.rerouting"
                )
            }
            if let maneuver {
                bannerRow(
                    String(
                        format: L10n.string("recording.live_map.route.maneuver"),
                        DateFormatters.formatManeuverDistance(maneuver.distanceMeters),
                        maneuver.instruction
                    ),
                    systemImage: ManeuverIcon.systemImage(for: maneuver.instruction),
                    showsProgress: false,
                    identifier: "liveMap.route.maneuver",
                    lineLimit: 2
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bannerRow(
        _ title: String,
        systemImage: String?,
        showsProgress: Bool,
        identifier: String,
        lineLimit: Int = 1
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12 * heightScale, weight: .semibold))
                    .foregroundStyle(bannerInk)
            }
            Text(title)
                .font(.system(size: 11 * heightScale + 2, weight: .semibold))
                .foregroundStyle(bannerInk)
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Glanceable notes: the next turn, or a missed turn and the recalculation under it.
/// Not buttons: nothing to tap while moving.
struct LiveFollowRouteNotices: View {
    var missedTurn: Bool
    var isRerouting: Bool
    var maneuver: UpcomingManeuver? = nil

    var body: some View {
        if missedTurn || isRerouting || maneuver != nil {
            VStack(alignment: .center, spacing: 4) {
                if missedTurn {
                    notice(
                        L10n.string("recording.live_map.route.missed_turn"),
                        systemImage: "arrow.turn.up.right",
                        showsProgress: false,
                        identifier: "liveMap.route.missed"
                    )
                }
                if isRerouting {
                    notice(
                        L10n.string("recording.live_map.route.rerouting"),
                        systemImage: nil,
                        showsProgress: true,
                        identifier: "liveMap.route.rerouting"
                    )
                }
                if let maneuver, !missedTurn, !isRerouting {
                    notice(
                        String(
                            format: L10n.string("recording.live_map.route.maneuver"),
                            DateFormatters.formatManeuverDistance(maneuver.distanceMeters),
                            maneuver.instruction
                        ),
                        systemImage: ManeuverIcon.systemImage(for: maneuver.instruction),
                        showsProgress: false,
                        identifier: "liveMap.route.maneuver",
                        lineLimit: 2
                    )
                    .frame(maxWidth: 280)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    private func notice(
        _ title: String,
        systemImage: String?,
        showsProgress: Bool,
        identifier: String,
        lineLimit: Int = 1
    ) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassChrome(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Reads the planned-route store in its own body, so a remaining-distance change re-renders
/// this chip and not the whole live map.
struct LiveFollowRouteChipHost: View {
    var plannedRoute: PlannedRouteStore
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            RecordingRouteChip(
                content: Self.content(for: plannedRoute, now: context.date),
                action: action,
                wide: true
            )
        }
    }

    static func content(for store: PlannedRouteStore, now: Date) -> RecordingRouteChip.Content {
        guard store.destination != nil else { return .setDestination }
        switch store.status {
        case .idle, .loading:
            return .loading
        case .offline:
            return .offline
        case .failed:
            return .failed
        case .ready:
            if store.showsRecalculatingETA {
                return .loading
            }
            guard let meters = store.remainingMeters, let time = store.displayedRemaining(at: now) else {
                return .loading
            }
            return .estimate(
                distance: DateFormatters.formatDistance(meters),
                countdown: LiveFollowCountdown.label(seconds: time),
                arrival: DateFormatters.tripTime.string(from: now.addingTimeInterval(time))
            )
        }
    }
}

/// Remaining minutes on the destination button. Whole minutes, at least one while any time is left.
enum LiveFollowCountdown {
    static func label(seconds: TimeInterval) -> String {
        let minutes = max(seconds > 0 ? 1 : 0, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return String(format: L10n.string("recording.live_map.route.minutes"), minutes)
        }
        let hours = minutes / 60
        let remain = minutes % 60
        if remain == 0 {
            return String(format: L10n.string("recording.live_map.route.hours"), hours)
        }
        return String(format: L10n.string("recording.live_map.route.hours_minutes"), hours, remain)
    }
}

struct LiveFollowPolylineSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
}
