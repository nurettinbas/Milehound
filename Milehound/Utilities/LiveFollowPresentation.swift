import CoreGraphics

/// Pure layout math for the live-follow open/close transition.
///
/// Open: map fades in; road vehicle mark flies into the nav puck.
/// Close: map fades out; nav puck flies back to the list-card vehicle mark.
/// Keeps MapKit out of the animation path: callers interpolate cheap rects only.
enum LiveFollowPresentation {
    /// Cluster height estimate (tools, route chip, three stats, actions) when intrinsic size is unknown.
    static let estimatedSettledHUDHeight: CGFloat = 148
    /// The cluster stays a compact corner control. It does not grow with the map.
    static let compactHUDWidthCap: CGFloat = 220
    static let landscapeCoverHUDWidthCap: CGFloat = compactHUDWidthCap
    static let paneHUDWidthCap: CGFloat = compactHUDWidthCap
    static let settledBottomPadding: CGFloat = 12
    /// Matches `containerRelativeFrame(..., count: 12, span: 8)`.
    static let settledWidthSpan: CGFloat = 8
    static let settledWidthCount: CGFloat = 12

    static func clampedProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    static func lerpRect(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        let t = clampedProgress(progress)
        return CGRect(
            x: lerp(from.minX, to.minX, t),
            y: lerp(from.minY, to.minY, t),
            width: lerp(from.width, to.width, t),
            height: lerp(from.height, to.height, t)
        )
    }

    /// Column width for the live-map cluster. `8/12` of the map, then the cover or pane cap.
    static func hudColumnWidth(
        containerWidth: CGFloat,
        landscapeCover: Bool,
        fillsPane: Bool
    ) -> CGFloat {
        let proportional = min(
            containerWidth * settledWidthSpan / settledWidthCount,
            max(0, containerWidth - 32)
        )
        let cap = landscapeCover || fillsPane ? compactHUDWidthCap : compactHUDWidthCap
        return min(proportional, cap)
    }

    /// Widths for the live-map row. Stats and Pause/Stop keep their own width;
    /// the middle slot gets only the gap between them, so a landscape phone pane
    /// cannot push either end off the map.
    static func hudColumns(
        availableWidth: CGFloat,
        statsWidth: CGFloat,
        controlsWidth: CGFloat,
        spacing: CGFloat = 6
    ) -> (stats: CGFloat, switches: CGFloat, controls: CGFloat) {
        let available = max(0, availableWidth)
        let stats = max(0, statsWidth)
        let controls = max(0, controlsWidth)
        let gap = max(0, spacing) * 2
        let switches = max(0, available - stats - controls - gap)
        return (stats, switches, controls)
    }

    /// Settled bottom HUD frame inside `container` (same coordinate space).
    static func settledHUDRect(
        in container: CGRect,
        hudHeight: CGFloat = estimatedSettledHUDHeight,
        bottomPadding: CGFloat = settledBottomPadding
    ) -> CGRect {
        let width = container.width * (settledWidthSpan / settledWidthCount)
        let height = max(hudHeight, 1)
        let x = container.minX + (container.width - width) / 2
        let y = container.maxY - bottomPadding - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Card morph: source list card → settled bottom HUD.
    static func hudRect(source: CGRect, settled: CGRect, progress: CGFloat) -> CGRect {
        lerpRect(from: source, to: settled, progress: progress)
    }

    /// Close phase 1 target: source-sized card, bottom edge pinned where the HUD sat.
    static func expandedAtBottomRect(source: CGRect, settled: CGRect) -> CGRect {
        let width = max(source.width, 1)
        let height = max(source.height, 1)
        return CGRect(
            x: settled.midX - width / 2,
            y: settled.maxY - height,
            width: width,
            height: height
        )
    }

    /// Close morph: expand at bottom (`expandProgress`), then rise to list card (`riseProgress`).
    static func closeHudRect(
        source: CGRect,
        settled: CGRect,
        expandProgress: CGFloat,
        riseProgress: CGFloat
    ) -> CGRect {
        let e = clampedProgress(expandProgress)
        let r = clampedProgress(riseProgress)
        let width = lerp(settled.width, source.width, e)
        let height = lerp(settled.height, source.height, e)
        // Bottom edge stays pinned while growing; then the whole rect rises to `source`.
        let atBottom = CGRect(
            x: settled.midX - width / 2,
            y: settled.maxY - height,
            width: width,
            height: height
        )
        return lerpRect(from: atBottom, to: source, progress: r)
    }

    /// Valid source when the list card reported a real frame; otherwise a fallback mid-screen card.
    static func sourceRect(from anchor: RecordingCardAnchor, fallbackContainer: CGRect) -> CGRect {
        if anchor.width > 1, anchor.height > 1 {
            return anchor.rect
        }
        let width = min(fallbackContainer.width - 32, 360)
        let height = estimatedSettledHUDHeight + 80
        return CGRect(
            x: fallbackContainer.midX - width / 2,
            y: fallbackContainer.minY + 96,
            width: width,
            height: height
        )
    }

    /// Road / vehicle mark frame for the open hero flight (global coords).
    static func heroSourceRect(from anchor: RecordingCardAnchor, cardFallback: CGRect) -> CGRect {
        if anchor.hasCarFrame {
            return anchor.carRect
        }
        let width: CGFloat = min(cardFallback.width * 0.45, 120)
        let height: CGFloat = 56
        return CGRect(
            x: cardFallback.midX - width / 2,
            y: cardFallback.minY + 40,
            width: width,
            height: height
        )
    }

    /// Fallback hero landing when MapKit has not projected the live vehicle yet.
    /// Camera is locked to the vehicle, so the annotation coordinate is screen center.
    static func heroDestCenter(in containerSize: CGSize, uses3D _: Bool = true) -> CGPoint {
        return puckCircleCenter(
            fromProjectedAnnotationPoint: CGPoint(
                x: containerSize.width / 2,
                y: containerSize.height / 2
            )
        )
    }

    /// Matches `LiveFollowPuckAnnotationView` / `LiveFollowPuckMark` circle size.
    static let puckCircleSize: CGFloat = 56
    static let puckChevronHeight: CGFloat = 38
    static let puckChevronOverlap: CGFloat = 18
    static let puckFrameVerticalExtra: CGFloat = 14

    /// Circle + chevron bounds (pulse padding below is excluded).
    static var puckArtworkHeight: CGFloat {
        puckCircleSize + puckChevronHeight - puckChevronOverlap
    }

    static var puckAnnotationFrameHeight: CGFloat {
        puckArtworkHeight + puckFrameVerticalExtra
    }

    /// Puts the **photo circle's center** exactly on the map coordinate.
    ///
    /// The route tail also terminates at that coordinate, so the trail runs straight
    /// through the middle of the puck. Centring the whole circle+chevron artwork instead
    /// lifts the circle ~10 pt up the screen, and under a 62° pitch those points are a
    /// long way forward on the ground — on a bend the puck then sits beside the trail.
    static var puckAnnotationCenterOffset: CGPoint {
        CGPoint(x: 0, y: puckAnnotationFrameHeight / 2 - puckCircleSize / 2)
    }

    /// Artwork is drawn pointing screen-up. Rotate it by this many radians so the
    /// chevron's sharp tip (and the photo) face `travelHeading` on a map whose
    /// camera heading is `mapHeading`. Near zero while following on a straight; through a
    /// turn the eased camera trails the vehicle and the chevron leads by the gap.
    static func puckRotationRadians(
        travelHeadingDegrees: Double,
        mapHeadingDegrees: Double
    ) -> CGFloat {
        var delta = travelHeadingDegrees - mapHeadingDegrees
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return CGFloat(delta * .pi / 180)
    }

    /// Screen position of the puck photo-circle center from MapKit's projected annotation point.
    ///
    /// `projectedPoint` is `map.convert(coordinate, toPointTo: map)`. The annotation view's
    /// geometric center is offset by `puckAnnotationCenterOffset`, and the circle sits at
    /// the top of that view.
    static func puckCircleCenter(fromProjectedAnnotationPoint projectedPoint: CGPoint) -> CGPoint {
        let viewCenterY = projectedPoint.y + puckAnnotationCenterOffset.y
        let circleCenterY = viewCenterY - puckAnnotationFrameHeight / 2 + puckCircleSize / 2
        return CGPoint(x: projectedPoint.x + puckAnnotationCenterOffset.x, y: circleCenterY)
    }

    /// How far the hero arc bows off the straight chord (fraction of chord length).
    /// Large enough to read as a sweep, not a straight drop.
    static let heroArcLiftFactor: CGFloat = 0.45

    static func lerpPoint(from: CGPoint, to: CGPoint, progress: CGFloat) -> CGPoint {
        let t = clampedProgress(progress)
        return CGPoint(x: lerp(from.x, to.x, t), y: lerp(from.y, to.y, t))
    }

    /// Control point for a side-sweep quadratic arc (out, then down — open + close share this path).
    static func heroControlPoint(
        from: CGPoint,
        to: CGPoint,
        liftFactor: CGFloat = heroArcLiftFactor
    ) -> CGPoint {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let length = max(hypot(to.x - from.x, to.y - from.y), 1)
        let lift = length * liftFactor
        // Prefer a leftward bow (leading edge) with a slight upward peak before the descent.
        return CGPoint(
            x: mid.x - lift * 0.9,
            y: mid.y - lift * 0.28
        )
    }

    static func quadraticBezier(
        from: CGPoint,
        control: CGPoint,
        to: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        let t = clampedProgress(progress)
        let u = 1 - t
        return CGPoint(
            x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
        )
    }

    /// Curved hero flight (list card ↔ map puck). Same path both ways via `progress` 0…1.
    static func heroFlightPoint(from: CGPoint, to: CGPoint, progress: CGFloat) -> CGPoint {
        let control = heroControlPoint(from: from, to: to)
        return quadraticBezier(from: from, control: control, to: to, progress: progress)
    }

    /// Reduce Motion skips the expand spring — treat as fully settled.
    static func initialProgress(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : 0
    }
}
