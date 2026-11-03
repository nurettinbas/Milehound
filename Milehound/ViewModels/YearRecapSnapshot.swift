import Foundation

struct YearRecapSnapshot: Equatable, Sendable, Codable {
    var year: Int
    var tripCount: Int
    var distanceMeters: Double
    var duration: TimeInterval
    var cityCount: Int
    var topCities: [String]
    var topRouteStart: String?
    var topRouteEnd: String?
    var topRouteCount: Int
    var topRouteStartLatitude: Double?
    var topRouteStartLongitude: Double?
    var topRouteEndLatitude: Double?
    var topRouteEndLongitude: Double?
    var nightDistanceMeters: Double
    var longestStreak: Int
    var busiestMonth: Int?
    var busiestMonthDistanceMeters: Double
    var businessDistanceMeters: Double
    /// Non-business distance (custom categories included). Display as "Other".
    var personalDistanceMeters: Double
    var purposeVerdict: RecapPurposeVerdict?
    var estimatedFuelCost: Double
    /// Logged pump fuel for the year (`VehicleExpense` `.fuel` only — not service, insurance, or other).
    var paidExpenses: Double
    var unlockedAchievementIDs: [String]

    var otherDistanceMeters: Double {
        get { personalDistanceMeters }
        set { personalDistanceMeters = newValue }
    }

    static func empty(year: Int) -> YearRecapSnapshot {
        YearRecapSnapshot(
            year: year,
            tripCount: 0,
            distanceMeters: 0,
            duration: 0,
            cityCount: 0,
            topCities: [],
            topRouteStart: nil,
            topRouteEnd: nil,
            topRouteCount: 0,
            topRouteStartLatitude: nil,
            topRouteStartLongitude: nil,
            topRouteEndLatitude: nil,
            topRouteEndLongitude: nil,
            nightDistanceMeters: 0,
            longestStreak: 0,
            busiestMonth: nil,
            busiestMonthDistanceMeters: 0,
            businessDistanceMeters: 0,
            personalDistanceMeters: 0,
            purposeVerdict: nil,
            estimatedFuelCost: 0,
            paidExpenses: 0,
            unlockedAchievementIDs: []
        )
    }

    var hasData: Bool { tripCount > 0 && distanceMeters > 0 }
}

enum YearRecapCache {
    static let schemaVersion = 6
    private static let directoryName = "YearRecapSnapshots"

    private struct Record: Codable {
        var schemaVersion: Int
        var snapshot: YearRecapSnapshot
    }

    static func invalidate(yearContaining date: Date, calendar: Calendar = .current) {
        let year = calendar.component(.year, from: date)
        invalidate(year: year)
    }

    static func invalidate(year: Int) {
        try? FileManager.default.removeItem(at: fileURL(for: year))
    }

    static func invalidateAll() {
        try? FileManager.default.removeItem(at: directoryURL())
    }

    static func load(year: Int) -> YearRecapSnapshot? {
        let url = fileURL(for: year)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == schemaVersion
        else {
            return nil
        }
        return record.snapshot
    }

    static func save(_ snapshot: YearRecapSnapshot) {
        let directory = directoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = Record(schemaVersion: schemaVersion, snapshot: snapshot)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: fileURL(for: snapshot.year), options: .atomic)
        }
    }

    private static func directoryURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for year: Int) -> URL {
        directoryURL().appendingPathComponent("\(year).json")
    }
}
