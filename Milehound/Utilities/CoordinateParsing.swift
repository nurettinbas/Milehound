import CoreLocation
import Foundation

enum CoordinateParsing {
    /// Parses strings like `"41.01, 28.97"`, `"41.01;28.97"`, or whitespace-separated pairs.
    static func parse(_ raw: String) -> CLLocationCoordinate2D? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: "，", with: ",")

        let parts: [String]
        if normalized.contains(";") {
            parts = normalized.split(separator: ";", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if normalized.contains(",") {
            parts = normalized.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            parts = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func format(_ coordinate: CLLocationCoordinate2D) -> String {
        DateFormatters.formatCoordinate(coordinate)
    }
}
