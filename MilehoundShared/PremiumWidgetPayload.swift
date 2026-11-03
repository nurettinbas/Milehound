import Foundation

public struct PremiumWidgetPayload: Equatable, Sendable {
    public var monthDistanceMeters: Double
    public var monthlyGoalMeters: Double
    public var projectedTotal: Double
    public var projectedFuel: Double
    public var installmentsDue: Double
    public var previousMonthTotal: Double
    public var currencyCode: String
    public var lastTripID: UUID?
    public var lastTripDistanceMeters: Double
    public var lastTripStart: String
    public var lastTripEnd: String
    public var lastTripHasPreview: Bool
    public var showRoutePreview: Bool
    public var asOf: Date

    public static let empty = PremiumWidgetPayload(
        monthDistanceMeters: 0,
        monthlyGoalMeters: 500_000,
        projectedTotal: 0,
        projectedFuel: 0,
        installmentsDue: 0,
        previousMonthTotal: 0,
        currencyCode: "TRY",
        lastTripID: nil,
        lastTripDistanceMeters: 0,
        lastTripStart: "",
        lastTripEnd: "",
        lastTripHasPreview: false,
        showRoutePreview: true,
        asOf: Date(timeIntervalSince1970: 0)
    )

    public var goalProgress: Double {
        guard monthlyGoalMeters > 0 else { return 0 }
        return min(1, monthDistanceMeters / monthlyGoalMeters)
    }

    public var trendRatio: Double? {
        guard previousMonthTotal > 0 else { return nil }
        return (projectedTotal - previousMonthTotal) / previousMonthTotal
    }

    public static func load(from defaults: UserDefaults? = nil) -> PremiumWidgetPayload {
        let defaults = defaults ?? RecordingControlBridge.sharedDefaults()
        let recording = RecordingControlBridge.recordingWidgetSnapshot(from: defaults)
        let tripID = defaults.string(forKey: RecordingControlBridge.Keys.lastTripID).flatMap(UUID.init(uuidString:))
        let asOf = defaults.double(forKey: RecordingControlBridge.Keys.forecastAsOf)
        let goal = defaults.double(forKey: "monthlyDistanceGoalMeters")
        let showPreview: Bool
        if defaults.object(forKey: RecordingControlBridge.Keys.showRoutePreview) == nil {
            showPreview = true
        } else {
            showPreview = defaults.bool(forKey: RecordingControlBridge.Keys.showRoutePreview)
        }
        return PremiumWidgetPayload(
            monthDistanceMeters: recording.monthDistanceMeters,
            monthlyGoalMeters: goal > 0 ? goal : 500_000,
            projectedTotal: defaults.double(forKey: RecordingControlBridge.Keys.forecastProjected),
            projectedFuel: defaults.double(forKey: RecordingControlBridge.Keys.forecastFuel),
            installmentsDue: defaults.double(forKey: RecordingControlBridge.Keys.forecastInstallments),
            previousMonthTotal: defaults.double(forKey: RecordingControlBridge.Keys.forecastPrevious),
            currencyCode: defaults.string(forKey: RecordingControlBridge.Keys.forecastCurrency) ?? "TRY",
            lastTripID: tripID,
            lastTripDistanceMeters: defaults.double(forKey: RecordingControlBridge.Keys.lastTripDistance),
            lastTripStart: defaults.string(forKey: RecordingControlBridge.Keys.lastTripStart) ?? "",
            lastTripEnd: defaults.string(forKey: RecordingControlBridge.Keys.lastTripEnd) ?? "",
            lastTripHasPreview: defaults.bool(forKey: RecordingControlBridge.Keys.lastTripHasPreview),
            showRoutePreview: showPreview,
            asOf: asOf > 0 ? Date(timeIntervalSince1970: asOf) : Date(timeIntervalSince1970: 0)
        )
    }

    public static func lastTripPreviewURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RecordingControlBridge.appGroupSuiteName)?
            .appendingPathComponent(RecordingControlBridge.Keys.lastTripPreviewName)
    }
}

public extension RecordingControlBridge.Keys {
    static let forecastProjected = "forecast.monthProjected"
    static let forecastFuel = "forecast.monthFuel"
    static let forecastInstallments = "forecast.installments"
    static let forecastPrevious = "forecast.previousMonthTotal"
    static let forecastCurrency = "forecast.currency"
    static let forecastAsOf = "forecast.asOf"
    static let lastTripID = "widget.lastTripID"
    static let lastTripDistance = "widget.lastTripDistance"
    static let lastTripStart = "widget.lastTripStart"
    static let lastTripEnd = "widget.lastTripEnd"
    static let lastTripHasPreview = "widget.lastTripHasPreview"
    static let showRoutePreview = "widget.showRoutePreview"
    static let lastTripPreviewName = "LastTrip.jpg"
}

public extension MilehoundDeepLink {
    static let statsGoal = URL(string: "milehound://stats/goal")!
    static let statsForecast = URL(string: "milehound://stats/forecast")!
    static let statsRecap = URL(string: "milehound://stats/recap")!
    static let statsRoutes = URL(string: "milehound://stats/routes")!
    static let statsAchievements = URL(string: "milehound://stats/achievements")!

    static func trip(_ id: UUID) -> URL {
        URL(string: "milehound://trip/\(id.uuidString)")!
    }
}
