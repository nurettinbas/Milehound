import CoreLocation
import Foundation
import MapKit

struct GeocodedPlace {
    let suggestedName: String?
    let address: String?
    let locality: String?
    let countryCode: String?
}

struct NearbyPlaceOption: Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
}

actor GeocodingService {
    private let geocoder = CLGeocoder()

    func reverseGeocode(_ location: CLLocation) async -> String? {
        let place = await lookupPlace(at: location)
        return place.address ?? place.suggestedName
    }

    func lookupPlace(at location: CLLocation) async -> GeocodedPlace {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let placemark = placemarks.first
            return GeocodedPlace(
                suggestedName: suggestedName(from: placemark),
                address: formattedAddress(from: placemark),
                locality: normalized(placemark?.locality),
                countryCode: normalized(placemark?.isoCountryCode)?.uppercased()
            )
        } catch {
            return GeocodedPlace(
                suggestedName: nil,
                address: DateFormatters.formatCoordinate(location.coordinate),
                locality: nil,
                countryCode: nil
            )
        }
    }

    func nearbyPointsOfInterest(
        around coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 450
    ) async -> [NearbyPlaceOption] {
        if UITestSupport.seedsPlannedRoute {
            return [
                NearbyPlaceOption(
                    id: "cafe",
                    name: "Seed Cafe",
                    subtitle: "Cafe",
                    coordinate: UITestSupport.plannedRouteSeedOrigin
                ),
            ]
        }
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return mapItemsToPlaceOptions(response.mapItems, limit: 8)
        } catch {
            return []
        }
    }

    func searchPlaces(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        regionSpan: CLLocationDegrees = 0.35
    ) async -> [NearbyPlaceOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: regionSpan, longitudeDelta: regionSpan)
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            return mapItemsToPlaceOptions(response.mapItems, limit: 10)
        } catch {
            return []
        }
    }

    private func mapItemsToPlaceOptions(_ mapItems: [MKMapItem], limit: Int) -> [NearbyPlaceOption] {
        var seen = Set<String>()
        var results: [NearbyPlaceOption] = []

        for item in mapItems {
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }

            let key = "\(name)|\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)"
            guard seen.insert(key).inserted else { continue }

            results.append(
                NearbyPlaceOption(
                    id: key,
                    name: name,
                    subtitle: formattedAddress(from: item.placemark),
                    coordinate: item.placemark.coordinate
                )
            )
            if results.count >= limit { break }
        }

        return results
    }

    private func suggestedName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        if let area = placemark.areasOfInterest?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !area.isEmpty {
            return area
        }
        if let name = placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           !looksLikeStreetAddress(name) {
            return name
        }
        return nil
    }

    private func looksLikeStreetAddress(_ value: String) -> Bool {
        value.range(of: #"\d"#, options: .regularExpression) != nil
            && (value.contains("Sk") || value.contains("Cd") || value.contains("No") || value.contains("Mah"))
    }

    private func formattedAddress(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        let parts = [
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        if parts.isEmpty {
            return placemark.name
        }
        return parts.joined(separator: ", ")
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
