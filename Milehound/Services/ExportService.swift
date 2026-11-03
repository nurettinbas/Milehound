import Foundation
import SwiftData

enum ExportService {
    struct ExportTrip: Codable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date?
        let distanceMeters: Double
        let startAddress: String?
        let endAddress: String?
        let note: String?
        let category: String
        let estimatedFuelCost: Double?
        let dynamicFuelCost: Double?
        let points: [ExportPoint]
    }

    struct ExportPoint: Codable, Sendable {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let sequence: Int
        let speedMps: Double?
    }

    struct TripExportSnapshot: Sendable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date?
        let distanceMeters: Double
        let startAddress: String?
        let endAddress: String?
        let note: String?
        let categoryRaw: String
        let estimatedFuelCost: Double?
        let dynamicFuelCost: Double?
        let displayStartName: String
        let displayEndName: String
        let routeSummary: String
        let kmlName: String
        let points: [ExportPoint]
    }

    enum FileFormat: Sendable {
        case json, csv, gpx, kml
    }

    @MainActor
    static func snapshots(
        from trips: [Trip],
        blurCoordinates: Bool,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> [TripExportSnapshot] {
        trips.map { trip in
            let points = trip.sortedPoints.map { point in
                let coordinate = blurCoordinates
                    ? PlaceMatchingService.blurredCoordinate(point.coordinate)
                    : point.coordinate
                return ExportPoint(
                    timestamp: point.timestamp,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    sequence: point.sequence,
                    speedMps: point.speedMps
                )
            }
            return TripExportSnapshot(
                id: trip.id,
                startedAt: trip.startedAt,
                endedAt: trip.endedAt,
                distanceMeters: trip.distanceMeters,
                startAddress: trip.startAddress,
                endAddress: trip.endAddress,
                note: trip.note,
                categoryRaw: trip.categoryRaw,
                estimatedFuelCost: trip.estimatedFuelCost,
                dynamicFuelCost: trip.dynamicFuelCost,
                displayStartName: trip.displayStartName,
                displayEndName: trip.displayEndName,
                routeSummary: TripListViewModel.routeSummary(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius
                ),
                kmlName: DateFormatters.tripDate.string(from: trip.startedAt),
                points: points
            )
        }
    }

    nonisolated static func write(
        snapshots: [TripExportSnapshot],
        format: FileFormat,
        to url: URL
    ) throws {
        switch format {
        case .json:
            let data = try exportJSON(snapshots: snapshots)
            try data.write(to: url)
        case .csv:
            let csv = exportCSV(snapshots: snapshots)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        case .gpx:
            let gpx = exportGPX(snapshots: snapshots)
            try gpx.write(to: url, atomically: true, encoding: .utf8)
        case .kml:
            let kml = exportKML(snapshots: snapshots)
            try kml.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func exportJSON(trips: [Trip], blurCoordinates: Bool) throws -> Data {
        try exportJSON(snapshots: trips.map { snapshot(from: $0, blurCoordinates: blurCoordinates) })
    }

    nonisolated static func exportJSON(snapshots: [TripExportSnapshot]) throws -> Data {
        let payload = snapshots.map { snapshot in
            ExportTrip(
                id: snapshot.id,
                startedAt: snapshot.startedAt,
                endedAt: snapshot.endedAt,
                distanceMeters: snapshot.distanceMeters,
                startAddress: snapshot.startAddress,
                endAddress: snapshot.endAddress,
                note: snapshot.note,
                category: snapshot.categoryRaw,
                estimatedFuelCost: snapshot.estimatedFuelCost,
                dynamicFuelCost: snapshot.dynamicFuelCost,
                points: snapshot.points
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func exportCSV(trips: [Trip]) -> String {
        exportCSV(snapshots: trips.map { snapshot(from: $0, blurCoordinates: false) })
    }

    nonisolated static func exportCSV(snapshots: [TripExportSnapshot]) -> String {
        var lines = ["id,startedAt,endedAt,distanceKm,start,end,category,note,fuelCost,dynamicFuelCost"]
        let formatter = ISO8601DateFormatter()
        for snapshot in snapshots {
            let distanceKm = String(format: "%.2f", snapshot.distanceMeters / 1000)
            let fuel = snapshot.estimatedFuelCost.map { String(format: "%.0f", $0) } ?? ""
            let dynamicFuel = snapshot.dynamicFuelCost.map { String(format: "%.0f", $0) } ?? ""
            let row = [
                snapshot.id.uuidString,
                formatter.string(from: snapshot.startedAt),
                snapshot.endedAt.map { formatter.string(from: $0) } ?? "",
                distanceKm,
                csvEscape(snapshot.displayStartName),
                csvEscape(snapshot.displayEndName),
                snapshot.categoryRaw,
                csvEscape(snapshot.note ?? ""),
                fuel,
                dynamicFuel
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    static func exportGPX(trips: [Trip], blurCoordinates: Bool) -> String {
        exportGPX(snapshots: trips.map { snapshot(from: $0, blurCoordinates: blurCoordinates) })
    }

    nonisolated static func exportGPX(snapshots: [TripExportSnapshot]) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Milehound">"#
        ]
        let formatter = ISO8601DateFormatter()

        for snapshot in snapshots {
            lines.append(#"<trk>"#)
            lines.append(#"<name>\#(xmlEscape(snapshot.kmlName))</name>"#)
            if let note = snapshot.note, !note.isEmpty {
                lines.append(#"<desc>\#(xmlEscape(note))</desc>"#)
            }
            lines.append(#"<trkseg>"#)
            for point in snapshot.points {
                lines.append(
                    #"<trkpt lat="\#(point.latitude)" lon="\#(point.longitude)">"#
                )
                lines.append(#"<time>\#(formatter.string(from: point.timestamp))</time>"#)
                if let speed = point.speedMps, speed > 0 {
                    lines.append(#"<speed>\#(speed)</speed>"#)
                }
                lines.append(#"</trkpt>"#)
            }
            lines.append(#"</trkseg>"#)
            lines.append(#"</trk>"#)
        }

        lines.append(#"</gpx>"#)
        return lines.joined(separator: "\n")
    }

    static func exportKML(trips: [Trip], blurCoordinates: Bool) -> String {
        exportKML(snapshots: trips.map { snapshot(from: $0, blurCoordinates: blurCoordinates) })
    }

    nonisolated static func exportKML(snapshots: [TripExportSnapshot]) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<kml xmlns="http://www.opengis.net/kml/2.2">"#,
            "<Document>"
        ]

        for snapshot in snapshots {
            lines.append(#"<Placemark>"#)
            lines.append(#"<name>\#(xmlEscape(snapshot.kmlName))</name>"#)
            lines.append(#"<description>\#(xmlEscape(snapshot.routeSummary))</description>"#)
            lines.append(#"<LineString><tessellate>1</tessellate><coordinates>"#)
            let coordinates = snapshot.points.map { point in
                "\(point.longitude),\(point.latitude),0"
            }.joined(separator: " ")
            lines.append(coordinates)
            lines.append(#"</coordinates></LineString>"#)
            lines.append(#"</Placemark>"#)
        }

        lines.append("</Document>")
        lines.append("</kml>")
        return lines.joined(separator: "\n")
    }

    private static func snapshot(from trip: Trip, blurCoordinates: Bool) -> TripExportSnapshot {
        let points = trip.sortedPoints.map { point in
            let coordinate = blurCoordinates
                ? PlaceMatchingService.blurredCoordinate(point.coordinate)
                : point.coordinate
            return ExportPoint(
                timestamp: point.timestamp,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                sequence: point.sequence,
                speedMps: point.speedMps
            )
        }
        return TripExportSnapshot(
            id: trip.id,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt,
            distanceMeters: trip.distanceMeters,
            startAddress: trip.startAddress,
            endAddress: trip.endAddress,
            note: trip.note,
            categoryRaw: trip.categoryRaw,
            estimatedFuelCost: trip.estimatedFuelCost,
            dynamicFuelCost: trip.dynamicFuelCost,
            displayStartName: trip.displayStartName,
            displayEndName: trip.displayEndName,
            routeSummary: "\(trip.displayStartName) → \(trip.displayEndName)",
            kmlName: DateFormatters.tripDate.string(from: trip.startedAt),
            points: points
        )
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
