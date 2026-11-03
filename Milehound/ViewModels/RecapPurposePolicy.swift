import Foundation

enum RecapPurposeKind: String, Codable, Equatable, Sendable {
    case business
    case personal
    case custom
}

struct RecapPurposeBucket: Equatable, Sendable {
    var kind: RecapPurposeKind
    var customName: String?
    var distanceMeters: Double
}

struct RecapPurposeSlice: Equatable, Sendable, Codable {
    var kind: RecapPurposeKind
    var customName: String?
    var distanceMeters: Double
    /// Share of categorized distance, 0...1.
    var share: Double
}

struct RecapPurposeVerdict: Equatable, Sendable, Codable {
    var kind: RecapPurposeKind
    var customName: String?
    var distanceMeters: Double
    /// Winner share of categorized distance, 0...1.
    var share: Double
    /// Ranked mix shown on the story (winner first). Caps at `RecapPurposePolicy.maxVisibleSlices`.
    var slices: [RecapPurposeSlice]
}

enum RecapPurposePolicy {
    static let minWinnerMeters: Double = 50_000
    static let minWinnerShare: Double = 0.45
    static let minLeadOverSecond: Double = 0.12
    static let maxVisibleSlices = 4

    static func kind(forCategoryID categoryID: String) -> RecapPurposeKind {
        if categoryID == BuiltInCategory.businessID.uuidString
            || categoryID == TripCategory.business.rawValue {
            return .business
        }
        if categoryID == BuiltInCategory.personalID.uuidString
            || categoryID == TripCategory.personal.rawValue
            || categoryID.isEmpty {
            return .personal
        }
        return .custom
    }

    static func bucketKey(forCategoryID categoryID: String, knownCustomIDs: Set<String>) -> String {
        switch kind(forCategoryID: categoryID) {
        case .business:
            return "business"
        case .personal:
            return "personal"
        case .custom:
            return knownCustomIDs.contains(categoryID) ? categoryID : "other"
        }
    }

    static func verdict(from buckets: [RecapPurposeBucket]) -> RecapPurposeVerdict? {
        let live = buckets.filter { $0.distanceMeters > 0 }
        guard live.count >= 2 else { return nil }
        let total = live.reduce(0) { $0 + $1.distanceMeters }
        guard total > 0 else { return nil }
        let ranked = live.sorted { lhs, rhs in
            if lhs.distanceMeters != rhs.distanceMeters {
                return lhs.distanceMeters > rhs.distanceMeters
            }
            return tieKey(lhs) < tieKey(rhs)
        }
        let winner = ranked[0]
        let second = ranked[1]
        guard winner.distanceMeters > second.distanceMeters else { return nil }
        let share = winner.distanceMeters / total
        let lead = share - (second.distanceMeters / total)
        guard winner.distanceMeters >= minWinnerMeters else { return nil }
        guard share >= minWinnerShare || lead >= minLeadOverSecond else { return nil }
        return RecapPurposeVerdict(
            kind: winner.kind,
            customName: winner.kind == .custom ? winner.customName : nil,
            distanceMeters: winner.distanceMeters,
            share: share,
            slices: visibleSlices(ranked: ranked, total: total)
        )
    }

    static func shouldPresent(_ verdict: RecapPurposeVerdict?) -> Bool {
        verdict != nil
    }

    static func heroTitle(for verdict: RecapPurposeVerdict) -> String {
        switch verdict.kind {
        case .business:
            return L10n.string("premium.recap.purpose_hero_business")
        case .personal:
            return L10n.string("premium.recap.purpose_hero_personal")
        case .custom:
            let name = normalizedCustomName(verdict.customName)
            return String(format: L10n.string("premium.recap.purpose_hero_custom"), name)
        }
    }

    static func whisper(for verdict: RecapPurposeVerdict) -> String {
        let percent = Int((verdict.share * 100).rounded())
        return String(format: L10n.string("premium.recap.purpose_whisper"), percent)
    }

    static func percentLabel(_ share: Double) -> String {
        String(format: L10n.string("premium.recap.purpose_percent"), Int((share * 100).rounded()))
    }

    static func displayName(for slice: RecapPurposeSlice) -> String {
        switch slice.kind {
        case .business:
            return L10n.string("premium.recap.business")
        case .personal:
            return L10n.string("premium.recap.personal")
        case .custom:
            return normalizedCustomName(slice.customName)
        }
    }

    static func normalizedCustomName(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.string("premium.recap.other") : trimmed
    }

    static func visibleSlices(ranked: [RecapPurposeBucket], total: Double) -> [RecapPurposeSlice] {
        guard total > 0 else { return [] }
        if ranked.count <= maxVisibleSlices {
            return ranked.map { slice(from: $0, total: total) }
        }
        let head = Array(ranked.prefix(maxVisibleSlices - 1))
        let restMeters = ranked.dropFirst(maxVisibleSlices - 1).reduce(0) { $0 + $1.distanceMeters }
        var slices = head.map { slice(from: $0, total: total) }
        slices.append(
            RecapPurposeSlice(
                kind: .custom,
                customName: nil,
                distanceMeters: restMeters,
                share: restMeters / total
            )
        )
        return slices
    }

    private static func slice(from bucket: RecapPurposeBucket, total: Double) -> RecapPurposeSlice {
        RecapPurposeSlice(
            kind: bucket.kind,
            customName: bucket.kind == .custom ? bucket.customName : nil,
            distanceMeters: bucket.distanceMeters,
            share: bucket.distanceMeters / total
        )
    }

    private static func tieKey(_ bucket: RecapPurposeBucket) -> String {
        switch bucket.kind {
        case .business: "0-business"
        case .personal: "1-personal"
        case .custom: "2-\(bucket.customName ?? "")"
        }
    }
}
