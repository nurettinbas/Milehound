import Foundation

/// Binary codec for `TripRoutePathCache`. Kept in its own file with no `@MainActor`
/// types so disk-queue / detached tasks can encode and decode freely under
/// `SWIFT_STRICT_CONCURRENCY = complete`.
enum TripRoutePathCodec: Sendable {
    private static let magic: [UInt8] = [0x54, 0x48, 0x52, 0x50] // "THRP"
    private static let formatVersion: UInt32 = 1

    nonisolated static func encode(_ payload: TripRoutePathPayload) -> Data {
        var data = Data()
        data.append(contentsOf: magic)
        appendUInt32(formatVersion, to: &data)
        appendDouble(payload.fingerprint.distanceMeters, to: &data)
        appendDouble(payload.fingerprint.startedAt, to: &data)
        appendDouble(payload.fingerprint.endedAt, to: &data)
        appendDouble(payload.fingerprint.startLatitude, to: &data)
        appendDouble(payload.fingerprint.startLongitude, to: &data)
        appendDouble(payload.fingerprint.endLatitude, to: &data)
        appendDouble(payload.fingerprint.endLongitude, to: &data)
        appendUInt32(UInt32(payload.pieces.count), to: &data)
        for piece in payload.pieces {
            appendUInt32(UInt32(piece.count), to: &data)
            for point in piece {
                appendDouble(point.latitude, to: &data)
                appendDouble(point.longitude, to: &data)
                appendDouble(point.timestamp, to: &data)
                appendDouble(point.speedMps ?? .nan, to: &data)
            }
        }
        return data
    }

    nonisolated static func decode(_ data: Data) -> TripRoutePathPayload? {
        var cursor = 0
        guard data.count >= 4 + 4 + (8 * 7) + 4 else { return nil }
        guard Array(data[cursor..<(cursor + 4)]) == magic else { return nil }
        cursor += 4
        guard let version = readUInt32(data, cursor: &cursor), version == formatVersion else { return nil }
        guard
            let distanceMeters = readDouble(data, cursor: &cursor),
            let startedAt = readDouble(data, cursor: &cursor),
            let endedAt = readDouble(data, cursor: &cursor),
            let startLatitude = readDouble(data, cursor: &cursor),
            let startLongitude = readDouble(data, cursor: &cursor),
            let endLatitude = readDouble(data, cursor: &cursor),
            let endLongitude = readDouble(data, cursor: &cursor),
            let pieceCount = readUInt32(data, cursor: &cursor)
        else { return nil }

        var pieces: [[CachedRoutePoint]] = []
        pieces.reserveCapacity(Int(pieceCount))
        for _ in 0..<pieceCount {
            guard let pointCount = readUInt32(data, cursor: &cursor) else { return nil }
            var points: [CachedRoutePoint] = []
            points.reserveCapacity(Int(pointCount))
            for _ in 0..<pointCount {
                guard
                    let latitude = readDouble(data, cursor: &cursor),
                    let longitude = readDouble(data, cursor: &cursor),
                    let timestamp = readDouble(data, cursor: &cursor),
                    let speed = readDouble(data, cursor: &cursor)
                else { return nil }
                points.append(
                    CachedRoutePoint(
                        latitude: latitude,
                        longitude: longitude,
                        timestamp: timestamp,
                        speedMps: speed.isNaN ? nil : speed
                    )
                )
            }
            pieces.append(points)
        }

        return TripRoutePathPayload(
            fingerprint: TripRoutePathFingerprint(
                distanceMeters: distanceMeters,
                startedAt: startedAt,
                endedAt: endedAt,
                startLatitude: startLatitude,
                startLongitude: startLongitude,
                endLatitude: endLatitude,
                endLongitude: endLongitude
            ),
            pieces: pieces
        )
    }

    nonisolated static func read(from url: URL) -> TripRoutePathPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    nonisolated static func write(_ payload: TripRoutePathPayload, to url: URL) {
        let data = encode(payload)
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private nonisolated static func appendDouble(_ value: Double, to data: inout Data) {
        var value = value.bitPattern.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private nonisolated static func readUInt32(_ data: Data, cursor: inout Int) -> UInt32? {
        guard cursor + 4 <= data.count else { return nil }
        let value = data.subdata(in: cursor..<(cursor + 4)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        cursor += 4
        return value
    }

    private nonisolated static func readDouble(_ data: Data, cursor: inout Int) -> Double? {
        guard cursor + 8 <= data.count else { return nil }
        let bits = data.subdata(in: cursor..<(cursor + 8)).withUnsafeBytes {
            $0.load(as: UInt64.self).bigEndian
        }
        cursor += 8
        return Double(bitPattern: bits)
    }
}
