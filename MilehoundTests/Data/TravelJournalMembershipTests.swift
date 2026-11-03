import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class TravelJournalMembershipTests: XCTestCase {
    func testAssigningMovesTripBetweenJournals() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 12_000,
            estimatedFuelCost: 40,
            dynamicFuelCost: 42
        )
        context.insert(trip)
        let alpha = TravelJournal(title: "Alpha")
        let beta = TravelJournal(title: "Beta")
        context.insert(alpha)
        context.insert(beta)

        TravelJournalTotals.assign(trip: trip, to: alpha, in: context)
        XCTAssertEqual(trip.journalID, alpha.id)
        XCTAssertEqual(alpha.tripCount, 1)
        XCTAssertEqual(alpha.fuelCost, 40, accuracy: 0.01)

        TravelJournalTotals.assign(trip: trip, to: beta, in: context)
        XCTAssertEqual(trip.journalID, beta.id)
        XCTAssertEqual(alpha.tripCount, 0)
        XCTAssertEqual(beta.tripCount, 1)
        XCTAssertTrue(alpha.trips.isEmpty)
    }

    func testTotalsUseAvgFuelNotEstimated() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let withBoth = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 5_000,
            estimatedFuelCost: 10,
            dynamicFuelCost: 15
        )
        let avgOnly = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5_000,
            estimatedFuelCost: 12
        )
        context.insert(withBoth)
        context.insert(avgOnly)
        let journal = TravelJournal(title: "Costs")
        context.insert(journal)
        TravelJournalTotals.assign(trip: withBoth, to: journal, in: context)
        TravelJournalTotals.assign(trip: avgOnly, to: journal, in: context)
        XCTAssertEqual(journal.fuelCost, 22, accuracy: 0.01)
        XCTAssertEqual(journal.distanceMeters, 10_000, accuracy: 0.01)
    }

    func testRefreshAvgFuelTotalsRewritesStaleEstimatedSum() throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: TravelJournalTotals.avgFuelTotalsVersionKey)
        defer { defaults.removeObject(forKey: TravelJournalTotals.avgFuelTotalsVersionKey) }

        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5_000,
            estimatedFuelCost: 10,
            dynamicFuelCost: 15
        )
        context.insert(trip)
        let journal = TravelJournal(title: "Stale")
        context.insert(journal)
        TravelJournalTotals.assign(trip: trip, to: journal, in: context)
        journal.fuelCost = 15
        try context.save()

        TravelJournalTotals.refreshAvgFuelTotalsIfNeeded(in: context)
        XCTAssertEqual(journal.fuelCost, 10, accuracy: 0.01)
        XCTAssertEqual(
            defaults.integer(forKey: TravelJournalTotals.avgFuelTotalsVersionKey),
            TravelJournalTotals.avgFuelTotalsVersion
        )

        journal.fuelCost = 99
        TravelJournalTotals.refreshAvgFuelTotalsIfNeeded(in: context)
        XCTAssertEqual(journal.fuelCost, 99, accuracy: 0.01)
    }

    func testSameJournalMergeKeepsMembership() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let start = Date().addingTimeInterval(-7_200)
        let first = Trip(startedAt: start, endedAt: start.addingTimeInterval(1_800), distanceMeters: 3_000)
        let second = Trip(
            startedAt: start.addingTimeInterval(2_400),
            endedAt: start.addingTimeInterval(4_200),
            distanceMeters: 3_000
        )
        context.insert(first)
        context.insert(second)
        let journal = TravelJournal(title: "Merge")
        context.insert(journal)
        TravelJournalTotals.assign(trip: first, to: journal, in: context)
        TravelJournalTotals.assign(trip: second, to: journal, in: context)

        let merged = try TripMergeService.merge(trips: [first, second], into: context)
        XCTAssertEqual(merged.journalID, journal.id)
        TravelJournalTotals.refresh(journal)
        XCTAssertEqual(journal.tripCount, 1)
    }

    func testMixedJournalMergeClearsMembership() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let start = Date().addingTimeInterval(-7_200)
        let first = Trip(startedAt: start, endedAt: start.addingTimeInterval(1_800), distanceMeters: 3_000)
        let second = Trip(
            startedAt: start.addingTimeInterval(2_400),
            endedAt: start.addingTimeInterval(4_200),
            distanceMeters: 3_000
        )
        context.insert(first)
        context.insert(second)
        let alpha = TravelJournal(title: "A")
        let beta = TravelJournal(title: "B")
        context.insert(alpha)
        context.insert(beta)
        TravelJournalTotals.assign(trip: first, to: alpha, in: context)
        TravelJournalTotals.assign(trip: second, to: beta, in: context)

        let merged = try TripMergeService.merge(trips: [first, second], into: context)
        XCTAssertNil(merged.journalID)
        XCTAssertEqual(alpha.tripCount, 0)
        XCTAssertEqual(beta.tripCount, 0)
    }

    func testDeletingJournalNullifiesMembership() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 8_000
        )
        context.insert(trip)
        let journal = TravelJournal(title: "Gone")
        context.insert(journal)
        TravelJournalTotals.assign(trip: trip, to: journal, in: context)
        XCTAssertEqual(trip.journalID, journal.id)

        TravelJournalTotals.prepareForDelete(journal)
        context.delete(journal)
        try context.save()

        XCTAssertNil(trip.journalID)
        XCTAssertNil(trip.journal)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Trip>()).count, 1)
    }

    func testDeletingTripKeepsEmptyJournal() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 8_000
        )
        context.insert(trip)
        let journal = TravelJournal(title: "Stays")
        context.insert(journal)
        TravelJournalTotals.assign(trip: trip, to: journal, in: context)
        XCTAssertEqual(journal.tripCount, 1)

        TravelJournalTotals.handleTripDeletion(trip, in: context)
        context.delete(trip)
        try context.save()

        XCTAssertEqual(journal.tripCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TravelJournal>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Trip>()).count, 0)
    }

    func testSchemaV19OpensTravelJournal() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV19.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let journal = TravelJournal(title: "Opened")
        container.mainContext.insert(journal)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<TravelJournal>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Opened")
    }

    func testSchemaV20OpensJournalAndSmartCategoryFields() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV20.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1_000
        )
        let journal = TravelJournal(title: "Opened")
        trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
        trip.pendingSuggestionReasonRaw = TripCategorySuggestionReason.place.rawValue
        trip.categoryOriginRaw = TripCategoryOrigin.default.rawValue
        container.mainContext.insert(journal)
        container.mainContext.insert(trip)
        try container.mainContext.save()

        let tripID = trip.id
        let fetched = try container.mainContext.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
        )
        let reloaded = try XCTUnwrap(fetched.first)
        XCTAssertEqual(reloaded.pendingSuggestedCategoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(reloaded.pendingSuggestionReasonRaw, TripCategorySuggestionReason.place.rawValue)
        XCTAssertEqual(reloaded.categoryOriginRaw, TripCategoryOrigin.default.rawValue)
        XCTAssertNil(reloaded.journalID)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TravelJournal>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Trip>()).count, 1)
    }

    func testSearchFindsTitleIgnoringCase() throws {
        let journal = makeJournal(title: "Deneme")
        TravelJournalTotals.refresh(journal)

        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "deneme"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "DENEME"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "DeNe"))
        XCTAssertFalse(TravelJournalPage.matchesSearch(journal, searchText: "yok"))
        journal.searchIndex = nil
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "deneme"))
    }

    func testSearchFindsTurkishTitlesWithoutDiacritics() throws {
        let journal = makeJournal(title: "Türkiye Tatili")
        TravelJournalTotals.refresh(journal)

        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "turkiye"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "TÜRKİYE"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "tatili"))
        XCTAssertEqual(try XCTUnwrap(journal.searchIndex).contains("turkiye"), true)
    }

    func testSearchFoldsDottedAndDotlessI() throws {
        let istanbul = makeJournal(title: "İstanbul")
        TravelJournalTotals.refresh(istanbul)

        XCTAssertTrue(TravelJournalPage.matchesSearch(istanbul, searchText: "istanbul"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(istanbul, searchText: "ISTANBUL"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(istanbul, searchText: "ıstanbul"))

        let isik = makeJournal(title: "Işık")
        TravelJournalTotals.refresh(isik)
        XCTAssertTrue(TravelJournalPage.matchesSearch(isik, searchText: "isik"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(isik, searchText: "ışık"))
    }

    func testSearchMatchesNoteAndIgnoresEmptyQuery() throws {
        let journal = makeJournal(title: "Yol", note: "Ege sahil")
        TravelJournalTotals.refresh(journal)

        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "sahil"))
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: ""))
        XCTAssertTrue(TravelJournalPage.matchesSearch(journal, searchText: "   "))
    }

    func testDescriptorFetchFindsDenemeByName() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let journal = TravelJournal(title: "Deneme")
        let other = TravelJournal(title: "Tatil")
        context.insert(journal)
        context.insert(other)
        TravelJournalTotals.refresh(journal)
        TravelJournalTotals.refresh(other)
        try context.save()

        let found = try TravelJournalPage.fetch(
            filters: .init(searchText: "deneme"),
            limit: 50,
            in: context
        )
        XCTAssertEqual(found.journals.map(\.id), [journal.id])
        XCTAssertFalse(found.hasMore)

        let missed = try TravelJournalPage.fetch(
            filters: .init(searchText: "yok"),
            limit: 50,
            in: context
        )
        XCTAssertTrue(missed.journals.isEmpty)
    }

    private func makeJournal(title: String, note: String? = nil) -> TravelJournal {
        TravelJournal(title: title, note: note)
    }
}
