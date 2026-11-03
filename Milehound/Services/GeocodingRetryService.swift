import CoreLocation
import Foundation
import SwiftData

@MainActor
@Observable
final class GeocodingRetryService {
    private let geocodingService: GeocodingService
    private let networkMonitor: NetworkMonitor

    init(geocodingService: GeocodingService, networkMonitor: NetworkMonitor = .shared) {
        self.geocodingService = geocodingService
        self.networkMonitor = networkMonitor
    }

    func retryPendingTrips(in context: ModelContext) async {
        guard networkMonitor.isConnected else { return }

        let complete = GeocodeStatus.complete.rawValue
        let trips = TripStore.completed(from: context)

        for trip in trips where trip.geocodeStatusRaw != complete {
            await enrich(trip: trip, context: context)
        }
    }

    private func enrich(trip: Trip, context: ModelContext) async {
        var success = true
        var startPlace = GeocodedPlace(suggestedName: nil, address: nil, locality: nil, countryCode: nil)
        var endPlace = GeocodedPlace(suggestedName: nil, address: nil, locality: nil, countryCode: nil)

        if let startCoordinate = trip.startCoordinate {
            let location = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
            startPlace = await geocodingService.lookupPlace(at: location)
            trip.startAddress = startPlace.address ?? startPlace.suggestedName
            if trip.startAddress == nil { success = false }
        }

        if let endCoordinate = trip.endCoordinate {
            let location = CLLocation(latitude: endCoordinate.latitude, longitude: endCoordinate.longitude)
            endPlace = await geocodingService.lookupPlace(at: location)
            trip.endAddress = endPlace.address ?? endPlace.suggestedName
            if trip.endAddress == nil { success = false }
        }

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        TripLocalityResolver.apply(
            to: trip,
            startLocality: startPlace.locality,
            startCountryCode: startPlace.countryCode,
            endLocality: endPlace.locality,
            endCountryCode: endPlace.countryCode,
            places: places,
            privacyRadius: AppSettings.shared.privacyRadiusMeters
        )

        trip.geocodeStatus = success ? .complete : .failed
        try? context.save()
    }
}
