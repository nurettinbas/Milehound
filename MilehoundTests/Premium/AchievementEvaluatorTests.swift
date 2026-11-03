import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class AchievementEvaluatorTests: XCTestCase {
    override func setUp() {
        AppNotificationArchive.save([])
        AppNotificationStore.shared.reload()
        AppNotificationStore.shared.clearAll()
        UserDefaults.standard.set(0, forKey: AchievementEvaluator.catalogSeedKey)
        UserDefaults.standard.set(0, forKey: AchievementEvaluator.celebrationReplayKey)
    }
    func testBusinessLegacyAndUUIDCountTowardTen() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        for index in 0..<10 {
            let trip = Trip(
                startedAt: Date().addingTimeInterval(Double(-3600 * (10 - index))),
                endedAt: Date().addingTimeInterval(Double(-3600 * (9 - index))),
                distanceMeters: 1_000,
                category: index < 5 ? .business : .personal
            )
            if index >= 5 {
                trip.categoryID = BuiltInCategory.businessID.uuidString
            }
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()
        let displays = AchievementEvaluator.displays(in: context)
        let badge = displays.first { $0.id == .business10 }
        XCTAssertEqual(badge?.currentValue ?? 0, 10, accuracy: 0.1)
        XCTAssertNotNil(badge?.unlockedAt)
    }

    func testStreakCountsConsecutiveCalendarDaysAcrossMidnight() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let trip = Trip(
                startedAt: day.addingTimeInterval(8 * 3600),
                endedAt: day.addingTimeInterval(9 * 3600),
                distanceMeters: 2_000
            )
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()
        XCTAssertEqual(AchievementEvaluator.currentStreakDays(in: context, now: today.addingTimeInterval(12 * 3600), calendar: calendar), 7)
        let streak = AchievementEvaluator.displays(in: context).first { $0.id == .streak7 }
        XCTAssertNotNil(streak?.unlockedAt)
    }

    func testAutoDeleteDoesNotRevokeUnlock() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()
        XCTAssertNotNil(AchievementEvaluator.displays(in: context).first { $0.id == .distance100 }?.unlockedAt)

        TripRollupService.remove(trip, in: context)
        context.delete(trip)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .distance100 }
        XCTAssertNotNil(badge?.unlockedAt)
        XCTAssertEqual(badge?.currentValue ?? -1, 0, accuracy: 0.1)
    }

    func testUnlockQueueMergesNewPendingWithoutResettingCurrent() {
        let first = AchievementDisplay(
            id: .nightOwl,
            currentValue: 5_000,
            unlockedAt: Date(),
            needsCelebration: true
        )
        let second = AchievementDisplay(
            id: .firstTrip,
            currentValue: 1,
            unlockedAt: Date(),
            needsCelebration: true
        )
        let merged = AchievementUnlockQueue.merging(queued: [first], pending: [first, second])
        XCTAssertEqual(merged.map(\.id), [.nightOwl, .firstTrip])
    }

    func testUnlockQueueEmptyTakesPending() {
        let pending = [
            AchievementDisplay(
                id: .streak7,
                currentValue: 7,
                unlockedAt: Date(),
                needsCelebration: true
            )
        ]
        XCTAssertEqual(AchievementUnlockQueue.merging(queued: [], pending: pending).map(\.id), [.streak7])
    }

    func testDistance100000SeedsFromExistingMetersWithoutCelebration() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let row = AchievementProgress(achievementID: AchievementID.distance10000.rawValue, currentValue: 120_000_000)
        row.unlockedAt = Date().addingTimeInterval(-86_400)
        context.insert(row)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .distance100000 }
        XCTAssertEqual(badge?.currentValue ?? 0, 120_000_000, accuracy: 1)
        XCTAssertNotNil(badge?.unlockedAt)
        XCTAssertFalse(badge?.needsCelebration ?? true)
    }

    func testDistance100000SeedsProgressWithoutUnlockingEarly() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let row = AchievementProgress(achievementID: AchievementID.distance10000.rawValue, currentValue: 50_000_000)
        row.unlockedAt = Date().addingTimeInterval(-86_400)
        context.insert(row)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .distance100000 }
        XCTAssertEqual(badge?.currentValue ?? 0, 50_000_000, accuracy: 1)
        XCTAssertNil(badge?.unlockedAt)
    }

    func testDistanceLadderListsBeforePredecessorUnlocks() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let ids = Set(AchievementEvaluator.displays(in: context).map(\.id))
        XCTAssertEqual(
            ids.intersection([.distance100, .distance1000, .distance10000, .distance100000]),
            [.distance100, .distance1000, .distance10000, .distance100000]
        )
        XCTAssertFalse(ids.contains(.business50))
        XCTAssertFalse(ids.contains(.streak30))
        XCTAssertFalse(ids.contains(.cities25))
    }

    func testStripPreviewOmitsLockedMedals() {
        let unlocked = AchievementDisplay(
            id: .firstTrip,
            currentValue: 1,
            unlockedAt: Date(),
            needsCelebration: false
        )
        let locked = AchievementDisplay(
            id: .distance100,
            currentValue: 40_000,
            unlockedAt: nil,
            needsCelebration: false
        )
        XCTAssertEqual(AchievementStripPreview.medals(from: [unlocked, locked]).map(\.id), [.firstTrip])
        XCTAssertTrue(AchievementStripPreview.medals(from: [locked]).isEmpty)
        let many = AchievementID.allCases.prefix(9).map { id in
            AchievementDisplay(
                id: id,
                currentValue: 1,
                unlockedAt: Date(),
                needsCelebration: false
            )
        }
        XCTAssertEqual(AchievementStripPreview.medals(from: many + [locked]).count, 9)
    }

    func testApplyReturnsNewlyUnlockedWithoutInboxWhenNotifyFalse() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        let newly = AchievementEvaluator.apply(
            trip: trip,
            sign: 1,
            localities: [],
            in: context,
            notify: false
        )
        XCTAssertTrue(newly.contains(.firstTrip))
        XCTAssertTrue(newly.contains(.distance100))
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertFalse(displays.first { $0.id == .firstTrip }?.needsCelebration ?? true)
        XCTAssertFalse(displays.first { $0.id == .distance100 }?.needsCelebration ?? true)
    }

    func testLiveApplyLeavesCelebrationPendingWithoutInboxInUnitTests() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        let newly = AchievementEvaluator.apply(
            trip: trip,
            sign: 1,
            localities: [],
            in: context,
            notify: true
        )
        XCTAssertTrue(newly.contains(.firstTrip))
        XCTAssertTrue(newly.contains(.distance100))
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertTrue(displays.first { $0.id == .firstTrip }?.needsCelebration ?? false)
        XCTAssertTrue(displays.first { $0.id == .distance100 }?.needsCelebration ?? false)
    }

    func testNotifyAchievementsUnlockedRecordsOneInboxRowPerBadge() {
        TripNotificationService.notifyAchievementsUnlocked([.firstTrip, .nightOwl])
        let items = AppNotificationStore.shared.items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { AppNotificationStore.shared.kind(for: $0) == .achievementUnlocked })
        XCTAssertEqual(Set(items.compactMap(\.target)), ["first.trip", "night.owl"])
        XCTAssertEqual(items.first?.action, TripNotificationService.openAchievementsAction)
    }

    func testRebuildDoesNotRecordAchievementNotifications() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        AchievementEvaluator.rebuild(in: context)
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        XCTAssertNotNil(AchievementEvaluator.displays(in: context).first { $0.id == .firstTrip }?.unlockedAt)
        XCTAssertFalse(AchievementEvaluator.displays(in: context).first { $0.id == .firstTrip }?.needsCelebration ?? true)
    }

    func testRebuildUnlocksHistoricalTripsWithoutCelebrationOrInbox() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let firstEnded = Date().addingTimeInterval(-86_400 * 40)
        let laterEnded = Date().addingTimeInterval(-86_400 * 10)
        let first = Trip(
            startedAt: firstEnded.addingTimeInterval(-1_800),
            endedAt: firstEnded,
            distanceMeters: 8_000
        )
        let later = Trip(
            startedAt: laterEnded.addingTimeInterval(-3_600),
            endedAt: laterEnded,
            distanceMeters: 110_000
        )
        context.insert(first)
        context.insert(later)
        try context.save()

        AchievementEvaluator.rebuild(in: context)

        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        let firstTrip = displays.first { $0.id == .firstTrip }
        let distance = displays.first { $0.id == .distance100 }
        XCTAssertEqual(firstTrip?.unlockedAt, firstEnded)
        XCTAssertEqual(distance?.unlockedAt, laterEnded)
        XCTAssertEqual(distance?.currentValue ?? 0, 118_000, accuracy: 1)
        XCTAssertFalse(firstTrip?.needsCelebration ?? true)
        XCTAssertFalse(distance?.needsCelebration ?? true)
        XCTAssertTrue(firstTrip?.isUnlocked ?? false)
        XCTAssertTrue(distance?.isUnlocked ?? false)
    }

    func testCelebrationReplayQueuesSeenUnlocksOnceWithoutInbox() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let ended = Date().addingTimeInterval(-86_400)
        let trip = Trip(
            startedAt: ended.addingTimeInterval(-1_800),
            endedAt: ended,
            distanceMeters: 120_000
        )
        context.insert(trip)
        try context.save()
        AchievementEvaluator.rebuild(in: context)
        XCTAssertFalse(
            AchievementEvaluator.displays(in: context).first { $0.id == .firstTrip }?.needsCelebration ?? true
        )

        XCTAssertTrue(AchievementEvaluator.replayUnlockCelebrationsIfNeeded(in: context))
        let after = AchievementEvaluator.displays(in: context)
        XCTAssertTrue(after.first { $0.id == .firstTrip }?.needsCelebration ?? false)
        XCTAssertTrue(after.first { $0.id == .distance100 }?.needsCelebration ?? false)
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)

        XCTAssertFalse(AchievementEvaluator.replayUnlockCelebrationsIfNeeded(in: context))
        AchievementEvaluator.markSeen([.firstTrip, .distance100], in: context)
        try context.save()
        XCTAssertFalse(
            AchievementEvaluator.displays(in: context).first { $0.id == .firstTrip }?.needsCelebration ?? true
        )
    }

    func testMaintenanceAchievementReplayBackfillsExistingTripsSilently() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let ended = Date().addingTimeInterval(-86_400 * 20)
        let trip = Trip(
            startedAt: ended.addingTimeInterval(-2_000),
            endedAt: ended,
            distanceMeters: 250_000
        )
        context.insert(trip)
        try context.save()

        await PremiumDerivedMaintenance.rebuildAchievements(container: container)

        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertEqual(displays.first { $0.id == .firstTrip }?.unlockedAt, ended)
        XCTAssertEqual(displays.first { $0.id == .distance100 }?.unlockedAt, ended)
        XCTAssertFalse(displays.first { $0.id == .firstTrip }?.needsCelebration ?? true)
        XCTAssertFalse(displays.first { $0.id == .distance100 }?.needsCelebration ?? true)
    }

    func testBusiness100SeedsFromSiblingWithoutCelebration() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let row = AchievementProgress(achievementID: AchievementID.business50.rawValue, currentValue: 120)
        row.unlockedAt = Date().addingTimeInterval(-86_400)
        context.insert(row)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .business100 }
        XCTAssertEqual(badge?.currentValue ?? 0, 120, accuracy: 0.1)
        XCTAssertNotNil(badge?.unlockedAt)
        XCTAssertFalse(badge?.needsCelebration ?? true)
    }

    func testCatalogSeedWalksEndedTripsOnce() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 1_000
        )
        context.insert(trip)
        try context.save()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AchievementEvaluator.catalogSeedKey), 0)
        _ = AchievementEvaluator.displays(in: context)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AchievementEvaluator.catalogSeedKey), AchievementEvaluator.catalogSeedVersion)
        XCTAssertEqual(
            AchievementEvaluator.displays(in: context).first { $0.id == .trips50 }?.currentValue ?? 0,
            1,
            accuracy: 0.1
        )
    }

    func testDawnWeekendAndLonghaulSeedFromTrip() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        var start = day
        for _ in 0..<8 {
            if calendar.isDateInWeekend(day) {
                start = calendar.date(byAdding: .hour, value: 6, to: day)!
                break
            }
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        XCTAssertTrue(calendar.isDateInWeekend(start))
        XCTAssertEqual(calendar.component(.hour, from: start), 6)
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(3600),
            distanceMeters: 120_000
        )
        context.insert(trip)
        try context.save()
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertNotNil(displays.first { $0.id == .longhaul1 }?.unlockedAt)
        XCTAssertEqual(displays.first { $0.id == .dawn10 }?.currentValue ?? 0, 1, accuracy: 0.1)
        XCTAssertEqual(displays.first { $0.id == .weekend10 }?.currentValue ?? 0, 1, accuracy: 0.1)
        XCTAssertEqual(displays.first { $0.id == .trips50 }?.currentValue ?? 0, 1, accuracy: 0.1)
        XCTAssertEqual(displays.first { $0.id == .hours24 }?.currentValue ?? 0, 1, accuracy: 0.05)
    }

    func testFiftyExistingTripsUnlockOnDisplays() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        insertCompletedTrips(count: 50, in: context)
        try context.save()

        let displays = AchievementEvaluator.displays(in: context)
        let trips50 = displays.first { $0.id == .trips50 }
        XCTAssertEqual(trips50?.currentValue ?? 0, 50, accuracy: 0.1)
        XCTAssertNotNil(trips50?.unlockedAt)
        XCTAssertFalse(trips50?.needsCelebration ?? true)
        XCTAssertEqual(
            displays.first { $0.id == .firstTrip }?.currentValue ?? 0,
            50,
            accuracy: 0.1
        )
        XCTAssertNotNil(displays.first { $0.id == .firstTrip }?.unlockedAt)
        XCTAssertNotNil(displays.first { $0.id == .hours24 }?.unlockedAt)
    }

    func testFirstTripProgressFillsTrips50AfterSeedAlreadyStamped() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        UserDefaults.standard.set(
            AchievementEvaluator.catalogSeedVersion,
            forKey: AchievementEvaluator.catalogSeedKey
        )
        let first = AchievementProgress(
            achievementID: AchievementID.firstTrip.rawValue,
            currentValue: 50
        )
        first.unlockedAt = Date().addingTimeInterval(-86_400)
        first.seenAt = first.unlockedAt
        context.insert(first)
        try context.save()

        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .trips50 }
        XCTAssertEqual(badge?.currentValue ?? 0, 50, accuracy: 0.1)
        XCTAssertNotNil(badge?.unlockedAt)
        XCTAssertFalse(badge?.needsCelebration ?? true)
    }

    func testSequentialApplyUnlocksTrips50OnTheFiftiethTrip() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        AchievementEvaluator.markCatalogSeeded()
        let trips = insertCompletedTrips(count: 50, in: context)
        for (index, trip) in trips.enumerated() {
            AchievementEvaluator.apply(
                trip: trip,
                sign: 1,
                localities: [],
                in: context,
                notify: false
            )
            let value = AchievementEvaluator.displays(in: context)
                .first { $0.id == .trips50 }?.currentValue ?? 0
            XCTAssertEqual(value, Double(index + 1), accuracy: 0.1)
        }
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .trips50 }
        XCTAssertEqual(badge?.currentValue ?? 0, 50, accuracy: 0.1)
        XCTAssertNotNil(badge?.unlockedAt)
    }

    func testRebuildCountsEachHistoricalTripOnce() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        insertCompletedTrips(count: 50, in: context)
        try context.save()

        AchievementEvaluator.rebuild(in: context)

        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertEqual(displays.first { $0.id == .trips50 }?.currentValue ?? 0, 50, accuracy: 0.1)
        XCTAssertNotNil(displays.first { $0.id == .trips50 }?.unlockedAt)
        XCTAssertEqual(displays.first { $0.id == .firstTrip }?.currentValue ?? 0, 50, accuracy: 0.1)
        XCTAssertEqual(displays.first { $0.id == .hours24 }?.currentValue ?? 0, 25, accuracy: 0.1)
        XCTAssertNotNil(displays.first { $0.id == .hours24 }?.unlockedAt)
        XCTAssertFalse(displays.first { $0.id == .trips50 }?.needsCelebration ?? true)
    }

    @discardableResult
    private func insertCompletedTrips(count: Int, in context: ModelContext) -> [Trip] {
        let origin = Date().addingTimeInterval(-86_400 * 80)
        return (0..<count).map { index in
            let start = origin.addingTimeInterval(Double(index) * 3_600)
            let trip = Trip(
                startedAt: start,
                endedAt: start.addingTimeInterval(1_800),
                distanceMeters: 8_000
            )
            context.insert(trip)
            return trip
        }
    }
}
