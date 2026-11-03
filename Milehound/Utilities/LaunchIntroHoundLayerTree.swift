import UIKit

/// Images for `LaunchIntroHoundRig`. Nil when any part is missing, so the flat hound plays instead.
struct LaunchIntroHoundParts {
    var rig: LaunchIntroHoundRig
    var images: [String: UIImage]

    static func load(rig: LaunchIntroHoundRig = .standard) -> LaunchIntroHoundParts? {
        var images: [String: UIImage] = [:]
        for bone in rig.bones {
            guard let image = UIImage(named: bone.asset) else { return nil }
            images[bone.asset] = image
        }
        return LaunchIntroHoundParts(rig: rig, images: images)
    }

    func cgImage(named asset: String, tint: UIColor?) -> CGImage? {
        guard let image = images[asset], let source = image.cgImage else { return nil }
        guard let tint else { return source }
        let size = CGSize(width: source.width, height: source.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.setFillColor(tint.cgColor)
            cg.fill(bounds)
            cg.setBlendMode(.destinationIn)
            cg.draw(source, in: bounds)
        }
        return rendered.cgImage
    }
}

/// Nested bone layers shared by the cold-launch intro and the Start control.
/// Joint math lives here so the two call sites cannot drift.
enum LaunchIntroHoundLayerTree {
    struct Mounted {
        let root: CALayer
        let art: CGSize
        let joints: [(layer: CALayer, swing: LaunchIntroHoundRig.Curve)]
        let imageLayers: [String: CALayer]
        let rig: LaunchIntroHoundRig
    }

    /// Builds the icon’s hound into `frame`, scaled to fit. `tint` recolors template parts;
    /// `nil` keeps the source pixels (white on the launch plate). `fit` shrinks the art inside
    /// the same box so a stride’s swing clears a tight chrome edge.
    @discardableResult
    static func add(
        parts: LaunchIntroHoundParts,
        in frame: CGRect,
        on parent: CALayer,
        contentsScale: CGFloat,
        tint: UIColor? = nil,
        fit: CGFloat = 1
    ) -> Mounted {
        let rig = parts.rig
        let scale = min(frame.width / rig.canvas.width, frame.height / rig.canvas.height) * fit
        let art = CGSize(width: rig.canvas.width * scale, height: rig.canvas.height * scale)

        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: art)
        root.position = CGPoint(x: frame.midX, y: frame.midY)
        root.allowsGroupOpacity = true
        parent.addSublayer(root)

        var joints: [(layer: CALayer, swing: LaunchIntroHoundRig.Curve)] = []
        var imageLayers: [String: CALayer] = [:]
        addBone(
            rig.torso,
            parts: parts,
            scale: scale,
            contentsScale: contentsScale,
            tint: tint,
            to: root,
            joints: &joints,
            imageLayers: &imageLayers
        )
        return Mounted(root: root, art: art, joints: joints, imageLayers: imageLayers, rig: rig)
    }

    static func applyTint(_ tint: UIColor?, to mounted: Mounted, parts: LaunchIntroHoundParts) {
        for bone in mounted.rig.bones {
            mounted.imageLayers[bone.asset]?.contents = parts.cgImage(named: bone.asset, tint: tint)
        }
    }

    /// Infinite 0.42 s cubic stride (envelope = 1). Same sample count as the intro gait.
    static func attachStrideLoop(to mounted: Mounted) {
        mounted.root.add(
            strideLoop(
                "transform.translation.y",
                rig: mounted.rig,
                curve: mounted.rig.bob,
                unit: mounted.art.height
            ),
            forKey: "bob"
        )
        for joint in mounted.joints {
            joint.layer.add(
                strideLoop("transform.rotation.z", rig: mounted.rig, curve: joint.swing),
                forKey: "swing"
            )
        }
    }

    static func removeStrideLoop(from mounted: Mounted) {
        mounted.root.removeAnimation(forKey: "bob")
        for joint in mounted.joints {
            joint.layer.removeAnimation(forKey: "swing")
        }
    }

    static func strideLoop(
        _ keyPath: String,
        rig: LaunchIntroHoundRig,
        curve: LaunchIntroHoundRig.Curve,
        unit: CGFloat = 1,
        samplesPerStride: Int = 16
    ) -> CAKeyframeAnimation {
        let samples = strideSamples(curve: curve, unit: unit, samplesPerStride: samplesPerStride)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = samples.values
        animation.keyTimes = samples.times
        animation.calculationMode = .cubic
        animation.repeatCount = .greatestFiniteMagnitude
        animation.duration = max(rig.stride, 0.01)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// Samples a rig curve across the run and close, so the gait dies out on the logo pose at `closeEnd`.
    static func envelopedGait(
        _ keyPath: String,
        rig: LaunchIntroHoundRig,
        curve: LaunchIntroHoundRig.Curve,
        timeline: LaunchIntroTimeline,
        unit: CGFloat = 1,
        samplesPerStride: Int = 16
    ) -> CAKeyframeAnimation {
        let length = max(timeline.closeEnd, 0.01)
        let step = max(rig.stride / Double(samplesPerStride), 0.005)
        var times: [NSNumber] = []
        var values: [CGFloat] = []
        var time: TimeInterval = 0
        while length - time > step * 0.25 {
            times.append(NSNumber(value: min(1, max(0, time / length))))
            values.append(rig.offset(curve, at: time, timeline: timeline) * unit)
            time += step
        }
        times.append(1)
        values.append(rig.offset(curve, at: length, timeline: timeline) * unit)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.calculationMode = .cubic
        animation.duration = length
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// One stride of `curve` (envelope = 1). First and last samples match so the loop is seamless.
    static func strideSamples(
        curve: LaunchIntroHoundRig.Curve,
        unit: CGFloat = 1,
        samplesPerStride: Int = 16
    ) -> (times: [NSNumber], values: [CGFloat]) {
        var times: [NSNumber] = []
        var values: [CGFloat] = []
        for index in 0...samplesPerStride {
            let phase = CGFloat(index) / CGFloat(samplesPerStride)
            times.append(NSNumber(value: Double(phase)))
            values.append(curve.value(at: phase) * unit)
        }
        return (times, values)
    }

    private static func addBone(
        _ bone: LaunchIntroHoundRig.Bone,
        parts: LaunchIntroHoundParts,
        scale: CGFloat,
        contentsScale: CGFloat,
        tint: UIColor?,
        to parent: CALayer,
        joints: inout [(layer: CALayer, swing: LaunchIntroHoundRig.Curve)],
        imageLayers: inout [String: CALayer]
    ) {
        let rig = parts.rig
        let layer = part(nil, pivot: bone.joint, canvas: rig.canvas, scale: scale, contentsScale: contentsScale)
        parent.addSublayer(layer)
        for child in bone.behind {
            addBone(
                child,
                parts: parts,
                scale: scale,
                contentsScale: contentsScale,
                tint: tint,
                to: layer,
                joints: &joints,
                imageLayers: &imageLayers
            )
        }
        let image = part(
            parts.cgImage(named: bone.asset, tint: tint),
            pivot: bone.joint,
            canvas: rig.canvas,
            scale: scale,
            contentsScale: contentsScale
        )
        layer.addSublayer(image)
        imageLayers[bone.asset] = image
        for child in bone.front {
            addBone(
                child,
                parts: parts,
                scale: scale,
                contentsScale: contentsScale,
                tint: tint,
                to: layer,
                joints: &joints,
                imageLayers: &imageLayers
            )
        }
        joints.append((layer, bone.swing))
    }

    /// A full-canvas layer that turns around `pivot` (canvas pixels).
    private static func part(
        _ image: CGImage?,
        pivot: CGPoint,
        canvas: CGSize,
        scale: CGFloat,
        contentsScale: CGFloat
    ) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: canvas.width * scale, height: canvas.height * scale)
        layer.anchorPoint = CGPoint(x: pivot.x / canvas.width, y: pivot.y / canvas.height)
        layer.position = CGPoint(x: pivot.x * scale, y: pivot.y * scale)
        layer.contents = image
        layer.contentsGravity = .resize
        layer.contentsScale = contentsScale
        return layer
    }
}
