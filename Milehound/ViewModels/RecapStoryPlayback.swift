import CoreGraphics
import Foundation

enum RecapStoryPlaybackCommand: Equatable, Sendable {
    case stay
    case moved
    case finished
}

struct RecapStoryPlayback: Equatable, Sendable {
    static let pageDuration: TimeInterval = 4.5

    private(set) var pageIndex: Int
    let pageCount: Int
    private(set) var isPaused: Bool
    private(set) var remaining: TimeInterval
    let autoplayEnabled: Bool

    init(pageCount: Int, autoplayEnabled: Bool, startIndex: Int = 0) {
        let count = max(1, pageCount)
        self.pageCount = count
        self.pageIndex = min(max(0, startIndex), count - 1)
        self.autoplayEnabled = autoplayEnabled
        self.remaining = Self.pageDuration
        self.isPaused = !autoplayEnabled
    }

    var isFirstPage: Bool { pageIndex <= 0 }
    var isLastPage: Bool { pageIndex >= pageCount - 1 }

    var activeSegmentProgress: Double {
        if !autoplayEnabled {
            return 0
        }
        let clamped = min(Self.pageDuration, max(0, remaining))
        return 1 - clamped / Self.pageDuration
    }

    func fill(forSegment index: Int) -> Double {
        if index < pageIndex { return 1 }
        if index > pageIndex { return 0 }
        return activeSegmentProgress
    }

    mutating func advance() -> RecapStoryPlaybackCommand {
        guard pageIndex + 1 < pageCount else { return .finished }
        pageIndex += 1
        remaining = Self.pageDuration
        if autoplayEnabled {
            isPaused = false
        }
        return .moved
    }

    mutating func retreat() -> RecapStoryPlaybackCommand {
        guard pageIndex > 0 else { return .stay }
        pageIndex -= 1
        remaining = Self.pageDuration
        if autoplayEnabled {
            isPaused = false
        }
        return .moved
    }

    mutating func pause() {
        isPaused = true
    }

    mutating func resume() {
        guard autoplayEnabled else { return }
        isPaused = false
    }

    mutating func setRemaining(_ value: TimeInterval) {
        remaining = min(Self.pageDuration, max(0, value))
    }

    /// Ticks the active page. Last page fills, then `.finished` so the cover can dismiss.
    mutating func consume(_ interval: TimeInterval) -> RecapStoryPlaybackCommand {
        guard autoplayEnabled, !isPaused else { return .stay }
        remaining -= interval
        if remaining > 0 { return .stay }
        remaining = 0
        if isLastPage {
            isPaused = true
            return .finished
        }
        return advance()
    }
}

enum RecapStoryTapMetrics {
    static let backWidthFraction: CGFloat = 1.0 / 3.0
    static let holdDuration: TimeInterval = 0.18

    static func isBack(x: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        return x < width * backWidthFraction
    }
}

enum RecapStoryChromeMetrics {
    /// Floor when the key window reports 0 (cover / overlay zeroed SwiftUI inset).
    static let minimumTopInset: CGFloat = 54
    /// Instagram-style gap under the status bar / Dynamic Island.
    static let extraTopPadding: CGFloat = 8

    /// Padding from the **physical** top. Chrome ignores SwiftUI’s top safe area so this is not stacked on it.
    static func topPadding(windowTop: CGFloat) -> CGFloat {
        let inset = windowTop > 1 ? windowTop : minimumTopInset
        return inset + extraTopPadding
    }
}
