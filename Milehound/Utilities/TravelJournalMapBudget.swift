import CoreLocation
import Foundation

/// Caps how many polyline vertices a travel-journal map may draw.
enum TravelJournalMapBudget {
    static let totalCap = 4000

    /// Allocates a per-trip vertex budget that sums to at most `totalCap`.
    /// Endpoints are preserved: a path with at least two points never drops below 2.
    static func allocate(pointCounts: [Int], totalCap: Int = totalCap) -> [Int] {
        let counts = pointCounts.map { max(0, $0) }
        let sum = counts.reduce(0, +)
        guard sum > totalCap else { return counts }

        var allocated = counts.map { count -> Int in
            guard count >= 2 else { return count }
            let share = Int((Double(count) / Double(sum) * Double(totalCap)).rounded(.down))
            return max(2, min(count, share))
        }

        let used = allocated.reduce(0, +)
        if used > totalCap {
            var overflow = used - totalCap
            for index in allocated.indices.reversed() where overflow > 0 {
                let reducible = allocated[index] - (counts[index] >= 2 ? 2 : 0)
                let cut = min(reducible, overflow)
                allocated[index] -= cut
                overflow -= cut
            }
            return allocated
        }

        var remainder = totalCap - used
        let order = allocated.indices.sorted { counts[$0] > counts[$1] }
        while remainder > 0 {
            var granted = false
            for index in order where remainder > 0 {
                guard allocated[index] < counts[index] else { continue }
                allocated[index] += 1
                remainder -= 1
                granted = true
            }
            if !granted { break }
        }
        return allocated
    }

    /// Evenly samples `coordinates` down to `maxCount`, always keeping both ends.
    static func downsample(
        _ coordinates: [CLLocationCoordinate2D],
        to maxCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maxCount, maxCount >= 2 else { return coordinates }
        if maxCount == 2 {
            return [coordinates[0], coordinates[coordinates.count - 1]]
        }
        let last = coordinates.count - 1
        return (0..<maxCount).map { step in
            let index = step == maxCount - 1
                ? last
                : Int((Double(step) * Double(last) / Double(maxCount - 1)).rounded())
            return coordinates[index]
        }
    }
}
