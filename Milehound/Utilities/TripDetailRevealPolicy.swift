import Foundation

/// Performance-oriented rules for trip detail route reveal animation.
enum TripDetailRevealPolicy {
    struct AnimationPlan: Equatable {
        let shouldAnimate: Bool
        let tickCount: Int
        let stepSleepMilliseconds: Int
        /// Flat elevation + solid-only stroke during reveal ticks.
        let useCheapMapDuringReveal: Bool
    }

    /// `pointCount` is retained for call-site compatibility; animate decision ignores it.
    /// First open always draws (~12 ticks, single polyline) unless Reduce Motion.
    static func animationPlan(pointCount: Int, reduceMotion: Bool) -> AnimationPlan {
        _ = pointCount
        if reduceMotion {
            return AnimationPlan(
                shouldAnimate: false,
                tickCount: 0,
                stepSleepMilliseconds: 0,
                useCheapMapDuringReveal: true
            )
        }

        return AnimationPlan(
            shouldAnimate: true,
            tickCount: 12,
            stepSleepMilliseconds: 40,
            useCheapMapDuringReveal: true
        )
    }

    static func quantizedProgress(rawProgress: Double, tick: Int, tickCount: Int) -> Double {
        guard tickCount > 0 else { return min(1, max(0, rawProgress)) }
        let clampedTick = min(tickCount, max(0, tick))
        return Double(clampedTick) / Double(tickCount)
    }
}
