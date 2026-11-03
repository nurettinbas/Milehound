import CoreLocation
import SwiftUI

/// Lightweight route preview for live recording and end credits (no MapKit).
struct LiveBreadcrumbCanvas: View {
    let coordinates: [CLLocationCoordinate2D]
    var segments: [[CLLocationCoordinate2D]] = []
    var liveCoordinate: CLLocationCoordinate2D?
    var progress: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let paths = strokePaths(in: size)
            guard !paths.isEmpty else {
                drawLiveDot(context: &context, size: size, paths: [])
                return
            }

            for path in paths {
                context.stroke(
                    path,
                    with: .color(.white.opacity(0.92)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }

            drawLiveDot(context: &context, size: size, paths: paths)
        }
        .accessibilityHidden(true)
    }

    private func strokePaths(in size: CGSize) -> [Path] {
        if !segments.isEmpty {
            return segments.compactMap { segment in
                path(for: segment, in: size, progress: progress)
            }
        }
        if let path = path(for: coordinates, in: size, progress: progress) {
            return [path]
        }
        return []
    }

    private func path(
        for coordinates: [CLLocationCoordinate2D],
        in size: CGSize,
        progress: CGFloat
    ) -> Path? {
        let points = projectedPoints(for: coordinates, in: size)
        guard points.count >= 2 else { return nil }

        let revealedCount = max(
            2,
            Int(ceil(Double(points.count - 1) * Double(min(1, max(0, progress))))) + 1
        )
        let revealed = Array(points.prefix(revealedCount))

        var path = Path()
        path.move(to: revealed[0])
        for point in revealed.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func drawLiveDot(
        context: inout GraphicsContext,
        size: CGSize,
        paths: [Path]
    ) {
        guard let liveCoordinate else { return }
        let points = projectedPoints(for: [liveCoordinate], in: size)
        guard let tip = points.first else { return }

        var glow = Path()
        glow.addEllipse(in: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10))
        context.fill(glow, with: .color(.red.opacity(0.28)))

        var tipDot = Path()
        tipDot.addEllipse(in: CGRect(x: tip.x - 2.5, y: tip.y - 2.5, width: 5, height: 5))
        context.fill(tipDot, with: .color(.red))
        context.stroke(tipDot, with: .color(.white), lineWidth: 1)
    }

    private func projectedPoints(
        for coordinates: [CLLocationCoordinate2D],
        in size: CGSize
    ) -> [CGPoint] {
        guard let first = coordinates.first else { return [] }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let latSpan = max(maxLat - minLat, 0.00025)
        let lonSpan = max(maxLon - minLon, 0.00025)
        let inset: CGFloat = 6
        let drawWidth = max(size.width - inset * 2, 1)
        let drawHeight = max(size.height - inset * 2, 1)

        return coordinates.map { coordinate in
            let x = inset + CGFloat((coordinate.longitude - minLon) / lonSpan) * drawWidth
            let y = inset + CGFloat(1 - (coordinate.latitude - minLat) / latSpan) * drawHeight
            return CGPoint(x: x, y: y)
        }
    }
}
