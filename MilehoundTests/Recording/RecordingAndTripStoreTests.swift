import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class AppSettingsRecordingRequestTests: XCTestCase {
    func testExpireStaleRecordingRequestsClearsOldFlags() {
        let defaults = UserDefaults(suiteName: "test.milehound.recording.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.pendingStartRecordingRequest = true
        defaults.set(Date().addingTimeInterval(-120).timeIntervalSince1970, forKey: "recording.requestStartAt")

        settings.expireStaleRecordingRequests()
        XCTAssertFalse(settings.pendingStartRecordingRequest)
    }

    func testExpireStaleRecordingRequestsClearsOldStopFlag() {
        let defaults = UserDefaults(suiteName: "test.milehound.recording.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.pendingStopRecordingRequest = true
        defaults.set(Date().addingTimeInterval(-120).timeIntervalSince1970, forKey: "recording.requestStopAt")

        settings.expireStaleRecordingRequests()
        XCTAssertFalse(settings.pendingStopRecordingRequest)
    }
}

@MainActor
final class RecordingControlBridgeRequestTests: XCTestCase {
    private let keys = [
        RecordingControlBridge.Keys.requestStart,
        RecordingControlBridge.Keys.requestStop,
        RecordingControlBridge.Keys.requestPause,
        RecordingControlBridge.Keys.requestResume,
        RecordingControlBridge.Keys.requestStartAt,
        RecordingControlBridge.Keys.requestStopAt,
        RecordingControlBridge.Keys.requestPauseAt,
        RecordingControlBridge.Keys.requestResumeAt,
        RecordingControlBridge.Keys.isActive,
        RecordingControlBridge.Keys.isPaused
    ]

    override func tearDown() {
        let defaults = RecordingControlBridge.sharedDefaults()
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testRequestStartFromControlSurfaceSetsPendingStartFlag() {
        let defaults = RecordingControlBridge.sharedDefaults()
        defaults.set(true, forKey: RecordingControlBridge.Keys.requestStop)
        defaults.set(true, forKey: RecordingControlBridge.Keys.requestPause)
        defaults.set(true, forKey: RecordingControlBridge.Keys.requestResume)

        RecordingControlBridge.requestStartFromControlSurface()

        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.requestStart))
        XCTAssertGreaterThan(defaults.double(forKey: RecordingControlBridge.Keys.requestStartAt), 0)
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.requestStop))
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.requestPause))
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.requestResume))
    }

    func testRequestStopPauseResumeFromControlSurfaceSetPendingFlags() {
        let defaults = RecordingControlBridge.sharedDefaults()

        RecordingControlBridge.requestStopFromControlSurface()
        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.requestStop))
        XCTAssertGreaterThan(defaults.double(forKey: RecordingControlBridge.Keys.requestStopAt), 0)
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.isActive))
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.isPaused))

        RecordingControlBridge.requestPauseFromControlSurface()
        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.requestPause))
        XCTAssertGreaterThan(defaults.double(forKey: RecordingControlBridge.Keys.requestPauseAt), 0)
        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.isActive))
        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.isPaused))

        RecordingControlBridge.requestResumeFromControlSurface()
        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.requestResume))
        XCTAssertGreaterThan(defaults.double(forKey: RecordingControlBridge.Keys.requestResumeAt), 0)
        XCTAssertTrue(defaults.bool(forKey: RecordingControlBridge.Keys.isActive))
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.isPaused))
        XCTAssertFalse(defaults.bool(forKey: RecordingControlBridge.Keys.requestPause))
    }

    func testPauseControlSurfaceMakesWidgetSnapshotShowResume() {
        let defaults = RecordingControlBridge.sharedDefaults()
        defaults.set(true, forKey: RecordingControlBridge.Keys.isActive)
        defaults.set(false, forKey: RecordingControlBridge.Keys.isPaused)

        var snapshot = RecordingControlBridge.recordingWidgetSnapshot(from: defaults)
        XCTAssertTrue(snapshot.showsRecordingControls)
        XCTAssertFalse(snapshot.showsResumeControl)

        RecordingControlBridge.requestPauseFromControlSurface()
        snapshot = RecordingControlBridge.recordingWidgetSnapshot(from: defaults)
        XCTAssertTrue(snapshot.isRecording)
        XCTAssertTrue(snapshot.isPaused)
        XCTAssertTrue(snapshot.showsResumeControl)

        RecordingControlBridge.requestResumeFromControlSurface()
        snapshot = RecordingControlBridge.recordingWidgetSnapshot(from: defaults)
        XCTAssertTrue(snapshot.showsRecordingControls)
        XCTAssertFalse(snapshot.showsResumeControl)
    }
}

@MainActor
final class ExternalRecordingRequestTests: XCTestCase {
    func testProcessExternalStartRequestAwaitsConfirmationWhenEnabled() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.external.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.confirmExternalRecordingStart = true
        settings.pendingStartRecordingRequest = true

        let container = try ModelContainerFactory.makeInMemory()
        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: container.mainContext)

        recordingService.processExternalStartRequest()

        XCTAssertTrue(settings.awaitingExternalStartConfirmation)
        XCTAssertFalse(settings.pendingStartRecordingRequest)
        XCTAssertEqual(recordingService.state, .idle)
    }

    func testProcessExternalStartRequestStartsWhenConfirmationDisabled() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.external.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.confirmExternalRecordingStart = false
        settings.pendingStartRecordingRequest = true

        let container = try ModelContainerFactory.makeInMemory()
        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: container.mainContext)

        recordingService.processExternalStartRequest()
        defer { recordingService.stopManualRecording() }

        XCTAssertFalse(settings.awaitingExternalStartConfirmation)
        XCTAssertFalse(settings.pendingStartRecordingRequest)
        XCTAssertEqual(recordingService.state, .recording)
    }

    /// Widget Pause must leave App Group in the Resume-control snapshot after in-app apply.
    func testProcessExternalPauseKeepsWidgetSnapshotOnResumeControl() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.external.pause.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        let container = try ModelContainerFactory.makeInMemory()
        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: container.mainContext)
        XCTAssertTrue(recordingService.startManualRecording())
        defer { recordingService.stopManualRecording() }

        // Optimistic writes from the widget/Live Activity pause control.
        settings.pendingPauseRecordingRequest = true
        defaults.set(true, forKey: RecordingControlBridge.Keys.isActive)
        defaults.set(true, forKey: RecordingControlBridge.Keys.isPaused)

        recordingService.processExternalPauseRequest()

        XCTAssertEqual(recordingService.state, .paused)
        XCTAssertFalse(settings.pendingPauseRecordingRequest)
        let snapshot = RecordingControlBridge.recordingWidgetSnapshot(from: defaults)
        XCTAssertTrue(snapshot.isRecording)
        XCTAssertTrue(snapshot.isPaused)
        XCTAssertTrue(snapshot.showsResumeControl)
    }

    func testProcessExternalResumeReturnsWidgetSnapshotToPauseControl() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.external.resume.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        let container = try ModelContainerFactory.makeInMemory()
        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: container.mainContext)
        XCTAssertTrue(recordingService.startManualRecording())
        defer { recordingService.stopManualRecording() }
        recordingService.pauseRecording()

        settings.pendingResumeRecordingRequest = true
        defaults.set(true, forKey: RecordingControlBridge.Keys.isActive)
        defaults.set(false, forKey: RecordingControlBridge.Keys.isPaused)

        recordingService.processExternalResumeRequest()

        XCTAssertEqual(recordingService.state, .recording)
        XCTAssertFalse(settings.pendingResumeRecordingRequest)
        let snapshot = RecordingControlBridge.recordingWidgetSnapshot(from: defaults)
        XCTAssertTrue(snapshot.showsRecordingControls)
        XCTAssertFalse(snapshot.showsResumeControl)
    }
}

@MainActor
final class TripStoreTests: XCTestCase {
    func testOrphansExcludesCompletedTrips() throws {
        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let open = Trip(startedAt: Date(), endedAt: nil)
        let done = Trip(startedAt: Date(), endedAt: Date())
        context.insert(open)
        context.insert(done)
        try context.save()

        let orphans = TripStore.orphans(from: context)
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans.first?.id, open.id)
    }

    func testOrphansFetchLimitKeepsNewestOpenTrips() throws {
        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()
        for index in 0..<(TripStore.orphanFetchLimit + 1) {
            context.insert(
                Trip(
                    startedAt: now.addingTimeInterval(TimeInterval(index) * 60),
                    endedAt: nil
                )
            )
        }
        context.insert(Trip(startedAt: now, endedAt: now))
        try context.save()

        let orphans = TripStore.orphans(from: context)
        XCTAssertEqual(orphans.count, TripStore.orphanFetchLimit)
        XCTAssertEqual(orphans.first?.endedAt, nil)
        for pair in zip(orphans, orphans.dropFirst()) {
            XCTAssertGreaterThan(pair.0.startedAt, pair.1.startedAt)
        }
        XCTAssertFalse(orphans.contains { $0.endedAt != nil })
    }

    func testCompletedSinceFiltersByStartDate() throws {
        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let old = Trip(
            startedAt: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            endedAt: Date()
        )
        let recent = Trip(startedAt: Date(), endedAt: Date())
        context.insert(old)
        context.insert(recent)
        try context.save()

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let recentTrips = TripStore.completedSince(weekAgo, from: context)
        XCTAssertEqual(recentTrips.count, 1)
        XCTAssertEqual(recentTrips.first?.id, recent.id)
    }

    func testSyncWidgetWeekDistanceUsesCalendarMonthNotRollingMonth() throws {
        let defaults = UserDefaults(suiteName: "group.com.milehound.app")
        let previousMonthDistance = defaults?.object(forKey: "stats.monthDistance")
        let previousWeekDistance = defaults?.object(forKey: "stats.weekDistance")
        defer {
            if let previousMonthDistance {
                defaults?.set(previousMonthDistance, forKey: "stats.monthDistance")
            } else {
                defaults?.removeObject(forKey: "stats.monthDistance")
            }
            if let previousWeekDistance {
                defaults?.set(previousWeekDistance, forKey: "stats.weekDistance")
            } else {
                defaults?.removeObject(forKey: "stats.weekDistance")
            }
        }

        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let calendar = Calendar.current
        let currentMonthStart = StatsViewModel.calendarMonthInterval(containing: Date(), calendar: calendar).start
        let previousMonthMid = calendar.date(byAdding: .day, value: 15, to:
            StatsViewModel.shiftMonth(currentMonthStart, by: -1, calendar: calendar)
        )!
        let currentMonthMid = calendar.date(byAdding: .day, value: 10, to: currentMonthStart)
            ?? currentMonthStart.addingTimeInterval(864_000)

        let previous = Trip(
            startedAt: previousMonthMid,
            endedAt: previousMonthMid.addingTimeInterval(3_600),
            distanceMeters: 50_000
        )
        let current = Trip(
            startedAt: min(currentMonthMid, Date()),
            endedAt: Date(),
            distanceMeters: 12_000
        )
        context.insert(previous)
        context.insert(current)
        try context.save()

        TripStore.syncWidgetWeekDistance(in: context)

        XCTAssertEqual(defaults?.double(forKey: "stats.monthDistance"), 12_000)
    }
}

@MainActor
final class TripRecoveryServiceTests: XCTestCase {
    func testDeleteOrphanSucceedsWhenTripAlreadyEnded() throws {
        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let ended = Trip(startedAt: Date().addingTimeInterval(-120), endedAt: Date())
        context.insert(ended)
        try context.save()

        XCTAssertTrue(TripRecoveryService.deleteOrphan(ended, in: context))
        XCTAssertNotNil(ended.endedAt)
    }

    func testFinalizeOrphanSucceedsWhenTripAlreadyEnded() throws {
        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let endedAt = Date()
        let ended = Trip(startedAt: Date().addingTimeInterval(-120), endedAt: endedAt)
        context.insert(ended)
        try context.save()

        XCTAssertTrue(TripRecoveryService.finalizeOrphan(ended, in: context, saveTrip: true))
        XCTAssertEqual(ended.endedAt, endedAt)
    }

    func testFinalizeOrphanSavesOpenTrip() throws {
        let container = try ModelContainer(
            for: Trip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let open = Trip(startedAt: Date().addingTimeInterval(-120), endedAt: nil)
        context.insert(open)
        try context.save()

        XCTAssertTrue(TripRecoveryService.finalizeOrphan(open, in: context, saveTrip: true))
        XCTAssertNotNil(open.endedAt)
        XCTAssertEqual(TripStore.orphans(from: context).count, 0)
    }

    /// Simulates widget/intent stop after process death: service is idle, SwiftData orphan remains.
    func testExternalStopWhileIdleFinalizesMatchingOrphan() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.orphan.stop.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let startedAt = Date().addingTimeInterval(-180)
        let open = Trip(startedAt: startedAt, endedAt: nil, distanceMeters: 40)
        context.insert(open)
        try context.save()

        settings.syncRecordingState(
            isRecording: false,
            isPaused: false,
            elapsed: 180,
            distanceMeters: 40,
            currentSpeedKmh: 0,
            recordingStartedAt: startedAt,
            activeTripID: open.id
        )
        settings.pendingStopRecordingRequest = true

        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: context)
        XCTAssertEqual(recordingService.state, .idle)

        recordingService.processExternalStopRequest()

        XCTAssertFalse(settings.pendingStopRecordingRequest)
        XCTAssertNotNil(open.endedAt)
        XCTAssertEqual(TripStore.orphans(from: context).count, 0)
        XCTAssertNil(settings.persistedActiveTripID)
    }

    func testStartManualRecordingBlockedWhenOrphanExists() throws {
        let defaults = UserDefaults(suiteName: "test.milehound.orphan.guard.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let open = Trip(startedAt: Date().addingTimeInterval(-60), endedAt: nil)
        context.insert(open)
        try context.save()

        let recordingService = TripRecordingService(
            locationService: LocationService(),
            settings: settings
        )
        recordingService.configure(modelContext: context)

        XCTAssertFalse(recordingService.startManualRecording())
        XCTAssertEqual(recordingService.state, .idle)
        XCTAssertEqual(TripStore.orphans(from: context).count, 1)
    }
}
