import SnapshotTesting
import UIKit

extension Snapshotting where Value == UIViewController, Format == UIImage {
    /// Light shell renders are stored as 16-bit Display P3. A `perceptualPrecision`
    /// below 1 compares those bytes with color management turned off and reports a
    /// mismatch for images that already agree once both are drawn into 8-bit sRGB.
    /// Precision `1` keeps that 8-bit check, which is the stable one on CI.
    static func shellImage(precision: Float = 0.98, size: CGSize) -> Snapshotting {
        .image(precision: precision, perceptualPrecision: 1, size: size)
    }
}
