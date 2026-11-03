import os
import SwiftUI
import UIKit

/// The real app icon, enlarged to the screen, then eased back down to icon size.
/// Core Animation only, so the first SwiftData fetch cannot hitch a frame.
struct LaunchIntroSceneView: UIViewRepresentable {
    var timeline: LaunchIntroTimeline
    /// System launch screen color. The first frame matches it.
    var launch: UIColor
    var plate: UIColor
    var logo: UIImage?
    var hound: UIImage?
    var houndParts: LaunchIntroHoundParts?
    var skipped: Bool
    var onReveal: () -> Void
    var onStarted: () -> Void
    var onLanded: () -> Void
    var onFinished: () -> Void

    func makeUIView(context: Context) -> LaunchIntroSceneUIView {
        let view = LaunchIntroSceneUIView()
        view.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        view.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        view.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
        view.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: LaunchIntroSceneUIView, context: Context) {
        uiView.onReveal = onReveal
        uiView.onStarted = onStarted
        uiView.onLanded = onLanded
        uiView.onFinished = onFinished
        uiView.apply(LaunchIntroSceneUIView.Snapshot(
            timeline: timeline,
            launch: launch,
            plate: plate,
            logo: logo,
            hound: hound,
            houndParts: houndParts,
            skipped: skipped
        ))
    }
}

final class LaunchIntroSceneUIView: UIView {
    struct Snapshot {
        var timeline: LaunchIntroTimeline
        var launch: UIColor
        var plate: UIColor
        var logo: UIImage?
        var hound: UIImage?
        var houndParts: LaunchIntroHoundParts?
        var skipped: Bool
    }

    var onReveal: (() -> Void)?
    var onStarted: (() -> Void)?
    var onLanded: (() -> Void)?
    var onFinished: (() -> Void)?

    private let content = CALayer()
    private let clockLayer = CALayer()
    private var pending: Snapshot?
    private var finishWork: DispatchWorkItem?
    private var flushScheduled = false
    private var startedAt: CFTimeInterval = 0
    private var token = ""
    private var didSkip = false
    private var didSignalReveal = false
    private var didFinish = false
    private var didSignalStart = false
    private var signpost: OSSignpostIntervalState?
    private let finishRelay = LaunchIntroFinishRelay()
    private var timeline = LaunchIntroTimeline.standard

    /// Shared curves. Enter decelerates, the close is a long in-out, the exit accelerates away.
    private let enterCurve = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    private let closeCurve = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
    private let exitCurve = CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
    /// Starts at the speed of a linear run and coasts to rest, so nothing freezes when the close begins.
    private let coastCurve = CAMediaTimingFunction(controlPoints: 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1)
    private let linear = CAMediaTimingFunction(name: .linear)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        content.frame = bounds
        content.allowsGroupOpacity = false
        clockLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        clockLayer.opacity = 0
        content.addSublayer(clockLayer)
        layer.addSublayer(content)
        finishRelay.onFinish = { [weak self] in
            self?.finish()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
        flushPending()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        flushPending()
    }

    func apply(_ snapshot: Snapshot) {
        pending = snapshot
        if token.isEmpty, !didSkip {
            backgroundColor = launchColor(snapshot.launch)
        }
        if window != nil, bounds.width > 1, bounds.height > 1 {
            startIfReady()
        }
    }

    /// `updateUIView` often runs before the view has a window or a real size.
    /// Starting Core Animation then schedules the clock in the wrong time base, so the cover never dismisses.
    private func flushPending() {
        guard pending != nil, window != nil, bounds.width > 1, bounds.height > 1, !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.startIfReady()
        }
    }

    private func startIfReady() {
        guard let pending, window != nil, bounds.width > 1, bounds.height > 1 else { return }
        if startedAt == 0 {
            startedAt = content.convertTime(CACurrentMediaTime(), from: nil)
            signpost = PerformanceSignposts.signposter.beginInterval("launch.intro")
        }
        if pending.skipped {
            guard !didSkip else { return }
            didSkip = true
            playSkip()
            return
        }
        let next = "\(Int(bounds.width))x\(Int(bounds.height))|\(pending.timeline.total)|\(pending.timeline.allowsMotion)"
        guard next != token else { return }
        token = next
        timeline = pending.timeline
        rebuild(pending)
    }

    private func rebuild(_ snapshot: Snapshot) {
        content.sublayers?.forEach { layer in
            if layer !== clockLayer {
                layer.removeFromSuperlayer()
            }
        }
        let launch = launchColor(snapshot.launch)
        if timeline.allowsMotion {
            addMovingMark(snapshot, launch: launch)
        } else {
            addStillLogo(snapshot.logo, launch: launch)
        }
        addClock()
        backgroundColor = .clear
        CATransaction.flush()
        signalStart()
    }

    /// Commit first, then let the app build underneath. The intro keeps running on the render server.
    private func signalStart() {
        guard !didSignalStart else { return }
        didSignalStart = true
        DispatchQueue.main.async { [weak self] in
            self?.onStarted?()
        }
    }

    /// The launch screen is drawn in the system appearance, not the app’s override.
    private func launchColor(_ color: UIColor) -> UIColor {
        let system = window?.windowScene?.screen.traitCollection ?? traitCollection
        return color.resolvedColor(with: system)
    }

    private var middle: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private var iconSide: CGFloat {
        min(168, min(bounds.width, bounds.height) * 0.42)
    }

    /// The app icon, enlarged until it meets the shorter side of the window, and centered.
    private var boardSide: CGFloat {
        min(bounds.width, bounds.height)
    }

    private var handoff: CFTimeInterval {
        timeline.runEnd + (timeline.closeEnd - timeline.runEnd) * 0.55
    }

    /// Launch color becomes the theme plate; road, hound, and stopwatch settle in large and move.
    /// Then the plate closes from the corners into the real icon, which leaves with a short push.
    private func addMovingMark(_ snapshot: Snapshot, launch: UIColor) {
        let total = max(timeline.total, 0.01)
        let enter = timeline.enterEnd / total
        let run = timeline.runEnd / total
        let close = timeline.closeEnd / total
        let hand = handoff / total
        let side = boardSide

        let plate = CALayer()
        plate.cornerCurve = .continuous
        plate.position = middle
        plate.backgroundColor = snapshot.plate.cgColor
        let full = CGRect(x: 0, y: 0, width: bounds.width + 4, height: bounds.height + 4)
        let icon = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
        plate.bounds = icon
        plate.cornerRadius = iconSide * 0.2237
        content.addSublayer(plate)
        keyframes(plate, "backgroundColor", [launch.cgColor, snapshot.plate.cgColor, snapshot.plate.cgColor], [0, enter, 1], [enterCurve, linear])
        keyframes(
            plate,
            "bounds",
            [full, full, icon, icon].map { NSValue(cgRect: $0) },
            [0, run, close, 1],
            [linear, closeCurve, linear]
        )
        let startRadius = side * 0.06
        keyframes(plate, "cornerRadius", [startRadius, startRadius, iconSide * 0.2237, iconSide * 0.2237], [0, run, close, 1], [linear, closeCurve, linear])

        let picture = CALayer()
        picture.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        picture.position = middle
        picture.allowsGroupOpacity = false
        content.addSublayer(picture)
        addLogoRoad(on: picture, side: side, dash: snapshot.plate)
        addRunningHound(snapshot.hound, parts: snapshot.houndParts, on: picture, side: side)
        addStopwatch(on: picture, side: side)
        let end = iconSide / side
        picture.transform = CATransform3DMakeScale(end, end, 1)
        keyframes(picture, "transform.scale", [1.06, 1, 1, end, end], [0, enter, run, close, 1], [enterCurve, linear, closeCurve, linear])
        // Each mark fades on its own; the hound fades as one so its overlapping parts do not show.
        for mark in picture.sublayers ?? [] {
            mark.opacity = 0
            keyframes(mark, "opacity", [0, 1, 1, 0, 0], [0, enter * 0.8, hand, close, 1], [enterCurve, linear, linear, linear])
        }

        let logo = logoLayer(snapshot.logo)
        content.addSublayer(logo)
        keyframes(logo, "opacity", [0, 0, 1, 1], [0, hand, close, 1], [linear, closeCurve, linear])

        content.opacity = 0
        keyframes(content, "opacity", [1, 1, 0], [0, close, 1], [linear, exitCurve])
        keyframes(content, "transform.scale", [1, 1, 1.06], [0, close, 1], [linear, exitCurve])

        after(timeline.runEnd) { $0.signalReveal() }
        after(timeline.closeEnd) { view in
            guard !view.didSkip else { return }
            view.onLanded?()
        }
    }

    /// Reduce Motion: the icon on the launch color, then a short fade.
    private func addStillLogo(_ image: UIImage?, launch: UIColor) {
        let ground = CALayer()
        ground.frame = bounds
        ground.backgroundColor = launch.cgColor
        content.addSublayer(ground)
        content.addSublayer(logoLayer(image))
        content.opacity = 0
        keyframes(content, "opacity", [1, 0], [0, 1], [exitCurve])
        signalReveal()
    }

    private func logoLayer(_ image: UIImage?) -> CALayer {
        let logo = CALayer()
        logo.bounds = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
        logo.position = middle
        logo.contents = image?.cgImage
        logo.contentsGravity = .resizeAspect
        logo.contentsScale = traitCollection.displayScale
        logo.cornerCurve = .continuous
        logo.cornerRadius = iconSide * 0.2237
        logo.masksToBounds = true
        return logo
    }

    /// Left and right edges traced from the app icon, so the bend matches the logo.
    private func addLogoRoad(on picture: CALayer, side: CGFloat, dash: UIColor) {
        let edges: [(CGFloat, CGFloat, CGFloat)] = [
            (0.188, 0.998, 0.789),
            (0.197, 0.963, 0.764),
            (0.242, 0.928, 0.746),
            (0.279, 0.893, 0.732),
            (0.297, 0.857, 0.727),
            (0.305, 0.822, 0.725),
            (0.305, 0.787, 0.730),
            (0.295, 0.752, 0.740),
            (0.275, 0.717, 0.756),
            (0.283, 0.682, 0.779),
            (0.320, 0.646, 0.807),
            (0.367, 0.611, 0.840),
            (0.424, 0.576, 0.873),
            (0.498, 0.541, 0.904),
            (0.586, 0.506, 0.932),
            (0.686, 0.471, 0.949),
            (0.775, 0.436, 0.959),
            (0.838, 0.400, 0.953),
            (0.848, 0.365, 0.926),
            (0.773, 0.330, 0.848),
            (0.717, 0.320, 0.787)
        ]
        let left = edges.map { CGPoint(x: $0.0 * side, y: $0.1 * side) }
        let right = edges.map { CGPoint(x: $0.2 * side, y: $0.1 * side) }
        let dashEdges = edges.prefix { $0.2 - $0.0 >= 0.16 }
        let centers = dashEdges.map { CGPoint(x: ($0.0 + $0.2) / 2 * side, y: $0.1 * side) }
        let road = CAShapeLayer()
        road.frame = picture.bounds
        road.path = ribbonPath(upper: left, lower: right)
        road.fillColor = UIColor.white.cgColor
        picture.addSublayer(road)

        let marks = CAShapeLayer()
        marks.frame = picture.bounds
        marks.path = smoothPath(centers)
        marks.fillColor = nil
        marks.strokeColor = dash.cgColor
        marks.lineCap = .round
        marks.lineJoin = .round
        marks.lineWidth = max(4, side * 0.034) * 0.75
        let dashLength = marks.lineWidth * 2.4
        let gap = marks.lineWidth * 1.7
        marks.lineDashPattern = [NSNumber(value: dashLength), NSNumber(value: gap)]
        picture.addSublayer(marks)
        let speed = (dashLength + gap) * 5
        coast(marks, "lineDashPhase", from: 0, speed: -speed, startAt: 0)
    }

    /// The icon’s hound, in the icon’s place, galloping without traveling. Legs bend at the knee and hock,
    /// the back flexes, the body pitches and lifts, and everything dies out on the logo pose as the plate closes.
    private func addRunningHound(_ image: UIImage?, parts: LaunchIntroHoundParts?, on picture: CALayer, side: CGFloat) {
        let dog = CGRect(x: side * 0.145, y: side * 0.105, width: side * 0.681, height: side * 0.365)
        guard let parts else {
            addFlatHound(image, in: dog, on: picture)
            return
        }
        let mounted = LaunchIntroHoundLayerTree.add(
            parts: parts,
            in: dog,
            on: picture,
            contentsScale: traitCollection.displayScale
        )
        mounted.root.add(
            gait("transform.translation.y", rig: mounted.rig, curve: mounted.rig.bob, unit: mounted.art.height),
            forKey: "bob"
        )
        for joint in mounted.joints {
            joint.layer.add(
                gait("transform.rotation.z", rig: mounted.rig, curve: joint.swing),
                forKey: "swing"
            )
        }
    }

    /// Single-image hound for when the rig parts are missing: squash and bob in place.
    private func addFlatHound(_ image: UIImage?, in dog: CGRect, on picture: CALayer) {
        guard let image else { return }
        let root = CALayer()
        root.frame = dog
        let mark = CALayer()
        mark.frame = root.bounds
        mark.contents = image.cgImage
        mark.contentsGravity = .resizeAspect
        mark.contentsScale = traitCollection.displayScale
        root.addSublayer(mark)
        picture.addSublayer(root)
        let cycle: CFTimeInterval = 0.36
        func loop(_ layer: CALayer, _ keyPath: String, _ values: [CGFloat]) {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = (0..<values.count).map { ns(Double($0) / Double(values.count - 1)) }
            animation.calculationMode = .cubic
            animation.repeatDuration = timeline.closeEnd
            stamp(animation, begin: 0, duration: cycle)
            layer.add(animation, forKey: keyPath)
        }
        loop(mark, "transform.scale.x", [1, 1.045, 1, 0.985, 1])
        loop(mark, "transform.scale.y", [1, 0.94, 1, 1.035, 1])
        loop(root, "transform.translation.x", [0, dog.width * 0.012, 0, -dog.width * 0.008, 0])
        loop(root, "transform.translation.y", [0, -dog.height * 0.02, 0, dog.height * 0.012, 0])
    }

    /// Logo stopwatch, lower-left. The crown is pressed, the hands start, and the watch rocks from the crown
    /// like one held in the hand. Everything coasts to rest on the logo’s own pose as the plate closes.
    private func addStopwatch(on picture: CALayer, side: CGFloat) {
        let face = CGPoint(x: side * 0.1639, y: side * 0.8089)
        let box = side * 0.40
        let local = CGPoint(x: box / 2, y: box / 2)
        let crownTop = local.y - side * 0.180
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        root.anchorPoint = CGPoint(x: 0.5, y: crownTop / box)
        root.position = CGPoint(x: face.x, y: face.y - side * 0.180)
        picture.addSublayer(root)

        let body = CGMutablePath()
        let ring = CGPath(
            ellipseIn: CGRect(x: local.x - side * 0.121, y: local.y - side * 0.121, width: side * 0.242, height: side * 0.242),
            transform: nil
        )
        body.addPath(ring.copy(strokingWithWidth: side * 0.023, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
        let ticks = CGMutablePath()
        for direction in [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)] {
            ticks.move(to: CGPoint(x: local.x + direction.x * side * 0.074, y: local.y + direction.y * side * 0.074))
            ticks.addLine(to: CGPoint(x: local.x + direction.x * side * 0.098, y: local.y + direction.y * side * 0.098))
        }
        body.addPath(ticks.copy(strokingWithWidth: side * 0.012, lineCap: .round, lineJoin: .round, miterLimit: 10))
        body.addPath(CGPath(
            roundedRect: CGRect(x: local.x - side * 0.016, y: local.y - side * 0.156, width: side * 0.032, height: side * 0.040),
            cornerWidth: side * 0.004,
            cornerHeight: side * 0.004,
            transform: nil
        ))
        let shape = CAShapeLayer()
        shape.frame = root.bounds
        shape.path = body
        shape.fillColor = UIColor.white.cgColor
        root.addSublayer(shape)

        let crown = CAShapeLayer()
        crown.frame = root.bounds
        crown.path = CGPath(
            roundedRect: CGRect(x: local.x - side * 0.032, y: crownTop, width: side * 0.064, height: side * 0.028),
            cornerWidth: side * 0.006,
            cornerHeight: side * 0.006,
            transform: nil
        )
        crown.fillColor = UIColor.white.cgColor
        root.addSublayer(crown)
        let press = CAKeyframeAnimation(keyPath: "transform.translation.y")
        press.values = [0, side * 0.009, 0]
        press.keyTimes = [0, 0.35, 1]
        press.timingFunctions = [CAMediaTimingFunction(name: .easeIn), enterCurve]
        stamp(press, begin: max(0, timeline.enterEnd - 0.12), duration: 0.2)
        crown.add(press, forKey: "press")

        let landing = CGFloat.pi / 4
        addWatchHand(on: root, at: local, length: side * 0.092, base: side * 0.016, landing: landing, turnsPerSecond: 1.6)
        addWatchHand(on: root, at: local, length: side * 0.058, base: side * 0.014, landing: landing, turnsPerSecond: 0.42)

        let hub = CAShapeLayer()
        hub.frame = root.bounds
        hub.path = CGPath(
            ellipseIn: CGRect(x: local.x - side * 0.012, y: local.y - side * 0.012, width: side * 0.024, height: side * 0.024),
            transform: nil
        )
        hub.fillColor = UIColor.white.cgColor
        root.addSublayer(hub)

        root.add(rock(tilt: 0.07, halfSwing: 0.17), forKey: "rock")
    }

    /// Alternating swings at full strength through the run, then dying out to rest at the end of the close.
    private func rock(tilt: CGFloat, halfSwing: CFTimeInterval) -> CAKeyframeAnimation {
        let length = max(timeline.closeEnd, 0.01)
        let run = timeline.runEnd
        let closing = max(timeline.closeEnd - run, 0.01)
        let accent: [CGFloat] = [1, 0.78, 0.92, 0.7]
        var times: [NSNumber] = [0]
        var values: [CGFloat] = [0]
        var time = halfSwing * 0.5
        var sign: CGFloat = 1
        var index = 0
        while time < length - halfSwing * 0.5 {
            let fade = time <= run ? 1 : pow(max(0, 1 - (time - run) / closing), 2)
            values.append(sign * tilt * accent[index % accent.count] * CGFloat(fade))
            times.append(ns(time / length))
            sign = -sign
            time += halfSwing
            index += 1
        }
        times.append(1)
        values.append(0)
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = values
        animation.keyTimes = times
        animation.calculationMode = .cubic
        stamp(animation, begin: 0, duration: length)
        return animation
    }

    /// Samples a rig curve across the run and close, so the gait dies out on the logo pose at `closeEnd`.
    private func gait(
        _ keyPath: String,
        rig: LaunchIntroHoundRig,
        curve: LaunchIntroHoundRig.Curve,
        unit: CGFloat = 1,
        samplesPerStride: Int = 16
    ) -> CAKeyframeAnimation {
        let animation = LaunchIntroHoundLayerTree.envelopedGait(
            keyPath,
            rig: rig,
            curve: curve,
            timeline: timeline,
            unit: unit,
            samplesPerStride: samplesPerStride
        )
        stamp(animation, begin: 0, duration: max(timeline.closeEnd, 0.01))
        return animation
    }

    /// Needle drawn pointing at 12; positive rotation is clockwise. It starts when the crown is pressed
    /// and lands on `landing` as the plate becomes the icon.
    private func addWatchHand(
        on root: CALayer,
        at center: CGPoint,
        length: CGFloat,
        base: CGFloat,
        landing: CGFloat,
        turnsPerSecond: Double
    ) {
        let hand = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: base * 0.2, y: length))
        path.addLine(to: CGPoint(x: base * 0.5, y: 0))
        path.addLine(to: CGPoint(x: base * 0.8, y: length))
        path.closeSubpath()
        hand.path = path
        hand.fillColor = UIColor.white.cgColor
        hand.bounds = CGRect(x: 0, y: 0, width: base, height: length)
        hand.anchorPoint = CGPoint(x: 0.5, y: 1)
        hand.position = center
        hand.transform = CATransform3DMakeRotation(landing, 0, 0, 1)
        root.addSublayer(hand)
        let speed = CGFloat(turnsPerSecond * 2 * .pi)
        let running = CGFloat(max(0, timeline.runEnd - timeline.enterEnd))
        let closing = CGFloat(max(0, timeline.closeEnd - timeline.runEnd))
        let travel = speed * running + speed * closing / 2
        coast(hand, "transform.rotation.z", from: landing - travel, speed: speed, startAt: timeline.enterEnd)
    }

    /// Holds `from`, moves at `speed` per second from `startAt` until the run ends,
    /// then coasts to rest as the close ends with no jump in speed.
    private func coast(_ layer: CALayer, _ keyPath: String, from: CGFloat, speed: CGFloat, startAt: CFTimeInterval) {
        let length = max(timeline.closeEnd, 0.01)
        let runMoving = CGFloat(max(0, timeline.runEnd - startAt))
        let closing = CGFloat(max(0, timeline.closeEnd - timeline.runEnd))
        let atRunEnd = from + speed * runMoving
        let atRest = atRunEnd + speed * closing / 2
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = [from, from, atRunEnd, atRest]
        animation.keyTimes = [0, ns(startAt / length), ns(timeline.runEnd / length), 1]
        animation.timingFunctions = [linear, linear, coastCurve]
        stamp(animation, begin: 0, duration: length)
        layer.add(animation, forKey: keyPath)
    }

    private func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        appendSmooth(from: points, to: path)
        return path
    }

    private func ribbonPath(upper: [CGPoint], lower: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let start = upper.first, let tip = lower.last else { return path }
        path.move(to: start)
        appendSmooth(from: upper, to: path)
        path.addLine(to: tip)
        appendSmooth(from: Array(lower.reversed()), to: path)
        path.closeSubpath()
        return path
    }

    private func appendSmooth(from points: [CGPoint], to path: CGMutablePath) {
        guard points.count > 1 else { return }
        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }
        for index in 1..<points.count - 1 {
            let mid = CGPoint(
                x: (points[index].x + points[index + 1].x) / 2,
                y: (points[index].y + points[index + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: points[index])
        }
        path.addQuadCurve(to: points[points.count - 1], control: points[points.count - 2])
    }

    /// Fades out from wherever the intro is. Running animations keep going underneath, so nothing snaps.
    private func playSkip() {
        backgroundColor = .clear
        signalStart()
        let current = content.presentation()?.opacity ?? 1
        content.removeAnimation(forKey: "opacity")
        content.removeAnimation(forKey: "transform.scale")
        content.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = current
        fade.toValue = 0
        fade.timingFunction = exitCurve
        fade.delegate = finishRelay
        stamp(fade, begin: 0, duration: LaunchIntroTimeline.skip.total, fromStart: false)
        content.add(fade, forKey: "skip")
        let push = CABasicAnimation(keyPath: "transform.scale")
        push.fromValue = 1
        push.toValue = 1.04
        push.timingFunction = exitCurve
        stamp(push, begin: 0, duration: LaunchIntroTimeline.skip.total, fromStart: false)
        content.add(push, forKey: "skipPush")
        armFinish(after: LaunchIntroTimeline.skip.total)
        signalReveal()
    }

    private func addClock() {
        let clock = CABasicAnimation(keyPath: "opacity")
        clock.fromValue = 1
        clock.toValue = 1
        clock.delegate = finishRelay
        stamp(clock, begin: 0, duration: timeline.total)
        clockLayer.add(clock, forKey: "clock")
        armFinish(after: timeline.total)
    }

    private func keyframes(
        _ layer: CALayer,
        _ keyPath: String,
        _ values: [Any],
        _ times: [Double],
        _ curves: [CAMediaTimingFunction]
    ) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map(ns)
        animation.timingFunctions = curves
        stamp(animation, begin: 0, duration: max(timeline.total, 0.01))
        layer.add(animation, forKey: keyPath)
    }

    private func after(_ time: CFTimeInterval, _ action: @escaping (LaunchIntroSceneUIView) -> Void) {
        let elapsed = startedAt > 0 ? content.convertTime(CACurrentMediaTime(), from: nil) - startedAt : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, time - elapsed)) { [weak self] in
            guard let self else { return }
            action(self)
        }
    }

    private func stamp(_ animation: CAAnimation, begin: CFTimeInterval, duration: CFTimeInterval, fromStart: Bool = true) {
        let now = content.convertTime(CACurrentMediaTime(), from: nil)
        let origin = fromStart ? startedAt : now
        animation.beginTime = origin + begin
        animation.duration = duration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        applyFrameRate(animation)
    }

    private func armFinish(after delay: CFTimeInterval) {
        finishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finish()
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05, execute: work)
    }

    private func applyFrameRate(_ animation: CAAnimation) {
        let preferred = timeline.preferredFrameRate
        let minimum: Float = preferred >= 100 ? 80 : 30
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: minimum, maximum: preferred, preferred: preferred)
    }

    private func signalReveal() {
        guard !didSignalReveal else { return }
        didSignalReveal = true
        DispatchQueue.main.async { [weak self] in
            self?.onReveal?()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        finishWork?.cancel()
        finishWork = nil
        if let signpost {
            PerformanceSignposts.signposter.endInterval("launch.intro", signpost)
            self.signpost = nil
        }
        onFinished?()
    }

    private func ns(_ value: Double) -> NSNumber {
        NSNumber(value: min(1, max(0, value)))
    }
}

private final class LaunchIntroFinishRelay: NSObject, CAAnimationDelegate {
    var onFinish: (() -> Void)?

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        onFinish?()
    }
}
