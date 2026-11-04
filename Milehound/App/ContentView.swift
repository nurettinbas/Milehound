import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AppLockService.self) private var appLockService
    @Environment(TripRecordingService.self) private var tripRecordingService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = AppSettings.shared
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var sideColumnChrome = SideColumnChromeState.shared
    @State private var windowSize: CGSize = .zero
    /// Layout the current turn started with. The live size is applied when the turn ends.
    @State private var presentedLayout = MilehoundLayoutSnapshot.phone
    @State private var launchIntroPlays = false
    @State private var launchIntroSettled = false
    @State private var contentSettleScale: CGFloat = 1
    /// The app is built only once the intro’s first frame is on screen, so the system launch screen
    /// does not wait for the whole tab hierarchy.
    @State private var contentMounted = false
    /// Selected tab is on its root and nothing is presented over the window.
    @State private var tabRootClear = true
    /// `mainTabs` origin in window coordinates, so the window-space capsule lands on this view.
    @State private var tabsOrigin: CGPoint = .zero

    var body: some View {
        AppLanguageRefresh {
        ZStack {
            Group {
            if !contentMounted {
                Color.clear
            } else if !settings.hasCompletedOnboarding {
                OnboardingView()
            } else if settings.appLockEnabled && !appLockService.isUnlocked {
                AppLockView()
            } else {
                mainTabs
                    .animation(layoutChangeAnimation, value: layoutSnapshot.layoutClass)
            }
        }
        .scaleEffect(launchIntroAppliedScale, anchor: .center)
        .allowsHitTesting(launchIntroSettled)

            if !launchIntroSettled {
                launchIntroCover
            }
        }
        .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        .appTextSizeScope()
        .onGlassShell()
        .glassMorphPanelHost()
        .recapCardExpandHost()
        .toastHost(clearsTabBar: true)
        .deleteConfirmHost()
        .environment(\.shellPalette, settings.shellPalette)
        .environment(\.milehoundLayout, layoutSnapshot)
        .coordinateSpace(name: MilehoundWindowSpace.name)
        .background {
            ZStack {
                WindowRotationFill()
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            publishWindowSize(geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            publishWindowSize(newSize)
                        }
                }
                MilehoundHingeProbe()
            }
            .allowsHitTesting(false)
        }
        .fullScreenCover(isPresented: $tabSelection.showNotificationsCover) {
            NavigationStack {
                NotificationsListView()
            }
            .glassNavigationChrome()
            .coordinateSpace(name: MilehoundWindowSpace.name)
            .environment(\.milehoundLayout, layoutSnapshot)
            .environment(\.shellPalette, settings.shellPalette)
            .environment(\.locale, AppLanguageStore.shared.locale)
            .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
            .appTextSizeScope()
            .onGlassShell()
            .toastHost()
            .deleteConfirmHost()
        }
        .onAppear {
            syncWindowFill()
            rememberPresentedLayout()
            resolveLaunchIntro()
        }
        .onChange(of: tripRecordingService.state.isActiveSession) { _, active in
            guard active, launchIntroPlays else { return }
            finishLaunchIntro(playedMotion: false)
        }
        .onChange(of: LaunchIntroSession.shared.openedFromURL) { _, opened in
            guard opened, launchIntroPlays else { return }
            finishLaunchIntro(playedMotion: false)
        }
        .onChange(of: LaunchIntroSession.shared.openedFromNotification) { _, opened in
            guard opened, launchIntroPlays else { return }
            finishLaunchIntro(playedMotion: false)
        }
        .onChange(of: appLockService.isUnlocked) { _, unlocked in
            if !unlocked {
                RecapCardExpandPresenter.shared.dismissImmediately()
            }
        }
        .onChange(of: settings.appearanceMode) { _, _ in syncWindowFill() }
        .onChange(of: settings.shellPalette) { _, _ in syncWindowFill() }
        .onChange(of: windowSize) { _, _ in
            rememberPresentedLayout()
            guard !MilehoundInterfaceRotation.shared.isRotating else { return }
            syncWindowFill()
        }
        .onChange(of: horizontalSizeClass) { _, _ in rememberPresentedLayout() }
        .onChange(of: verticalSizeClass) { _, _ in rememberPresentedLayout() }
        .onChange(of: MilehoundInterfaceRotation.shared.isRotating) { _, rotating in
            guard !rotating else { return }
            rememberPresentedLayout()
            syncWindowFill()
        }
        }
    }

    /// A turn already moves the window. A second spring fades the old page over the new one.
    private var layoutChangeAnimation: Animation? {
        let rotation = MilehoundInterfaceRotation.shared
        if rotation.isRotating || rotation.suppressReflowAnimation { return nil }
        return MilehoundMotion.layoutReflow(reduceMotion: reduceMotion)
    }

    /// A scaled `TabView` lays its bar out again on every frame of the settle. Where iOS can
    /// draw a side column (open Duo, iPad), that pass flips it to a bottom bar and back.
    private var launchIntroAppliedScale: CGFloat {
        switch layoutSnapshot.layoutClass {
        case .duoOpen, .pad:
            return 1
        case .phone, .phoneLandscape:
            return contentSettleScale
        }
    }

    private var isRecordingSession: Bool {
        tripRecordingService.state.isActiveSession
    }

    /// Bell, plus the Trips action when that action is in the bar. Nil keeps both in the toolbar.
    private var duoStatusCapsuleFrame: CGRect? {
        var count = sideColumnChrome.duoCapsuleButtonCount(
            tripsTab: tabSelection.selectedTab == .trips,
            splitPair: tabSelection.wideBookShowsPlusAndMerge,
            singleTrailing: tabSelection.selectedTab == .trips && tabSelection.wideBookTrailingVisible
        )
        if sideColumnChrome.showsSettingsDetailBack {
            count += 1
        }
        return sideColumnChrome.uprightDuoCapsuleFrame(
            buttonCount: count,
            layout: layoutSnapshot
        )
    }

    private func noteTabsOrigin(_ origin: CGPoint) {
        guard abs(origin.x - tabsOrigin.x) > 0.5 || abs(origin.y - tabsOrigin.y) > 0.5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tabsOrigin = origin
        }
    }

    private var layoutSnapshot: MilehoundLayoutSnapshot {
        MilehoundLayoutResolver.snapshotDuringTurn(
            presented: presentedLayout,
            live: liveLayout,
            isRotating: MilehoundInterfaceRotation.shared.isRotating
        )
    }

    private var liveLayout: MilehoundLayoutSnapshot {
        let size = windowSize == .zero
            ? MilehoundLayoutResolver.currentWindowSize(fallback: CGSize(width: 390, height: 844))
            : windowSize
        return MilehoundLayoutResolver.snapshot(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass,
            size: size,
            idiom: UIDevice.current.userInterfaceIdiom
        )
    }

    /// Keeps the snapshot a later turn will hold. Ignored while a turn is in progress
    /// so the live inner-display size cannot swap the hierarchy mid-rotation.
    private func rememberPresentedLayout() {
        guard !MilehoundInterfaceRotation.shared.isRotating else { return }
        let next = liveLayout
        guard next != presentedLayout else { return }
        let classChanged = next.layoutClass != presentedLayout.layoutClass
        presentedLayout = next
        guard classChanged else { return }
        let state = PerformanceSignposts.signposter.beginInterval("layout.reflow")
        PerformanceSignposts.signposter.endInterval("layout.reflow", state)
    }

    private func syncWindowFill() {
        AppIconSync.syncWindowStyle(settings.appearanceMode, palette: settings.shellPalette)
    }

    private var launchIntroCover: some View {
        ZStack {
            if launchIntroPlays, windowSize.width > 1, windowSize.height > 1 {
                LaunchIntroOverlay(
                    onReveal: {
                        withAnimation(MilehoundMotion.launchIntroContentSettle) {
                            contentSettleScale = 1
                        }
                    },
                    onStarted: {
                        contentMounted = true
                    },
                    onLanded: {
                        MilehoundHaptics.launchSettled()
                    },
                    onFinished: { playedMotion in
                        finishLaunchIntro(playedMotion: playedMotion)
                    }
                )
            } else {
                LaunchIntroLaunchFill()
            }
        }
        .ignoresSafeArea()
    }

    private func resolveLaunchIntro() {
        guard !launchIntroSettled, !launchIntroPlays else { return }
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        let ownsScene = LaunchIntroSession.shared.claimFirstScene()
        let decision = LaunchIntroGate.decide(
            isUITesting: UITestSupport.shouldSkipExternalEffects,
            isActiveRecording: tripRecordingService.state.isActiveSession,
            hasPendingRecordingRequest: hasPendingRecordingRequest,
            openedFromURL: LaunchIntroSession.shared.openedFromURL,
            openedFromNotification: LaunchIntroSession.shared.openedFromNotification,
            voiceOver: UIAccessibility.isVoiceOverRunning,
            alreadyPlayed: LaunchIntroSession.shared.didFinish,
            isFirstScene: ownsScene
        )
        if decision.plays {
            LaunchIntroSession.shared.markCovering()
            launchIntroPlays = true
            if !reduceMotion {
                contentSettleScale = MilehoundMotion.launchIntroContentSettleScale
            }
        } else {
            LaunchIntroSession.shared.markSkipped()
            contentMounted = true
            launchIntroSettled = true
        }
    }

    private var hasPendingRecordingRequest: Bool {
        settings.pendingStartRecordingRequest
            || settings.pendingStopRecordingRequest
            || settings.pendingPauseRecordingRequest
            || settings.pendingResumeRecordingRequest
            || settings.awaitingExternalStartConfirmation
    }

    private func finishLaunchIntro(playedMotion: Bool) {
        guard !launchIntroSettled else { return }
        if playedMotion {
            LaunchIntroSession.shared.markPlayed()
        } else if !LaunchIntroSession.shared.didFinish {
            LaunchIntroSession.shared.markSkipped()
        }
        contentSettleScale = 1
        contentMounted = true
        launchIntroPlays = false
        launchIntroSettled = true
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func publishWindowSize(_ proposed: CGSize) {
        let size = MilehoundLayoutResolver.currentWindowSize(fallback: proposed)
        guard size != windowSize else { return }
        // The new size can arrive before UIKit's turn. Rebuilding the page then
        // cancels the rotation and the Duo stays landscape, sideways in the hand.
        if MilehoundLayoutResolver.aspectFlips(from: windowSize, to: size) {
            MilehoundInterfaceRotation.shared.holdForIncomingTurn()
        }
        windowSize = size
    }

    private var mainTabs: some View {
        ZStack {
            AtmosphericBackground()

            TabView(selection: $tabSelection.selectedTab) {
                NavigationStack(path: $tabSelection.tripsPath) {
                    TripListView()
                }
                .background(Color.clear)
                .glassNavigationChrome()
                .modifier(MilehoundTabContentChrome())
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabTrips,
                        systemImage: "map",
                        isSelected: tabSelection.selectedTab == .trips
                    )
                    .accessibilityIdentifier("tab.trips")
                }
                .badge(isRecordingSession ? "" : nil)
                .tag(AppTab.trips)

                Group {
                    if tabSelection.selectedTab == .pairing {
                        PairingTabView()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .modifier(MilehoundTabContentChrome())
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.string("vehicles.tab.title"),
                        systemImage: "car",
                        isSelected: tabSelection.selectedTab == .pairing
                    )
                    .accessibilityIdentifier("tab.pairing")
                }
                .tag(AppTab.pairing)

                NavigationStack {
                    if tabSelection.selectedTab == .stats {
                        StatsView()
                            .milehoundShellToolbar()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(MilehoundTabContentChrome())
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabStats,
                        systemImage: "chart.bar",
                        isSelected: tabSelection.selectedTab == .stats
                    )
                    .accessibilityIdentifier("tab.stats")
                }
                .tag(AppTab.stats)

                NavigationStack {
                    if tabSelection.selectedTab == .year {
                        YearView()
                            .milehoundShellToolbar()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(MilehoundTabContentChrome())
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabYear,
                        systemImage: "star",
                        selectedSystemImage: "star.fill",
                        isSelected: tabSelection.selectedTab == .year
                    )
                    .accessibilityIdentifier("tab.year")
                }
                .tag(AppTab.year)

                NavigationStack {
                    if tabSelection.selectedTab == .settings {
                        SettingsView()
                            .milehoundShellToolbar()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(MilehoundTabContentChrome())
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabSettings,
                        systemImage: "gearshape",
                        isSelected: tabSelection.selectedTab == .settings
                    )
                    .accessibilityIdentifier("tab.settings")
                }
                .tag(AppTab.settings)
            }
            .background(Color.clear)
            .background(MilehoundTabBarCompactInstaller(selectedTab: tabSelection.selectedTab))
            .modifier(MilehoundTabSelectionTint())
        }
        .modifier(MilehoundTabBarChrome())
        .modifier(MilehoundRootTint())
        .background {
            TabRootClearReader { clear in
                guard clear != tabRootClear else { return }
                tabRootClear = clear
                sideColumnChrome.setRootClear(clear)
            }
            .allowsHitTesting(false)
        }
        .background {
            WindowOriginReader { origin in
                noteTabsOrigin(origin)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if let frame = duoStatusCapsuleFrame, tabRootClear || sideColumnChrome.holdsSideColumnCapsule {
                DuoSideStatusCapsule()
                    .id(colorScheme)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .offset(x: frame.minX - tabsOrigin.x, y: frame.minY - tabsOrigin.y)
                    .transaction { $0.animation = nil }
            }
        }
        .task(id: launchIntroSettled) {
            guard launchIntroSettled else { return }
            await authenticateOnLaunch()
            processPendingRecordingRequests()
            AppIconSync.apply(settings.shellPalette)
            // If a trip is already active when the main UI appears (e.g. launched
            // from the lock screen widget, or started while locked), land on trips.
            if tripRecordingService.state.isActiveSession {
                tabSelection.openTrips()
            }
        }
        .onChange(of: settings.shellPalette) { _, palette in
            AppIconSync.apply(palette)
        }
        .onChange(of: appLockService.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                processPendingRecordingRequests()
            }
        }
        .onChange(of: tripRecordingService.state.isActiveSession) { wasActive, isActive in
            // A trip can start outside the app (lock screen widget, App Intent,
            // vehicle auto-connect). When it becomes active, surface the trips tab
            // so the user lands on the active trip regardless of the previous tab.
            if !wasActive && isActive {
                tabSelection.openTrips()
            }
        }
        .alert(L10n.externalStartConfirmTitle, isPresented: externalStartConfirmationBinding) {
            Button(L10n.externalStartConfirmAction) {
                tripRecordingService.confirmExternalStartRecording()
            }
            Button(L10n.cancel, role: .cancel) {
                tripRecordingService.cancelExternalStartRecording()
            }
        } message: {
            Text(L10n.externalStartConfirmMessage)
        }
        .appErrorAlert()
    }

    @MainActor
    private func authenticateOnLaunch() async {
        _ = await appLockService.authenticateIfNeeded(enabled: settings.appLockEnabled)
    }

    private func processPendingRecordingRequests() {
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        settings.expireStaleRecordingRequests()
        if settings.pendingStopRecordingRequest {
            tripRecordingService.processExternalStopRequest()
            return
        }
        if settings.pendingStartRecordingRequest || settings.awaitingExternalStartConfirmation {
            tripRecordingService.processExternalStartRequest()
            return
        }
        if settings.pendingPauseRecordingRequest {
            tripRecordingService.processExternalPauseRequest()
            return
        }
        if settings.pendingResumeRecordingRequest {
            tripRecordingService.processExternalResumeRequest()
        }
    }

    private var externalStartConfirmationBinding: Binding<Bool> {
        Binding(
            get: { launchIntroSettled && settings.awaitingExternalStartConfirmation },
            set: { newValue in
                if !newValue, settings.awaitingExternalStartConfirmation {
                    tripRecordingService.cancelExternalStartRecording()
                }
            }
        )
    }

}

private struct MilehoundTabBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

private struct MilehoundRootTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(chromeTint)
    }

    /// White Light tint plates the iOS 26 toolbar, so that case uses the tab selection color.
    /// The modifier stays in place so a theme change does not rebuild the tabs.
    private var chromeTint: Color {
        if colorScheme == .light, GlassEngineResolver.lightAvoidsWhiteChromeTint {
            return Color(
                uiColor: MilehoundTabBarTheme.selectionTintUIColor(
                    palette: shellPalette,
                    scheme: colorScheme
                )
            )
        }
        return shellPalette.shellTint(for: colorScheme)
    }
}

/// Selected capsule uses the palette in Light and Dark. iOS 26 otherwise keeps
/// `AccentColor` (blue) on the side tab and the bottom tab.
private struct MilehoundTabSelectionTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(
            Color(
                uiColor: MilehoundTabBarTheme.selectionTintUIColor(
                    palette: shellPalette,
                    scheme: colorScheme
                )
            )
        )
    }
}

/// Page chrome does not add a white Light tint — that plates the toolbar.
/// The tab bar tint stays on the `TabView`.
private struct MilehoundTabContentChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(chromeTint)
    }

    /// iOS 26 Light used to skip this modifier. Skipping rebuilt the page and popped
    /// Settings. The selection tint matches what the tab bar already provides, without the white plate.
    private var chromeTint: Color {
        if colorScheme == .light, GlassEngineResolver.lightAvoidsWhiteChromeTint {
            return Color(
                uiColor: MilehoundTabBarTheme.selectionTintUIColor(
                    palette: shellPalette,
                    scheme: colorScheme
                )
            )
        }
        return shellPalette.shellTint(for: colorScheme)
    }
}

/// Tab bar forces `.fill` via `symbolVariants`. Pin exact outline/fill names.
/// Selected ink is the palette tint. Unselected stays the system tab color —
/// leaving it unset is what made the selected star `AccentColor` blue.
private struct TabBarItemLabel: View {
    let title: String
    let systemImage: String
    var selectedSystemImage: String? = nil
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let selectedName = selectedSystemImage ?? "\(systemImage).fill"
        let icon = Image(systemName: isSelected ? selectedName : systemImage)
            .environment(\.symbolVariants, .none)
            .symbolRenderingMode(.monochrome)
        let label = Label {
            Text(title)
        } icon: {
            icon
        }
        if isSelected {
            label.foregroundStyle(shellPalette.tintColor(for: colorScheme))
        } else {
            label
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.shared.container)
        .environment(PreviewData.shared.recordingService)
        .environment(LocationService())
        .environment(AppLockService())
        .environment(GeocodingRetryService(geocodingService: GeocodingService()))
        .environment(NetworkMonitor.shared)
}
