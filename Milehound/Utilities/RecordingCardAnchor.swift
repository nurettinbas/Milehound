import CoreGraphics

/// Global frames for the live recording card (stop credits / live-follow).
struct RecordingCardAnchor: Equatable {
    var minX: CGFloat = 0
    var minY: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    /// Road / vehicle mark inside the card (hero → map puck).
    var carMinX: CGFloat = 0
    var carMinY: CGFloat = 0
    var carWidth: CGFloat = 0
    var carHeight: CGFloat = 0

    var rect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }

    var carRect: CGRect {
        CGRect(x: carMinX, y: carMinY, width: carWidth, height: carHeight)
    }

    var hasCarFrame: Bool {
        carWidth > 1 && carHeight > 1
    }
}

/// Holds the anchor outside SwiftUI's dependency graph.
///
/// The frame is only read when Stop / live-follow is pressed, but keeping it in `@State`
/// meant every scroll frame moved the card far enough to write it, rebuilding the whole
/// card each frame.
@MainActor
final class RecordingCardAnchorBox {
    var value = RecordingCardAnchor()
}
