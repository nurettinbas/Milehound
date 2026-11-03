import Foundation
import SwiftData

@ModelActor
actor MonthCostForecastLoader {
    private static let maxCacheEntries = 8

    private var cache: [MonthCostForecastRequest: MonthCostForecast] = [:]
    private var cacheOrder: [MonthCostForecastRequest] = []
    private var cachedStoreVersion: Int?

    func forecast(for request: MonthCostForecastRequest) -> MonthCostForecast {
        if cachedStoreVersion != request.storeVersion {
            cache.removeAll(keepingCapacity: true)
            cacheOrder.removeAll(keepingCapacity: true)
            cachedStoreVersion = request.storeVersion
        }
        if let cached = cache[request] { return cached }
        let built = MonthCostForecastStore.forecast(
            in: modelContext,
            vehicleID: request.selectedVehicleID,
            now: request.now
        )
        insertCache(request, snapshot: built)
        return built
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        cachedStoreVersion = nil
    }

    private func insertCache(_ request: MonthCostForecastRequest, snapshot: MonthCostForecast) {
        if cache[request] == nil {
            cacheOrder.append(request)
        }
        cache[request] = snapshot
        while cacheOrder.count > Self.maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}
