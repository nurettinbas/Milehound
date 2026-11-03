import UIKit

enum VehiclePhotoCropMath {
    /// Largest edge kept when preparing a gallery/camera image for the crop UI.
    static let prepMaxEdge: CGFloat = 2048

    /// `1` = aspect-fill (image covers the crop). Below 1 zooms out (letterbox OK); above 1 zooms in.
    static let defaultUserScale: CGFloat = 1
    /// Symmetric around default so the slider thumb starts centered.
    static let minUserScale: CGFloat = 0.35
    static let maxUserScale: CGFloat = 1.65

    static func coverScale(imageSize: CGSize, cropSide: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, cropSide > 0 else { return 1 }
        return max(cropSide / imageSize.width, cropSide / imageSize.height)
    }

    static func drawSize(imageSize: CGSize, cropSide: CGFloat, userScale: CGFloat) -> CGSize {
        let clamped = min(max(userScale, minUserScale), maxUserScale)
        let total = coverScale(imageSize: imageSize, cropSide: cropSide) * clamped
        return CGSize(width: imageSize.width * total, height: imageSize.height * total)
    }

    static func maxOffset(drawSize: CGSize, cropSide: CGFloat) -> CGSize {
        CGSize(
            width: max(0, (drawSize.width - cropSide) / 2),
            height: max(0, (drawSize.height - cropSide) / 2)
        )
    }

    static func clampedOffset(_ offset: CGSize, drawSize: CGSize, cropSide: CGFloat) -> CGSize {
        let limits = maxOffset(drawSize: drawSize, cropSide: cropSide)
        return CGSize(
            width: min(Swift.max(offset.width, -limits.width), limits.width),
            height: min(Swift.max(offset.height, -limits.height), limits.height)
        )
    }

    /// Normalizes orientation and optionally downscales for crop UI memory.
    static func prepareForCrop(_ image: UIImage, maxEdge: CGFloat = prepMaxEdge) -> UIImage {
        let upright = normalized(image)
        let longest = max(upright.size.width, upright.size.height)
        guard longest > maxEdge else { return upright }
        let ratio = maxEdge / longest
        let newSize = CGSize(
            width: max(1, (upright.size.width * ratio).rounded(.down)),
            height: max(1, (upright.size.height * ratio).rounded(.down))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            upright.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1 {
            return image
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let drawSize: CGSize
        if image.imageOrientation == .up {
            drawSize = CGSize(
                width: max(1, image.size.width * image.scale),
                height: max(1, image.size.height * image.scale)
            )
        } else {
            drawSize = image.size
        }
        let renderer = UIGraphicsImageRenderer(size: drawSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: drawSize))
        }
    }

    enum OrientationEdit {
        case rotateLeft
        case rotateRight
        case flipHorizontal
        case flipVertical
    }

    /// Returns a new upright image with the requested orientation edit applied.
    static func applying(_ edit: OrientationEdit, to image: UIImage) -> UIImage {
        let source = normalized(image)
        switch edit {
        case .rotateLeft:
            return rotated(source, degrees: -90)
        case .rotateRight:
            return rotated(source, degrees: 90)
        case .flipHorizontal:
            return flipped(source, horizontal: true, vertical: false)
        case .flipVertical:
            return flipped(source, horizontal: false, vertical: true)
        }
    }

    private static func rotated(_ image: UIImage, degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180
        let rotatedRect = CGRect(origin: .zero, size: image.size).applying(
            CGAffineTransform(rotationAngle: radians)
        )
        let newSize = CGSize(
            width: abs(rotatedRect.width),
            height: abs(rotatedRect.height)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: radians)
            image.draw(
                in: CGRect(
                    x: -image.size.width / 2,
                    y: -image.size.height / 2,
                    width: image.size.width,
                    height: image.size.height
                )
            )
        }
    }

    private static func flipped(_ image: UIImage, horizontal: Bool, vertical: Bool) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(
                x: horizontal ? size.width : 0,
                y: vertical ? size.height : 0
            )
            cg.scaleBy(
                x: horizontal ? -1 : 1,
                y: vertical ? -1 : 1
            )
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Renders the square visible in the crop window into `outputSide`×`outputSide` pixels.
    static func renderSquare(
        image: UIImage,
        cropSide: CGFloat,
        userScale: CGFloat,
        offset: CGSize,
        outputSide: CGFloat = VehiclePhotoStore.maxPixelSize
    ) -> UIImage? {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, cropSide > 0, outputSide > 0 else { return nil }

        let draw = drawSize(imageSize: imageSize, cropSide: cropSide, userScale: userScale)
        let clamped = clampedOffset(offset, drawSize: draw, cropSide: cropSide)
        let origin = CGPoint(
            x: (cropSide - draw.width) / 2 + clamped.width,
            y: (cropSide - draw.height) / 2 + clamped.height
        )

        // Crop window in image coordinates.
        let src = CGRect(
            x: -origin.x / draw.width * imageSize.width,
            y: -origin.y / draw.height * imageSize.height,
            width: cropSide / draw.width * imageSize.width,
            height: cropSide / draw.height * imageSize.height
        )
        guard src.width > 0.5, src.height > 0.5 else { return nil }

        let preservesAlpha = VehiclePhotoStore.imageHasAlpha(image)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !preservesAlpha
        let out = CGSize(width: outputSide, height: outputSide)
        let renderer = UIGraphicsImageRenderer(size: out, format: format)
        return renderer.image { ctx in
            if !preservesAlpha {
                UIColor.black.setFill()
                ctx.fill(CGRect(origin: .zero, size: out))
            }
            let dest = CGRect(
                x: -src.minX / src.width * outputSide,
                y: -src.minY / src.height * outputSide,
                width: imageSize.width / src.width * outputSide,
                height: imageSize.height / src.height * outputSide
            )
            image.draw(in: dest)
        }
    }
}
