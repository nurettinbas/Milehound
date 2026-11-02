import CoreLocation
import Foundation
import SwiftData
import UIKit

enum UITestSupport {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting")
        #else
        false
        #endif
    }

    static var seedsSmartCategory: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.smartCategorySeed")
        #else
        false
        #endif
    }

    static let smartCategorySeedTripID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000ca")!

    /// Two finished trips plus a read "Trip ended" inbox row for the older one.
    static var seedsTripSwitch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.tripSwitchSeed")
        #else
        false
        #endif
    }

    static let tripSwitchNewestID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000a1")!
    static let tripSwitchOlderID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000b2")!

    static var seedsExpenseCategory: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.expenseCategorySeed")
        #else
        false
        #endif
    }

    static let expenseCategorySeedVehicleID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000e1")!

    static var seedsOdometerCare: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.odometerCareSeed")
        #else
        false
        #endif
    }

    static let odometerCareSeedVehicleID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000024")!

    /// Live-map planned route: a saved place, a fake straight-line route provider, and a
    /// fixed origin when the simulator has no GPS fix.
    static var seedsPlannedRoute: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.plannedRouteSeed")
        #else
        false
        #endif
    }

    /// Pretends the car is moving at 15 m/s so destination search locks.
    static var plannedRouteSpeedOverrideMps: Double? {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.plannedRouteMoving") ? 15 : nil
        #else
        nil
        #endif
    }

    static let plannedRouteSeedPlaceID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000d5")!
    static let plannedRouteSeedOrigin = CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)

    /// Closed landscape cover on a phone simulator. The journal detail uses the corner card.
    static var forcesClosedCoverLandscape: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.closedCover")
        #else
        false
        #endif
    }

    static let journalCoverSeedID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000c1")!
    static let journalCoverTripID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000c2")!

    static var seedsJournalCover: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.journalCoverSeed")
        #else
        false
        #endif
    }

    static var showsDrivingSafetyNotice: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting.drivingNoticeSeed")
        #else
        false
        #endif
    }

    /// `TrailhoundTests` runs inside the app process (`TEST_HOST`); side effects must not touch host UI.
    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// WidgetKit, App Intents, Live Activities, and MapKit snapshots block XCTest quiescence.
    static var shouldSkipExternalEffects: Bool {
        isEnabled || isUnitTesting
    }

    @MainActor
    static func configureAppIfNeeded() {
        guard isEnabled else { return }
        UIView.setAnimationsEnabled(false)
        let settings = AppSettings.shared
        settings.completeOnboarding()
        settings.skipCarSetup()
        settings.appLockEnabled = false
        settings.smartCategorySuggestionsEnabled = true
        settings.appearanceMode = .system
        settings.shellPalette = .default
        settings.textSize = .standard
        AppLanguageStore.shared.select(.en)
        if showsDrivingSafetyNotice {
            DrivingSafetyNoticePolicy().reset()
        } else {
            DrivingSafetyNoticePolicy().markShown()
        }
        AppNotificationArchive.save([])
        AppNotificationStore.shared.reload()
        AppNotificationStore.shared.clearAll()
    }

    @MainActor
    static func seedSampleTripIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }
        let context = container.mainContext
        var descriptor = FetchDescriptor<Trip>()
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        // Smart-category UI tests need the commute fixture to be the newest row. Skip the
        // generic sample trip on a fresh store so "first row" is unambiguous.
        if seedsTripSwitch {
            seedTripSwitchFixtures(in: context)
            try? context.save()
            return
        }
        if existing.isEmpty, !seedsSmartCategory {
            let trip = PreviewData.sampleTrip
            context.insert(trip)
            for point in trip.points {
                context.insert(point)
            }
            TripRollupService.add(trip, in: context)
        }
        if seedsSmartCategory {
            let seedID = smartCategorySeedTripID
            let leftovers = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
            for trip in leftovers where trip.id != seedID {
                context.delete(trip)
            }
            seedSmartCategoryFixtures(in: context)
        }
        if seedsExpenseCategory {
            seedExpenseCategoryFixtures(in: context)
        }
        if seedsOdometerCare {
            seedOdometerCareFixtures(in: context)
        }
        if seedsPlannedRoute {
            seedPlannedRouteFixtures(in: context)
        }
        if seedsJournalCover {
            seedJournalCoverFixtures(in: context)
        }
        try? context.save()
    }

    @MainActor
    static func seedPlannedRouteFixtures(in context: ModelContext) {
        let seedID = plannedRouteSeedPlaceID
        var existing = FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.id == seedID })
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil { return }
        context.insert(
            SavedPlace(
                id: seedID,
                name: "Route Seed Office",
                latitude: 41.0422,
                longitude: 29.0083,
                radiusMeters: 200,
                kind: .work
            )
        )
    }

    @MainActor
    static func seedJournalCoverFixtures(in context: ModelContext) {
        let seedID = journalCoverSeedID
        var existing = FetchDescriptor<TravelJournal>(predicate: #Predicate { $0.id == seedID })
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil { return }
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let journal = TravelJournal(
            id: seedID,
            title: "Cover Seed",
            startedOn: anchor,
            endedOn: anchor.addingTimeInterval(3_600),
            note: "Seaside",
            tripCount: 1,
            distanceMeters: 12_000
        )
        let trip = Trip(
            id: journalCoverTripID,
            startedAt: anchor,
            endedAt: anchor.addingTimeInterval(3_600),
            distanceMeters: 12_000,
            startPlaceName: "Home",
            endPlaceName: "Office",
            journal: journal
        )
        context.insert(journal)
        context.insert(trip)
        journal.trips = [trip]
    }

    @MainActor
    static func seedOdometerCareFixtures(in context: ModelContext) {
        let seedID = odometerCareSeedVehicleID
        var existing = FetchDescriptor<VehicleProfile>(predicate: #Predicate { $0.id == seedID })
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil { return }
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let vehicle = VehicleProfile(
            id: seedID,
            name: "Vespa",
            isDefault: true,
            currentOdometerKm: 9_000,
            odometerAnchorKm: 9_000,
            odometerAnchorAt: anchor,
            odometerTripMetersSinceAnchor: 0
        )
        context.insert(vehicle)
        let trip = Trip(
            startedAt: anchor.addingTimeInterval(3_600),
            endedAt: anchor.addingTimeInterval(7_200),
            distanceMeters: 500_000,
            vehicleID: seedID
        )
        context.insert(trip)
        VehicleOdometerService.tripAdded(trip, in: context)
        context.insert(VehicleSchedule(
            kind: .service,
            title: "Service",
            nextDueOdometerKm: 10_000,
            intervalKind: .everyKm,
            intervalKm: 4_000,
            vehicle: vehicle
        ))
    }

    @MainActor
    static func seedExpenseCategoryFixtures(in context: ModelContext) {
        let seedID = expenseCategorySeedVehicleID
        var existing = FetchDescriptor<VehicleProfile>(predicate: #Predicate { $0.id == seedID })
        existing.fetchLimit = 1
        if (try? context.fetch(existing).first) != nil { return }
        let vehicle = VehicleProfile(id: seedID, name: "Expense Seed")
        context.insert(vehicle)
    }

    @MainActor
    static func seedSmartCategoryFixtures(in context: ModelContext) {
        let seedID = smartCategorySeedTripID
        var existingSeed = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == seedID })
        existingSeed.fetchLimit = 1
        if let trip = try? context.fetch(existingSeed).first {
            applySmartCategoryPendingState(to: trip)
            return
        }

        let home = SavedPlace(
            name: "Home",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300,
            kind: .home
        )
        let work = SavedPlace(
            name: "Work",
            latitude: 41.1,
            longitude: 29.1,
            radiusMeters: 300,
            kind: .work
        )
        context.insert(home)
        context.insert(work)

        let trip = Trip(
            id: seedID,
            distanceMeters: 8_000,
            category: .personal,
            startPlaceName: "Home",
            endPlaceName: "Work"
        )
        trip.startLatitude = home.latitude
        trip.startLongitude = home.longitude
        trip.endLatitude = work.latitude
        trip.endLongitude = work.longitude
        applySmartCategoryPendingState(to: trip)
        let startPoint = TripPoint(
            timestamp: trip.startedAt,
            latitude: home.latitude,
            longitude: home.longitude,
            sequence: 0,
            speedMps: 12,
            trip: trip
        )
        let endPoint = TripPoint(
            timestamp: trip.endedAt ?? Date(),
            latitude: work.latitude,
            longitude: work.longitude,
            sequence: 1,
            speedMps: 10,
            trip: trip
        )
        trip.points = [startPoint, endPoint]
        context.insert(trip)
        context.insert(startPoint)
        context.insert(endPoint)
    }

    @MainActor
    static func seedTripSwitchFixtures(in context: ModelContext) {
        let now = Date()
        insertStraightTrip(
            id: tripSwitchNewestID,
            name: "Switch A",
            startLatitude: 38.40,
            startLongitude: 27.10,
            endedAt: now.addingTimeInterval(-3_600),
            in: context
        )
        insertStraightTrip(
            id: tripSwitchOlderID,
            name: "Switch B",
            startLatitude: 38.30,
            startLongitude: 27.20,
            endedAt: now.addingTimeInterval(-86_400),
            in: context
        )
        let store = AppNotificationStore.shared
        store.record(
            kind: .tripEnded,
            title: "Trip ended",
            body: "Switch B ended",
            tripID: tripSwitchOlderID,
            createdAt: now.addingTimeInterval(-86_400)
        )
        store.markAllRead()
    }

    @MainActor
    private static func insertStraightTrip(
        id: UUID,
        name: String,
        startLatitude: Double,
        startLongitude: Double,
        endedAt: Date,
        in context: ModelContext
    ) {
        let pointCount = 60
        let step = 0.0005
        let startedAt = endedAt.addingTimeInterval(-Double(pointCount) * 5)
        let trip = Trip(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: Double(pointCount) * 60,
            category: .personal,
            startPlaceName: "\(name) start",
            endPlaceName: "\(name) end"
        )
        trip.startLatitude = startLatitude
        trip.startLongitude = startLongitude
        trip.endLatitude = startLatitude + Double(pointCount - 1) * step
        trip.endLongitude = startLongitude + Double(pointCount - 1) * step
        context.insert(trip)
        var points: [TripPoint] = []
        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 5),
                latitude: startLatitude + Double(index) * step,
                longitude: startLongitude + Double(index) * step,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            context.insert(point)
            points.append(point)
        }
        trip.points = points
        TripRollupService.add(trip, in: context)
    }

    /// Newest completed personal commute with a pending Business suggestion.
    @MainActor
    private static func applySmartCategoryPendingState(to trip: Trip) {
        let endedAt = Date().addingTimeInterval(-5)
        trip.startedAt = endedAt.addingTimeInterval(-1_500)
        trip.endedAt = endedAt
        trip.categoryID = BuiltInCategory.personalID.uuidString
        trip.categoryOriginRaw = TripCategoryOrigin.default.rawValue
        trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
        trip.pendingSuggestionReasonRaw = TripCategorySuggestionReason.place.rawValue
    }
}
