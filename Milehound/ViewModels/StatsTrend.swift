import Foundation

/// Period-over-period change computed once on a snapshot — never in a SwiftUI body loop.
struct StatsTrend: Equatable, Sendable {
    enum Polarity: Equatable, Sendable {
        case higherIsBetter
        case lowerIsBetter
        case neutral
    }

    enum Direction: Equatable, Sendable {
        case up
        case down
        case flat
    }

    /// `nil` when there is no previous baseline (`isNovel`).
    let percent: Double?
    let polarity: Polarity
    /// Previous period was empty and the current value is positive.
    let isNovel: Bool

    var direction: Direction {
        guard let percent else { return .flat }
        let rounded = percent.rounded()
        if rounded > 0 { return .up }
        if rounded < 0 { return .down }
        return .flat
    }

    var isFavorable: Bool? {
        guard !isNovel else { return nil }
        switch polarity {
        case .neutral:
            return nil
        case .higherIsBetter:
            switch direction {
            case .up: return true
            case .down: return false
            case .flat: return nil
            }
        case .lowerIsBetter:
            switch direction {
            case .up: return false
            case .down: return true
            case .flat: return nil
            }
        }
    }

    var systemImage: String? {
        if isNovel { return nil }
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return nil
        }
    }

    var displayText: String? {
        if isNovel {
            return L10n.string("stats.trend.new")
        }
        guard let percent else { return nil }
        let format = L10n.string("stats.trend.format")
        let sign = percent > 0 ? "+" : ""
        return String(format: format, sign, Int(percent.rounded()))
    }

    func accessibilityLabel(metricName: String) -> String {
        if isNovel {
            return String(format: L10n.string("stats.trend.a11y.new"), metricName)
        }
        switch direction {
        case .up:
            return String(
                format: L10n.string("stats.trend.a11y.up"),
                metricName,
                Int(percent?.rounded() ?? 0)
            )
        case .down:
            return String(
                format: L10n.string("stats.trend.a11y.down"),
                metricName,
                Int(abs(percent?.rounded() ?? 0))
            )
        case .flat:
            return String(format: L10n.string("stats.trend.a11y.flat"), metricName)
        }
    }

    /// - Returns: `nil` when both sides are empty. Novel when previous is 0 and current > 0.
    static func make(current: Double, previous: Double, polarity: Polarity) -> StatsTrend? {
        if previous <= 0 {
            guard current > 0 else { return nil }
            return StatsTrend(percent: nil, polarity: polarity, isNovel: true)
        }
        let percent = ((current - previous) / previous) * 100
        return StatsTrend(percent: percent, polarity: polarity, isNovel: false)
    }
}
