import SwiftData
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class AppRuntime {
    private var location: LocationService?
    private var geocoding: GeocodingService?
    private var geocodingRetry: GeocodingRetryService?
    private var recording: TripRecordingService?
    private var lock: AppLockService?
    private var network: NetworkMonitor?
    private var didRecordingBootstrap = false
    private var didFullBootstrap = false

    init() {}

    var locationService: LocationService {
        if let location { return location }
        let service = LocationService()
        location = service
        return service
    }

    var geocodingService: GeocodingService {
        if let geocoding { return geocoding }
        let service = GeocodingService()
        geocoding = service
        return service
    }

    var geocodingRetryService: GeocodingRetryService {
        if let geocodingRetry { return geocodingRetry }
        let service = GeocodingRetryService(geocodingService: geocodingService)
        geocodingRetry = service
        return service
    }

    var tripRecordingService: TripRecordingService {
        if let recording { return recording }
        let service = TripRecordingService(
            locationService: locationService
        )
        recording = service
        return service
    }

    var appLockService: AppLockService {
        if let lock { return lock }
        let service = AppLockService()
        lock = service
        return service
    }

    var networkMonitor: NetworkMonitor {
        if let network { return network }
        let service = NetworkMonitor.shared
        network = service
        return service
    }

    func bootstrapRecording(container: ModelContainer) {
        guard !didRecordingBootstrap else { return }
        didRecordingBootstrap = true

        tripRecordingService.configure(modelContext: container.mainContext)
        wireRecordingRequestHandlers()
        wireLiveActivityDashboardOcclusionMonitor()
        reconcileRecordingStateAfterLaunch(context: container.mainContext)
    }

    private func reconcileRecordingStateAfterLaunch(context: ModelContext) {
        let settings = AppSettings.shared
        let recordingService = tripRecordingService
        guard !recordingService.state.isActiveSession else { return }
        guard !settings.pendingStartRecordingRequest else { return }

        // Widget already cleared isActive (or App Group still has a trip ID after kill).
        // Finalize the matching orphan instead of leaving an open trip with no session.
        let persistedTripID = settings.persistedActiveTripID
        if !settings.isRecordingActiveInAppGroup,
           persistedTripID != nil || settings.persistedRecordingStartedAt != nil {
            _ = recordingService.finalizeOrphanFromExternalStopIfNeeded()
        }

        // Keep trip ID when an orphan remains (kill without stop) so a later widget stop can match.
        let orphans = TripStore.orphans(from: context)
        let remainingOrphanID: UUID? = {
            if let persistedTripID, orphans.contains(where: { $0.id == persistedTripID }) {
                return persistedTripID
            }
            return orphans.first?.id
        }()

        settings.syncRecordingState(
            isRecording: false,
            isPaused: false,
            elapsed: 0,
            distanceMeters: 0,
            currentSpeedKmh: 0,
            activeTripID: remainingOrphanID
        )

        Task { @MainActor in
            await Task.yield()
            let hasActiveSession = tripRecordingService.state.isActiveSession
                || AppSettings.shared.pendingStartRecordingRequest
            guard !hasActiveSession else { return }
            guard !UITestSupport.isEnabled else { return }
            await RecordingLiveActivityService.reconcileAfterLaunch(hasActiveSession: false)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func bootstrap(container: ModelContainer) {
        bootstrapRecording(container: container)
        guard !didFullBootstrap else { return }
        didFullBootstrap = true

        VehicleOdometerService.backfillAnchorsIfNeeded(in: container.mainContext)
        VehiclePairingService.migrateLegacyBluetoothAutoStart(in: container.mainContext)

        networkMonitor.startIfNeeded()
        CategorySeeder.seedIfNeeded(in: container.mainContext)
        VehiclePairingService.seedDefaultVehicleIfNeeded(in: container.mainContext)
        VehicleCareSummaryStore.shared.refresh(in: container.mainContext)
        if !UITestSupport.isEnabled {
            VehicleCareNotificationScheduler.rescheduleAll(in: container.mainContext)
            RecapNotificationScheduler.reschedule(in: container.mainContext)
            TripStore.syncWidgetWeekDistance(in: container.mainContext)
        }
        TripRecoveryService.finalizeStaleOrphans(in: container.mainContext)
        if !UITestSupport.isEnabled {
            TripRecoveryService.scheduleOrphanStaleNotifications(
                in: container.mainContext,
                excludingTripID: tripRecordingService.activeTripID
            )
        }

        networkMonitor.onConnected = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.geocodingRetryService.retryPendingTrips(in: container.mainContext)
            }
        }

        if AppSettings.shared.autoDeleteDays > 0 {
            _ = try? TripCleanupService.cleanupOldTrips(
                in: container.mainContext,
                olderThanDays: AppSettings.shared.autoDeleteDays
            )
        }

        guard !UITestSupport.isEnabled else { return }
        Task(priority: .utility) { @MainActor in
            // Avg-fuel journal totals don't depend on GPS-derived estimates, so rewrite them first.
            TravelJournalTotals.refreshAvgFuelTotalsIfNeeded(in: container.mainContext)
            // Order matters: rollups read the derived night-distance split, so they are built
            // only after every trip has one.
            await TripDerivedBackfillService.backfillIfNeeded(container: container)
            await TripLocalityBackfillService.backfillIfNeeded(
                container: container,
                privacyRadius: AppSettings.shared.privacyRadiusMeters
            )
            await TripRollupService.rebuildIfNeeded(container: container)
            await PremiumDerivedMaintenance.rebuildIfNeeded(container: container)
            TripStore.syncWidgetWeekDistance(in: container.mainContext)
        }
    }

    var shouldKeepLocationServicesActive: Bool {
        tripRecordingService.state.isActiveSession
    }

    func resumeMonitoringIfNeeded() {
        guard shouldKeepLocationServicesActive else { return }
        DevLog.shared.log(.lifecycle, "resumeMonitoringIfNeeded: active recording session")
        RecordingLiveActivityService.retryPendingRestartIfNeeded()
        tripRecordingService.syncExternalState(force: true)
    }

    func suspendIdleMonitoringIfNeeded() {
        guard !shouldKeepLocationServicesActive else {
            DevLog.shared.log(.lifecycle, "suspendIdleMonitoringIfNeeded: kept active (recording session)")
            return
        }
        DevLog.shared.log(.lifecycle, "suspendIdleMonitoringIfNeeded: stopping idle services")
        tripRecordingService.stopIdleServices()
    }

    private func wireLiveActivityDashboardOcclusionMonitor() {
        guard !UITestSupport.isEnabled else { return }
        LiveActivityDashboardOcclusionMonitor.shared.start { [weak self] occluded in
            RecordingLiveActivityService.setDashboardOccluded(occluded)
            if !occluded {
                self?.tripRecordingService.syncExternalState(force: true)
            }
        }
    }

    private func wireRecordingRequestHandlers() {
        RecordingRequestObserver.shared.onStopRequested = { [weak self] in
            self?.tripRecordingService.processExternalStopRequest()
        }
        RecordingRequestObserver.shared.onStartRequested = { [weak self] in
            self?.tripRecordingService.processExternalStartRequest()
        }
        RecordingRequestObserver.shared.onPauseRequested = { [weak self] in
            self?.tripRecordingService.processExternalPauseRequest()
        }
        RecordingRequestObserver.shared.onResumeRequested = { [weak self] in
            self?.tripRecordingService.processExternalResumeRequest()
        }
        RecordingRequestObserver.shared.install()
    }

    func processPendingRecordingRequests() {
        // Widget extension writes land on disk; pull them before reading pending flags.
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        let settings = AppSettings.shared
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
}

@main
struct MilehoundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var didEnterBackground = false

    private var runtime: AppRuntime { AppServices.runtime }
    private var modelContainer: ModelContainer { AppServices.modelContainer }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environment(runtime.locationService)
                .environment(runtime.tripRecordingService)
                .environment(runtime.appLockService)
                .environment(runtime.geocodingRetryService)
                .environment(runtime.networkMonitor)
                .task {
                    await Task.yield()
                    runtime.bootstrap(container: modelContainer)
                    runtime.processPendingRecordingRequests()
                    if !UITestSupport.shouldSkipExternalEffects {
                        TipJarStore.shared.observeTransactionUpdates()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    handleScenePhase(phase)
                }
                .onOpenURL { url in
                    LaunchIntroSession.shared.noteURLOpen()
                    runtime.bootstrap(container: modelContainer)
                    handlePremiumDeepLink(url)
                    guard MilehoundDeepLink.handle(url) else { return }
                    runtime.processPendingRecordingRequests()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        runtime.processPendingRecordingRequests()
                    }
                }
        }
    }

    private func handlePremiumDeepLink(_ url: URL) {
        guard url.scheme == "milehound" else { return }
        switch url.host {
        case "stats":
            let anchor: StatsPremiumAnchor?
            switch url.path {
            case "/goal": anchor = .goal
            case "/forecast": anchor = .forecast
            case "/recap": anchor = .recap
            case "/routes": anchor = .routes
            case "/achievements": anchor = .achievements
            default: anchor = nil
            }
            TabSelection.shared.openStats(anchor: anchor)
        case "trip":
            let idString = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let id = UUID(uuidString: idString) {
                TabSelection.shared.openTrip(id: id)
            }
        default:
            break
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        DevLog.shared.log(.lifecycle, "scenePhase -> \(phase)")
        switch phase {
        case .background:
            didEnterBackground = true
            runtime.suspendIdleMonitoringIfNeeded()
        case .active:
            runtime.bootstrap(container: modelContainer)
            runtime.processPendingRecordingRequests()
            AppNotificationStore.shared.reload()
            runtime.resumeMonitoringIfNeeded()
            if !UITestSupport.isEnabled, !TripRecordingService.sessionIsActive {
                VehicleCareNotificationScheduler.evaluateKmReminders(in: modelContainer.mainContext)
            }
            refreshLockScreenWidgetStats()
            if !UITestSupport.isEnabled {
                Task { @MainActor in
                    await runtime.geocodingRetryService.retryPendingTrips(in: modelContainer.mainContext)
                }
            }
            if AppSettings.shared.appLockEnabled, didEnterBackground {
                runtime.appLockService.lock()
                Task { @MainActor in
                    _ = await runtime.appLockService.authenticateIfNeeded(enabled: true)
                }
            }
        default:
            break
        }
    }

    private func refreshLockScreenWidgetStats() {
        guard !UITestSupport.isEnabled else { return }
        TripStore.syncWidgetWeekDistance(in: modelContainer.mainContext)
        WidgetCenter.shared.reloadTimelines(ofKind: "MilehoundLockScreenWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "MilehoundWidget")
    }
}
