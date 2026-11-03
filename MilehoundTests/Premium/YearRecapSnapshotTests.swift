import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class YearRecapSnapshotTests: XCTestCase {
    func testYearBoundaryExcludesAdjacentYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let inYear = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 8))!
        let previousYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23))!
        let nextYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 1))!
        for date in [inYear, previousYear, nextYear] {
            let trip = Trip(
                startedAt: date,
                endedAt: date.addingTimeInterval(1800),
                distanceMeters: 10_000,
                estimatedFuelCost: 40,
                startLocality: date == inYear ? "Istanbul" : "Ankara"
            )
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: inYear)
        XCTAssertEqual(snapshot.tripCount, 1)
        XCTAssertEqual(snapshot.distanceMeters, 10_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.cityCount, 1)
        XCTAssertEqual(snapshot.topCities, ["Istanbul"])
    }

    func testSkipsCityPageWhenEveryLocalityIsNil() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let trip = Trip(
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now,
            distanceMeters: 8_000
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: year, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.cityCount, 0)
        XCTAssertTrue(snapshot.topCities.isEmpty)
        XCTAssertTrue(snapshot.hasData)
    }

    func testRecapMotionTokensVanishWhenReduceMotionIsOn() {
        XCTAssertNil(MilehoundMotion.recapPage(reduceMotion: true))
        XCTAssertNil(MilehoundMotion.recapCountUp(reduceMotion: true))
        XCTAssertNil(MilehoundMotion.badgeUnlock(reduceMotion: true))
        XCTAssertNil(MilehoundMotion.recapHold(reduceMotion: true))
        XCTAssertNil(MilehoundMotion.recapSegmentFill(reduceMotion: true))
        XCTAssertNotNil(MilehoundMotion.recapPage(reduceMotion: false))
        _ = MilehoundMotion.recapSceneTransition(reduceMotion: true, advancing: true)
        _ = MilehoundMotion.recapSceneTransition(reduceMotion: false, advancing: false)
        _ = MilehoundMotion.recapCopyTransition(reduceMotion: true)
        _ = MilehoundMotion.recapCopyTransition(reduceMotion: false)
        _ = MilehoundMotion.recapIntroCopyTransition(reduceMotion: true)
        _ = MilehoundMotion.recapIntroCopyTransition(reduceMotion: false)
        XCTAssertEqual(RecapIntroReveal.kickerOpacity(elapsed: 0, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.yearOpacity(elapsed: 0, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.whisperOpacity(elapsed: 0, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.yearScale(elapsed: 0, reduceMotion: true), 1, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.kickerOpacity(elapsed: 0, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.yearOpacity(elapsed: 0, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.whisperOpacity(elapsed: 0, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(
            RecapIntroReveal.yearScale(elapsed: 0, reduceMotion: false),
            RecapIntroReveal.yearScaleFrom,
            accuracy: 0.0001
        )
        XCTAssertEqual(RecapIntroReveal.kickerOpacity(elapsed: RecapIntroReveal.kickerEnd, reduceMotion: false), 1, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.yearOpacity(elapsed: RecapIntroReveal.yearEnd, reduceMotion: false), 1, accuracy: 0.0001)
        XCTAssertEqual(RecapIntroReveal.whisperOpacity(elapsed: RecapIntroReveal.whisperEnd, reduceMotion: false), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(RecapIntroReveal.yearOpacity(elapsed: 0.4, reduceMotion: false), 0)
        XCTAssertLessThan(RecapIntroReveal.whisperOpacity(elapsed: 0.4, reduceMotion: false), 1)
    }

    func testHubTeaserIdleIntervalStaysCheap() {
        XCTAssertEqual(RecapHubTeaserMetrics.idleInterval, 1.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(RecapHubTeaserMetrics.posterHeight, 148)
        XCTAssertEqual(StatsCardTokens.posterHeight, RecapHubTeaserMetrics.posterHeight)
        XCTAssertEqual(StatsCardTokens.posterOverlayInsets.top, 8)
        XCTAssertEqual(StatsCardTokens.posterOverlayInsets.leading, 10)
        XCTAssertEqual(RecapHubTeaserMetrics.emptyHeight, 72)
        XCTAssertEqual(RecapHubTeaserMetrics.promoHeight, 320)
        XCTAssertEqual(RecapChapterRailTokens.cardWidth, 140)
        XCTAssertEqual(RecapChapterRailTokens.cardHeight, 200)
        XCTAssertEqual(RecapChapterRailTokens.peek, 24)
        XCTAssertEqual(RecapChapterRailTokens.emblemPointSize, 64)
        XCTAssertEqual(RecapChapterRailTokens.emblemLift, 18)
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .intro), "sparkles")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .distance), "road.lanes")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .cities), "building.2.fill")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .route), "map.fill")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .time), "moon.stars.fill")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .categories), "steeringwheel")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .cost), "fuelpump.fill")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .badges), "medal.fill")
        XCTAssertEqual(RecapChapterEmblem.systemName(for: .closing), "flag.checkered")
        XCTAssertEqual(RecapSceneMotion.phase(0, at: 12), 0)
    }

    func testJanuaryUsesPreviousCalendarYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 15))!
        XCTAssertEqual(RecapYearPolicy.displayYear(now: january, calendar: calendar), 2026)
        XCTAssertEqual(RecapYearPolicy.displayYear(now: december, calendar: calendar), 2026)
        XCTAssertFalse(RecapYearPolicy.shouldPresent(.empty(year: 2026)))
    }

    func testRecapNotificationPolicyIsJanuaryOnlyAndSkipsSeen() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 8, hour: 12))!
        let february = calendar.date(from: DateComponents(year: 2027, month: 2, day: 1, hour: 9))!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        XCTAssertEqual(RecapNotificationPolicy.catchUpYear(now: january, calendar: calendar), 2026)
        XCTAssertNil(RecapNotificationPolicy.catchUpYear(now: february, calendar: calendar))
        let fire = RecapNotificationPolicy.fireDate(forRecapYear: 2026, calendar: calendar)!
        XCTAssertEqual(calendar.component(.year, from: fire), 2027)
        XCTAssertEqual(calendar.component(.month, from: fire), 1)
        XCTAssertEqual(calendar.component(.day, from: fire), 1)
        XCTAssertEqual(calendar.component(.hour, from: fire), 9)
        XCTAssertTrue(fire > september)
        XCTAssertTrue(RecapNotificationPolicy.shouldNotify(hasData: true, seen: false, alreadyNotified: false))
        XCTAssertFalse(RecapNotificationPolicy.shouldNotify(hasData: false, seen: false, alreadyNotified: false))
        XCTAssertFalse(RecapNotificationPolicy.shouldNotify(hasData: true, seen: true, alreadyNotified: false))
        XCTAssertFalse(RecapNotificationPolicy.shouldNotify(hasData: true, seen: false, alreadyNotified: true))
    }

    func testRecapPromoPolicyIsJanuaryWindowThenCatchUpOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let jan3 = calendar.date(from: DateComponents(year: 2027, month: 1, day: 3, hour: 12))!
        let jan8 = calendar.date(from: DateComponents(year: 2027, month: 1, day: 8, hour: 9))!
        let february = calendar.date(from: DateComponents(year: 2027, month: 2, day: 1, hour: 9))!
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 12))!
        XCTAssertTrue(RecapPromoPolicy.isWithinWindow(now: jan3, recapYear: 2026, calendar: calendar))
        XCTAssertFalse(RecapPromoPolicy.isWithinWindow(now: jan8, recapYear: 2026, calendar: calendar))
        XCTAssertTrue(
            RecapPromoPolicy.shouldPresent(
                hasData: true,
                dismissed: false,
                catchUpPresented: false,
                recapYear: 2026,
                now: jan3,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            RecapPromoPolicy.shouldPresent(
                hasData: true,
                dismissed: true,
                catchUpPresented: false,
                recapYear: 2026,
                now: jan3,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            RecapPromoPolicy.shouldPresent(
                hasData: true,
                dismissed: false,
                catchUpPresented: false,
                recapYear: 2026,
                now: jan8,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            RecapPromoPolicy.shouldPresent(
                hasData: true,
                dismissed: false,
                catchUpPresented: true,
                recapYear: 2026,
                now: jan8,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            RecapPromoPolicy.shouldPresent(
                hasData: true,
                dismissed: false,
                catchUpPresented: false,
                recapYear: 2026,
                now: february,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            RecapPromoPolicy.shouldPresent(
                hasData: true,
                dismissed: false,
                catchUpPresented: false,
                recapYear: 2026,
                now: december,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            RecapPromoPolicy.shouldPresent(
                hasData: false,
                dismissed: false,
                catchUpPresented: false,
                recapYear: 2026,
                now: jan3,
                calendar: calendar
            )
        )
        XCTAssertEqual(RecapPromoPolicy.dismissedKey(for: 2026), "recap.promo.dismissed.2026")
        XCTAssertEqual(RecapPromoPolicy.windowDays, 7)
    }

    func testChapterRailFollowsStoryPagesAndTitleKeys() {
        var empty = YearRecapSnapshot.empty(year: 2026)
        empty.tripCount = 2
        empty.distanceMeters = 12_000
        let pages = RecapStoryPagePolicy.pages(for: empty)
        XCTAssertEqual(pages, [.intro, .distance, .closing])
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .intro), "premium.recap.chapter.summary")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .distance), "premium.recap.chapter.distance")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .cities), "premium.recap.chapter.cities")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .route), "premium.recap.chapter.routes")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .time), "premium.recap.chapter.time")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .categories), "premium.recap.chapter.purpose")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .cost), "premium.recap.chapter.cost")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .badges), "premium.recap.chapter.badges")
        XCTAssertEqual(RecapStoryPagePolicy.chapterTitleKey(for: .closing), "premium.recap.chapter.wrap")
        var session = RecapStorySession(snapshot: empty, startPage: .distance)
        XCTAssertEqual(session.startPage, .distance)
        session = RecapStorySession(snapshot: empty)
        XCTAssertNil(session.startPage)
    }

    func testDiskCacheRejectsUnstampedPayload() throws {
        YearRecapCache.invalidate(year: 2026)
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YearRecapSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let stale = try JSONEncoder().encode(YearRecapSnapshot.empty(year: 2026))
        try stale.write(to: url.appendingPathComponent("2026.json"))
        XCTAssertNil(YearRecapCache.load(year: 2026))
        YearRecapCache.invalidate(year: 2026)
    }

    func testDiskCacheRoundTripsSnapshot() {
        YearRecapCache.invalidate(year: 2026)
        var snapshot = YearRecapSnapshot.empty(year: 2026)
        snapshot.tripCount = 3
        snapshot.distanceMeters = 12_345
        snapshot.topCities = ["Istanbul"]
        snapshot.topRouteCount = 4
        snapshot.topRouteStartLatitude = 41.0082
        snapshot.topRouteEndLatitude = 41.0422
        YearRecapCache.save(snapshot)
        XCTAssertEqual(YearRecapCache.load(year: 2026), snapshot)
        YearRecapCache.invalidate(year: 2026)
        XCTAssertNil(YearRecapCache.load(year: 2026))
    }

    func testRouteSnapshotCacheKeyIsStable() {
        let start = CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)
        let end = CLLocationCoordinate2D(latitude: 41.0422, longitude: 29.0094)
        let size = CGSize(width: 280, height: 160)
        let key = FrequentRoutesSnapshotCache.cacheKey(
            start: start,
            end: end,
            count: 4,
            isBusiness: false,
            size: size
        )
        XCTAssertEqual(
            key,
            FrequentRoutesSnapshotCache.cacheKey(
                start: start,
                end: end,
                count: 4,
                isBusiness: false,
                size: size
            )
        )
        XCTAssertEqual(key, "pair:41.00820,28.97840:41.04220,29.00940:4:false:280x160")
        let nudged = CLLocationCoordinate2D(latitude: 41.0082004, longitude: 28.9783996)
        XCTAssertEqual(
            key,
            FrequentRoutesSnapshotCache.cacheKey(
                start: nudged,
                end: end,
                count: 4,
                isBusiness: false,
                size: size
            )
        )
        XCTAssertNotEqual(
            key,
            FrequentRoutesSnapshotCache.cacheKey(
                start: start,
                end: end,
                count: 5,
                isBusiness: false,
                size: size
            )
        )
        XCTAssertNotEqual(
            key,
            FrequentRoutesSnapshotCache.cacheKey(
                start: start,
                end: end,
                count: 4,
                isBusiness: true,
                size: size
            )
        )
    }

    func testExpenseInvalidateRebuildsPaidTotal() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let inYear = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 8))!
        let trip = Trip(
            startedAt: inYear,
            endedAt: inYear.addingTimeInterval(1800),
            distanceMeters: 10_000,
            estimatedFuelCost: 40
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()
        YearRecapCache.invalidate(year: 2026)

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let first = await loader.snapshot(year: 2026, storeVersion: 1, now: inYear)
        XCTAssertEqual(first.paidExpenses, 0, accuracy: 0.1)
        XCTAssertEqual(first.estimatedFuelCost, 40, accuracy: 0.1)

        context.insert(VehicleExpense(category: .service, amount: 250, occurredAt: inYear))
        context.insert(VehicleExpense(category: .hgs, amount: 30, occurredAt: inYear))
        context.insert(VehicleExpense(category: .parking, amount: 20, occurredAt: inYear))
        context.insert(VehicleExpense(category: .mtv, amount: 100, occurredAt: inYear))
        context.insert(VehicleExpense(category: .fuel, amount: 80, occurredAt: inYear))
        try context.save()
        YearRecapCache.invalidate(yearContaining: inYear)
        let second = await loader.snapshot(year: 2026, storeVersion: 2, now: inYear)
        XCTAssertEqual(second.paidExpenses, 80, accuracy: 0.1)
        XCTAssertEqual(second.estimatedFuelCost, 40, accuracy: 0.1)
        XCTAssertEqual(second.estimatedFuelCost + second.paidExpenses, 120, accuracy: 0.1)
    }

    func testYearScopedRouteCountIgnoresLifetimeAggregate() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 9))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 4, day: 2, hour: 9))!

        func makeTrip(at date: Date) -> Trip {
            let trip = Trip(
                startedAt: date,
                endedAt: date.addingTimeInterval(1200),
                distanceMeters: 9_000,
                startPlaceName: "Ev",
                endPlaceName: "Ofis"
            )
            trip.startLatitude = 41.0
            trip.startLongitude = 29.0
            trip.endLatitude = 41.1
            trip.endLongitude = 29.1
            return trip
        }

        for _ in 0..<3 {
            let trip = makeTrip(at: thisYear)
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        for _ in 0..<17 {
            let trip = makeTrip(at: lastYear)
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: thisYear)
        XCTAssertEqual(snapshot.topRouteCount, 3)
        XCTAssertEqual(snapshot.topRouteStart, "Ev")
        XCTAssertEqual(snapshot.topRouteEnd, "Ofis")
        let pages = RecapStoryPagePolicy.pages(for: snapshot)
        XCTAssertTrue(pages.contains(.route))
    }

    func testCustomCategoryCountsAsOtherNotBusiness() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let year = RecapYearPolicy.displayYear(now: now)
        guard let inYear = calendar.date(from: DateComponents(year: year, month: 6, day: 10, hour: 8)) else {
            return XCTFail("expected a date in recap year")
        }
        let customID = UUID().uuidString
        let trip = Trip(
            startedAt: inYear,
            endedAt: inYear.addingTimeInterval(3600),
            distanceMeters: 5_000
        )
        trip.categoryID = customID
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: year, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.businessDistanceMeters, 0, accuracy: 0.1)
        XCTAssertEqual(snapshot.otherDistanceMeters, 5_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.personalDistanceMeters, snapshot.otherDistanceMeters, accuracy: 0.1)
        XCTAssertNil(snapshot.purposeVerdict)
        XCTAssertFalse(RecapStoryPagePolicy.pages(for: snapshot).contains(.categories))
    }

    func testPurposePolicySkipsOneBucketTieAndTinyWinner() {
        XCTAssertNil(
            RecapPurposePolicy.verdict(from: [
                RecapPurposeBucket(kind: .personal, customName: nil, distanceMeters: 120_000)
            ])
        )
        XCTAssertNil(
            RecapPurposePolicy.verdict(from: [
                RecapPurposeBucket(kind: .business, customName: nil, distanceMeters: 60_000),
                RecapPurposeBucket(kind: .personal, customName: nil, distanceMeters: 60_000)
            ])
        )
        XCTAssertNil(
            RecapPurposePolicy.verdict(from: [
                RecapPurposeBucket(kind: .business, customName: nil, distanceMeters: 20_000),
                RecapPurposeBucket(kind: .personal, customName: nil, distanceMeters: 10_000)
            ])
        )
        XCTAssertNil(
            RecapPurposePolicy.verdict(from: [
                RecapPurposeBucket(kind: .business, customName: nil, distanceMeters: 340_000),
                RecapPurposeBucket(kind: .personal, customName: nil, distanceMeters: 330_000),
                RecapPurposeBucket(kind: .custom, customName: "Aile", distanceMeters: 330_000)
            ])
        )
        var empty = YearRecapSnapshot.empty(year: 2026)
        XCTAssertFalse(RecapStoryPagePolicy.pages(for: empty).contains(.categories))
        empty.purposeVerdict = RecapPurposeVerdict(
            kind: .custom,
            customName: "Aile",
            distanceMeters: 80_000,
            share: 80_000 / 120_000,
            slices: [
                RecapPurposeSlice(kind: .custom, customName: "Aile", distanceMeters: 80_000, share: 80_000 / 120_000),
                RecapPurposeSlice(kind: .personal, customName: nil, distanceMeters: 40_000, share: 40_000 / 120_000)
            ]
        )
        XCTAssertTrue(RecapStoryPagePolicy.pages(for: empty).contains(.categories))
        XCTAssertTrue(RecapPurposePolicy.heroTitle(for: empty.purposeVerdict!).contains("Aile"))
    }

    func testPurposePolicyListsRankedSlicesAndFoldsOther() {
        let split = RecapPurposePolicy.verdict(from: [
            RecapPurposeBucket(kind: .personal, customName: nil, distanceMeters: 720_000),
            RecapPurposeBucket(kind: .business, customName: nil, distanceMeters: 480_000)
        ])
        XCTAssertEqual(split?.slices.count, 2)
        XCTAssertEqual(split?.slices[0].kind, .personal)
        XCTAssertEqual(split?.slices[0].share ?? 0, 720_000 / 1_200_000, accuracy: 0.001)
        XCTAssertEqual(split?.slices[1].kind, .business)
        XCTAssertEqual(split?.slices[1].distanceMeters ?? 0, 480_000, accuracy: 0.1)
        let whisper = RecapPurposePolicy.whisper(for: split!)
        XCTAssertFalse(whisper.contains("·"))
        XCTAssertTrue(whisper.contains("60") || whisper.contains("%") || whisper.contains("٪"))

        let folded = RecapPurposePolicy.verdict(from: [
            RecapPurposeBucket(kind: .personal, customName: nil, distanceMeters: 500_000),
            RecapPurposeBucket(kind: .business, customName: nil, distanceMeters: 200_000),
            RecapPurposeBucket(kind: .custom, customName: "Aile", distanceMeters: 80_000),
            RecapPurposeBucket(kind: .custom, customName: "Kamp", distanceMeters: 40_000),
            RecapPurposeBucket(kind: .custom, customName: "Okul", distanceMeters: 30_000)
        ])
        XCTAssertEqual(folded?.slices.count, RecapPurposePolicy.maxVisibleSlices)
        XCTAssertEqual(folded?.slices[0].kind, .personal)
        XCTAssertEqual(folded?.slices[1].kind, .business)
        XCTAssertEqual(folded?.slices[2].customName, "Aile")
        XCTAssertEqual(folded?.slices[3].kind, .custom)
        XCTAssertNil(folded?.slices[3].customName)
        XCTAssertEqual(folded?.slices[3].distanceMeters ?? 0, 70_000, accuracy: 0.1)
        XCTAssertEqual(RecapPurposePolicy.displayName(for: folded!.slices[3]), L10n.string("premium.recap.other"))
    }

    func testCostPageShowsWhenFuelOrExpensesExist() {
        var empty = YearRecapSnapshot.empty(year: 2026)
        XCTAssertFalse(RecapStoryPagePolicy.pages(for: empty).contains(.cost))
        empty.estimatedFuelCost = 400
        XCTAssertTrue(RecapStoryPagePolicy.pages(for: empty).contains(.cost))
        empty.estimatedFuelCost = 0
        empty.paidExpenses = 200
        XCTAssertTrue(RecapStoryPagePolicy.pages(for: empty).contains(.cost))
    }

    func testCostLayoutCentersPumpPairAboveCopySlot() {
        let size = CGSize(width: 390, height: 844)
        let left = RecapCostLayout.pumpRect(in: size, both: true, isLeading: true)
        let right = RecapCostLayout.pumpRect(in: size, both: true, isLeading: false)
        XCTAssertEqual(left.minY, RecapCostLayout.groupTop(in: size), accuracy: 0.5)
        XCTAssertEqual(left.maxY, right.maxY, accuracy: 0.5)
        let pairMid = (left.minX + right.maxX) / 2
        XCTAssertEqual(pairMid, size.width / 2, accuracy: 1)
        XCTAssertGreaterThan(right.minX, left.maxX)
        let copyTop = RecapCostLayout.groupTop(in: size)
            + RecapCostLayout.pumpHeight(in: size)
            + RecapCostLayout.stackSpacing
        XCTAssertGreaterThanOrEqual(copyTop, left.maxY)
    }

    func testDuoStoryStageCentersOnTheWindowNotTheSideTab() {
        let phone = RecapStoryStageMetrics.placement(
            containerWidth: 390,
            leadingInset: 0,
            trailingInset: 0,
            layoutDirection: .leftToRight,
            maxWidth: nil
        )
        XCTAssertEqual(phone.width, 390, accuracy: 0.1)
        XCTAssertEqual(phone.midX, 195, accuracy: 0.1)

        let duo = RecapStoryStageMetrics.placement(
            containerWidth: 1000,
            leadingInset: 0,
            trailingInset: 80,
            layoutDirection: .leftToRight,
            maxWidth: 400
        )
        XCTAssertEqual(duo.width, 400, accuracy: 0.1)
        XCTAssertEqual(duo.midX, 540, accuracy: 0.1)

        let mirrored = RecapStoryStageMetrics.placement(
            containerWidth: 1000,
            leadingInset: 0,
            trailingInset: 80,
            layoutDirection: .rightToLeft,
            maxWidth: 400
        )
        XCTAssertEqual(mirrored.midX, 460, accuracy: 0.1)

        let fullBleed = RecapStoryStageMetrics.placement(
            containerWidth: 1000,
            leadingInset: 0,
            trailingInset: 80,
            layoutDirection: .leftToRight,
            maxWidth: nil
        )
        XCTAssertEqual(fullBleed.midX, 500, accuracy: 0.1)
    }

    func testPurposeLoaderResolvesCustomCategoryWinner() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let year = RecapYearPolicy.displayYear(now: now)
        guard let inYear = calendar.date(from: DateComponents(year: year, month: 6, day: 10, hour: 8)) else {
            return XCTFail("expected a date in recap year")
        }
        let family = UserCategory(name: "Aile", systemImage: "house.fill", isBuiltIn: false, sortOrder: 8)
        context.insert(family)
        let familyTrip = Trip(
            startedAt: inYear,
            endedAt: inYear.addingTimeInterval(3600),
            distanceMeters: 80_000
        )
        familyTrip.categoryID = family.id.uuidString
        context.insert(familyTrip)
        TripRollupService.add(familyTrip, in: context)
        let personalTrip = Trip(
            startedAt: inYear.addingTimeInterval(8_000),
            endedAt: inYear.addingTimeInterval(10_000),
            distanceMeters: 40_000,
            category: .personal
        )
        context.insert(personalTrip)
        TripRollupService.add(personalTrip, in: context)
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: year, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.purposeVerdict?.kind, .custom)
        XCTAssertEqual(snapshot.purposeVerdict?.customName, "Aile")
        XCTAssertEqual(snapshot.purposeVerdict?.distanceMeters ?? 0, 80_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.purposeVerdict?.share ?? 0, 80_000 / 120_000, accuracy: 0.001)
        XCTAssertEqual(snapshot.purposeVerdict?.slices.count, 2)
        XCTAssertEqual(snapshot.purposeVerdict?.slices[0].kind, .custom)
        XCTAssertEqual(snapshot.purposeVerdict?.slices[0].customName, "Aile")
        XCTAssertEqual(snapshot.purposeVerdict?.slices[1].kind, .personal)
        XCTAssertEqual(snapshot.purposeVerdict?.slices[1].distanceMeters ?? 0, 40_000, accuracy: 0.1)
        XCTAssertTrue(RecapStoryPagePolicy.pages(for: snapshot).contains(.categories))
        XCTAssertEqual(snapshot.businessDistanceMeters, 0, accuracy: 0.1)
        XCTAssertEqual(snapshot.otherDistanceMeters, 120_000, accuracy: 0.1)
    }

    func testPlaybackFillsLastPageThenFinishes() {
        var playback = RecapStoryPlayback(pageCount: 3, autoplayEnabled: true)
        XCTAssertEqual(playback.advance(), .moved)
        XCTAssertEqual(playback.advance(), .moved)
        XCTAssertTrue(playback.isLastPage)
        XCTAssertFalse(playback.isPaused)
        XCTAssertEqual(playback.advance(), .finished)
        XCTAssertTrue(playback.isLastPage)

        var first = RecapStoryPlayback(pageCount: 3, autoplayEnabled: true)
        XCTAssertEqual(first.retreat(), .stay)

        var reduced = RecapStoryPlayback(pageCount: 3, autoplayEnabled: false)
        XCTAssertEqual(reduced.consume(10), .stay)
        XCTAssertEqual(reduced.pageIndex, 0)

        var timed = RecapStoryPlayback(pageCount: 3, autoplayEnabled: true)
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .moved)
        XCTAssertEqual(timed.pageIndex, 1)
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .moved)
        XCTAssertEqual(timed.pageIndex, 2)
        XCTAssertTrue(timed.isLastPage)
        XCTAssertFalse(timed.isPaused)
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .finished)
        XCTAssertEqual(timed.pageIndex, 2)
        timed.pause()
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .stay)
        XCTAssertEqual(timed.pageIndex, 2)

        let jumped = RecapStoryPlayback(pageCount: 5, autoplayEnabled: true, startIndex: 3)
        XCTAssertEqual(jumped.pageIndex, 3)
        XCTAssertFalse(jumped.isFirstPage)
        XCTAssertFalse(jumped.isLastPage)
        let clamped = RecapStoryPlayback(pageCount: 3, autoplayEnabled: false, startIndex: 99)
        XCTAssertEqual(clamped.pageIndex, 2)
        XCTAssertTrue(clamped.isLastPage)
    }

    func testStoryTapUsesLeftThirdForBack() {
        XCTAssertEqual(RecapStoryTapMetrics.backWidthFraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertTrue(RecapStoryTapMetrics.isBack(x: 0, width: 390))
        XCTAssertTrue(RecapStoryTapMetrics.isBack(x: 120, width: 390))
        XCTAssertFalse(RecapStoryTapMetrics.isBack(x: 200, width: 390))
        XCTAssertFalse(RecapStoryTapMetrics.isBack(x: 389, width: 390))
        XCTAssertFalse(RecapStoryTapMetrics.isBack(x: 0, width: 0))
    }

    func testStoryCoverLocksPhonePortraitOnly() {
        XCTAssertTrue(RecapStoryOrientationPolicy.locksPhonePortrait(.phone))
        XCTAssertTrue(RecapStoryOrientationPolicy.locksPhonePortrait(.phoneLandscape))
        XCTAssertFalse(RecapStoryOrientationPolicy.locksPhonePortrait(.duoOpen))
        XCTAssertFalse(RecapStoryOrientationPolicy.locksPhonePortrait(.pad))
        XCTAssertEqual(
            RecapStoryOrientationPolicy.restoredMask(device: .landscapeLeft, interface: .portrait),
            .landscapeRight
        )
        XCTAssertEqual(
            RecapStoryOrientationPolicy.restoredMask(device: .landscapeRight, interface: .portrait),
            .landscapeLeft
        )
        XCTAssertEqual(
            RecapStoryOrientationPolicy.restoredMask(device: .portrait, interface: .landscapeRight),
            .portrait
        )
        XCTAssertEqual(
            RecapStoryOrientationPolicy.restoredMask(device: .unknown, interface: .landscapeLeft),
            .landscapeLeft
        )
    }

    func testStoryChromeSitsBelowDynamicIsland() {
        XCTAssertEqual(RecapStoryChromeMetrics.topPadding(windowTop: 0), 62, accuracy: 0.001)
        XCTAssertEqual(RecapStoryChromeMetrics.topPadding(windowTop: 59), 67, accuracy: 0.001)
        XCTAssertEqual(RecapStoryChromeMetrics.topPadding(windowTop: 20), 28, accuracy: 0.001)
        XCTAssertGreaterThan(RecapStoryChromeMetrics.minimumTopInset, 50)
    }

    func testBadgeSlotsStayCenteredWithoutOverlap() {
        let size = CGSize(width: 390, height: 844)
        XCTAssertEqual(RecapStoryBadgeLayout.rowPattern(count: 5), [3, 2])
        XCTAssertEqual(RecapStoryBadgeLayout.overflowCount(8), 2)

        let slots = RecapStoryBadgeLayout.slots(in: size, count: 5)
        XCTAssertEqual(slots.count, 5)
        XCTAssertTrue(slots.allSatisfy { $0.minX >= -0.5 && $0.maxX <= size.width + 0.5 })
        XCTAssertTrue(slots.allSatisfy { $0.minY > size.height * 0.08 && $0.midY < size.height * 0.62 })

        for index in 0..<slots.count {
            for other in (index + 1)..<slots.count {
                XCTAssertFalse(
                    slots[index].insetBy(dx: 0.5, dy: 0.5).intersects(slots[other]),
                    "slot \(index) overlaps \(other)"
                )
            }
        }

        let medal = RecapStoryBadgeLayout.medalSize(in: size, count: 5)
        let medals = slots.map { RecapStoryBadgeLayout.medalRect(in: $0, medal: medal, offsetY: 5) }
        for index in 0..<medals.count {
            for other in (index + 1)..<medals.count {
                XCTAssertFalse(
                    medals[index].intersects(medals[other]),
                    "medal \(index) overlaps \(other)"
                )
            }
        }

        let firstRowMid = (slots[0].minX + slots[2].maxX) / 2
        let secondRowMid = (slots[3].midX + slots[4].midX) / 2
        XCTAssertEqual(firstRowMid, size.width / 2, accuracy: 0.5)
        XCTAssertEqual(secondRowMid, size.width / 2, accuracy: 0.5)
    }

    func testStorySessionAndPagesAreNeverEmpty() {
        let empty = YearRecapSnapshot.empty(year: 2026)
        let pages = RecapStoryPagePolicy.pages(for: empty)
        XCTAssertEqual(pages.first, .intro)
        XCTAssertTrue(pages.contains(.distance))
        XCTAssertEqual(pages.last, .closing)
        XCTAssertGreaterThanOrEqual(pages.count, 3)

        let session = RecapStorySession(snapshot: empty)
        XCTAssertEqual(session.snapshot.year, 2026)
        XCTAssertNotEqual(session.id, RecapStorySession(snapshot: empty).id)
        XCTAssertFalse(RecapYearPolicy.shouldPresent(empty))
        XCTAssertFalse(RecapYearPolicy.shouldPresent(nil))
    }

    func testBusiestMonthIsMonthNameNotYear0001() {
        let name = DateFormatters.formatMonthName(month: 8, year: 2026)
        XCTAssertFalse(name.contains("0001"))
        XCTAssertFalse(name.contains("2026"))
        XCTAssertFalse(name.isEmpty)
    }

    func testBadgePageKeepsKnownIDsAndSkipsUnknown() {
        var withBadges = YearRecapSnapshot.empty(year: 2026)
        withBadges.unlockedAchievementIDs = ["first.trip", "not.a.badge", "night.owl"]
        XCTAssertTrue(RecapStoryPagePolicy.pages(for: withBadges).contains(.badges))

        var unknownOnly = YearRecapSnapshot.empty(year: 2026)
        unknownOnly.unlockedAchievementIDs = ["not.a.badge"]
        XCTAssertFalse(RecapStoryPagePolicy.pages(for: unknownOnly).contains(.badges))
    }

    func testRecapBadgesFallBackToLifetimeWhenNoneUnlockedThisYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let previousUnlock = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2, hour: 10))!
        let row = AchievementProgress(achievementID: AchievementID.firstTrip.rawValue, currentValue: 1)
        row.unlockedAt = previousUnlock
        context.insert(row)
        try context.save()
        YearRecapCache.invalidate(year: 2026)

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.unlockedAchievementIDs, [AchievementID.firstTrip.rawValue])
    }

    func testRecapBadgesPreferUnlocksFromTheRecapYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
        let previousYear = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2, hour: 10))!
        let yearRow = AchievementProgress(achievementID: AchievementID.firstTrip.rawValue, currentValue: 1)
        yearRow.unlockedAt = thisYear
        let older = AchievementProgress(achievementID: AchievementID.nightOwl.rawValue, currentValue: 200_000)
        older.unlockedAt = previousYear
        context.insert(yearRow)
        context.insert(older)
        try context.save()
        YearRecapCache.invalidate(year: 2026)

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: thisYear)
        XCTAssertEqual(snapshot.unlockedAchievementIDs, [AchievementID.firstTrip.rawValue])
    }

    func testRecapSceneMotionPhaseStaysInUnitInterval() {
        XCTAssertEqual(RecapSceneMotion.phase(0, at: 3), 0)
        XCTAssertEqual(RecapSceneMotion.phase(-4, at: 1), 0)
        XCTAssertEqual(RecapSceneMotion.saw(0, at: 2), 0)
        let samples: [TimeInterval] = [0, 1.5, 8, 19.2, 40]
        for time in samples {
            let sine = RecapSceneMotion.phase(8, at: time)
            XCTAssertGreaterThanOrEqual(sine, 0)
            XCTAssertLessThanOrEqual(sine, 1)
            let signed = RecapSceneMotion.signedPhase(8, at: time)
            XCTAssertGreaterThanOrEqual(signed, -1)
            XCTAssertLessThanOrEqual(signed, 1)
            let saw = RecapSceneMotion.saw(10, at: time)
            XCTAssertGreaterThanOrEqual(saw, 0)
            XCTAssertLessThanOrEqual(saw, 1)
        }
        XCTAssertEqual(RecapSceneMotion.phase(8, at: 0), RecapSceneMotion.phase(8, at: 8), accuracy: 0.0001)
        XCTAssertEqual(RecapSceneMotion.saw(10, at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(RecapSceneMotion.saw(10, at: 5), 0.5, accuracy: 0.0001)
    }

    func testShareImageRendersEachStoryPage() throws {
        var snapshot = YearRecapSnapshot.empty(year: 2026)
        snapshot.tripCount = 12
        snapshot.distanceMeters = 50_000
        snapshot.duration = 3_600
        snapshot.cityCount = 3
        snapshot.topCities = ["Istanbul"]
        snapshot.topRouteStart = "Home"
        snapshot.topRouteEnd = "Work"
        snapshot.topRouteCount = 4
        snapshot.nightDistanceMeters = 4_000
        snapshot.longestStreak = 4
        snapshot.busiestMonth = 8
        snapshot.busiestMonthDistanceMeters = 8_000
        snapshot.businessDistanceMeters = 80_000
        snapshot.personalDistanceMeters = 40_000
        snapshot.purposeVerdict = RecapPurposeVerdict(
            kind: .business,
            customName: nil,
            distanceMeters: 80_000,
            share: 80_000 / 120_000,
            slices: [
                RecapPurposeSlice(kind: .business, customName: nil, distanceMeters: 80_000, share: 80_000 / 120_000),
                RecapPurposeSlice(kind: .personal, customName: nil, distanceMeters: 40_000, share: 40_000 / 120_000)
            ]
        )
        snapshot.estimatedFuelCost = 400
        snapshot.paidExpenses = 200
        snapshot.unlockedAchievementIDs = [AchievementID.firstTrip.rawValue]

        let pages = RecapStoryPagePolicy.pages(for: snapshot)
        XCTAssertGreaterThanOrEqual(pages.count, RecapStoryPage.allCases.count - 1)

        var rasters: [Data] = []
        for page in pages {
            let image = RecapShareRenderer.image(
                for: snapshot,
                page: page,
                palette: .gold,
                scheme: .light
            )
            XCTAssertEqual(
                image.size.width * image.scale,
                RecapShareRenderer.pixelSize.width,
                accuracy: 2
            )
            XCTAssertEqual(
                image.size.height * image.scale,
                RecapShareRenderer.pixelSize.height,
                accuracy: 2
            )
            let data = try XCTUnwrap(SocialImageShare.jpegData(from: image))
            XCTAssertGreaterThan(data.count, 4_000)
            XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF])
            rasters.append(data)
        }
        for index in 0..<rasters.count {
            for other in (index + 1)..<rasters.count {
                XCTAssertNotEqual(
                    rasters[index],
                    rasters[other],
                    "share JPEG for \(pages[index]) matched \(pages[other])"
                )
            }
        }

        let introCaption = RecapShareRenderer.caption(for: snapshot, page: .intro)
        XCTAssertTrue(introCaption.contains("2026"))
        XCTAssertFalse(introCaption.localizedCaseInsensitiveContains("Milehound"))

        let routeCaption = RecapShareRenderer.caption(for: snapshot, page: .route)
        XCTAssertTrue(routeCaption.contains("Home"))
        XCTAssertFalse(routeCaption.localizedCaseInsensitiveContains("Milehound"))
    }
}

@MainActor
final class PremiumWidgetBridgeTests: XCTestCase {
    func testPayloadSurvivesMissingAppGroupKeys() {
        let suite = "milehound.tests.widget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let payload = PremiumWidgetPayload.load(from: defaults)
        XCTAssertEqual(payload.projectedTotal, 0, accuracy: 0.1)
        XCTAssertTrue(payload.showRoutePreview)
        XCTAssertNil(payload.lastTripID)
    }
}
