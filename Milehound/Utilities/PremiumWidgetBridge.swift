import Foundation
import SwiftData
import UIKit
import WidgetKit

enum PremiumWidgetBridge {
    static let lastTripPreviewFileName = RecordingControlBridge.Keys.lastTripPreviewName

    static func appGroupDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RecordingControlBridge.appGroupSuiteName)
    }

    static func lastTripPreviewURL() -> URL? {
        PremiumWidgetPayload.lastTripPreviewURL()
    }

    @MainActor
    static func sync(in context: ModelContext, forecast: MonthCostForecast? = nil) {
        let defaults = RecordingControlBridge.sharedDefaults()
        let settings = AppSettings.shared
        defaults.set(settings.monthlyDistanceGoalMeters, forKey: "monthlyDistanceGoalMeters")
        defaults.set(settings.widgetShowRoutePreview, forKey: RecordingControlBridge.Keys.showRoutePreview)
        defaults.set(settings.fuelCurrency.rawValue, forKey: RecordingControlBridge.Keys.forecastCurrency)

        let forecast = forecast ?? MonthCostForecastStore.forecast(in: context, vehicleID: nil)
        defaults.set(forecast.projectedTotal, forKey: RecordingControlBridge.Keys.forecastProjected)
        defaults.set(forecast.projectedFuel, forKey: RecordingControlBridge.Keys.forecastFuel)
        defaults.set(forecast.installmentsDue, forKey: RecordingControlBridge.Keys.forecastInstallments)
        defaults.set(forecast.previousMonthTotal, forKey: RecordingControlBridge.Keys.forecastPrevious)
        defaults.set(forecast.asOf.timeIntervalSince1970, forKey: RecordingControlBridge.Keys.forecastAsOf)

        syncLastTrip(in: context, defaults: defaults, privacyRadius: settings.privacyRadiusMeters)
        reloadPremiumWidgetTimelines()
    }

    static func payload(from defaults: UserDefaults? = nil) -> PremiumWidgetPayload {
        PremiumWidgetPayload.load(from: defaults)
    }

    static func reloadPremiumWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "GoalRingWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LastTripWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "CostSummaryWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "MilehoundLockScreenWidget")
    }

    @MainActor
    private static func syncLastTrip(in context: ModelContext, defaults: UserDefaults, privacyRadius: Double) {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let trip = (try? context.fetch(descriptor))?.first else {
            defaults.removeObject(forKey: RecordingControlBridge.Keys.lastTripID)
            defaults.set(false, forKey: RecordingControlBridge.Keys.lastTripHasPreview)
            return
        }
        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let start = FrequentRoutesService.displayName(
            placeName: trip.startPlaceName,
            address: trip.startAddress,
            coordinate: trip.startCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        let end = FrequentRoutesService.displayName(
            placeName: trip.endPlaceName,
            address: trip.endAddress,
            coordinate: trip.endCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        defaults.set(trip.id.uuidString, forKey: RecordingControlBridge.Keys.lastTripID)
        defaults.set(trip.distanceMeters, forKey: RecordingControlBridge.Keys.lastTripDistance)
        defaults.set(start, forKey: RecordingControlBridge.Keys.lastTripStart)
        defaults.set(end, forKey: RecordingControlBridge.Keys.lastTripEnd)

        let appearance = widgetMapAppearance()
        if let image = TripMapSnapshotCache.shared.cachedImage(for: trip.id, appearance: appearance),
           let url = lastTripPreviewURL(),
           let data = image.jpegData(compressionQuality: 0.72),
           data.count < 100_000 {
            try? data.write(to: url, options: .atomic)
            defaults.set(true, forKey: RecordingControlBridge.Keys.lastTripHasPreview)
        } else if FileManager.default.fileExists(atPath: lastTripPreviewURL()?.path ?? "") {
            defaults.set(true, forKey: RecordingControlBridge.Keys.lastTripHasPreview)
        } else {
            defaults.set(false, forKey: RecordingControlBridge.Keys.lastTripHasPreview)
        }
        trip.invalidatePointCaches()
    }

    @MainActor
    private static func widgetMapAppearance() -> MapSnapshotAppearance {
        switch AppSettings.shared.appearanceMode {
        case .light: .light
        case .dark: .dark
        case .system:
            UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        }
    }
}
