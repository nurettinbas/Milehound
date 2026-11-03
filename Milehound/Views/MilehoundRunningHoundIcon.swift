import SwiftUI
import UIKit

/// Compact running-hound mark for the trip-list Start control.
/// Legs use the same `LaunchIntroHoundRig` Core Animation stride as the cold-launch
/// intro. Speed streaks stay on a display-link clock so List / theme transactions
/// cannot hijack mid-flight offsets (the classic “streak jump” on appearance change).
struct MilehoundRunningHoundIcon: View {
    var size: CGFloat = 30
    var reduceMotion: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    private var shouldAnimate: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var accent: Color { shellPalette.tintColor(for: colorScheme) }
    private var accentUIColor: UIColor {
        let rgb = shellPalette.atmosphere(for: colorScheme).tint
        return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
    /// Hound + speed streaks sit at 80% so the gallop lift clears the glass capsule edge.
    private let markScale: CGFloat = 0.968
    /// One seamless lane-width scroll — original default speed.
    private let streakPeriod: TimeInterval = 0.48

    @State private var clockDate = Date()

    var body: some View {
        mark(streakPhase: streakPhase(at: clockDate))
        .overlay(alignment: .topLeading) {
            MilehoundDisplayLinkTicker(
                isRunning: shouldAnimate,
                framesPerSecond: ProcessInfo.processInfo.isLowPowerModeEnabled ? 10 : 20
            ) { clockDate = Date(timeIntervalSinceReferenceDate: $0) }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(minWidth: size)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func mark(streakPhase: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Room above for gallop lift so the layout box doesn't grow/shrink.
                Color.clear.frame(height: size * 0.62)

                VStack(spacing: 1) {
                    MilehoundRunningHoundMark(
                        width: size * 0.92,
                        height: size * 0.48,
                        tint: accentUIColor,
                        animate: shouldAnimate
                    )
                    .frame(width: size * 0.92, height: size * 0.48)

                    speedStreaks(phase: streakPhase)
                }
                .scaleEffect(markScale, anchor: .bottom)
            }
            .frame(width: size, height: size * 0.62)

            Text(L10n.string("action.start"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.top, 1)
        }
    }

    /// Single dash under the hound; duplicated and scrolled for a seamless drift.
    private func speedStreaks(phase: CGFloat) -> some View {
        let laneWidth = size * 0.78
        return ZStack {
            streakDash
                .offset(x: shouldAnimate ? -phase * laneWidth : 0)
            streakDash
                .offset(x: shouldAnimate ? (1 - phase) * laneWidth : laneWidth)
        }
        .frame(width: laneWidth, height: 2, alignment: .leading)
        .clipped()
        .opacity(shouldAnimate ? 0.9 : 0.35)
        .mask {
            LinearGradient(
                colors: [.clear, .black.opacity(0.85), .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var streakDash: some View {
        Capsule(style: .continuous)
            .fill(accent.opacity(0.42))
            .frame(width: size * 0.42, height: 1.35)
            .frame(width: size * 0.78, alignment: .leading)
    }

    private func streakPhase(at date: Date) -> CGFloat {
        guard shouldAnimate else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        return CGFloat(t.truncatingRemainder(dividingBy: streakPeriod) / streakPeriod)
    }
}

/// In-place gallop for the Start glyph. Core Animation owns the bones so a 20 fps
/// streak tick cannot restart the stride.
struct MilehoundRunningHoundMark: UIViewRepresentable {
    var width: CGFloat
    var height: CGFloat
    var tint: UIColor
    var animate: Bool

    func makeUIView(context: Context) -> MilehoundRunningHoundMarkView {
        let view = MilehoundRunningHoundMarkView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: MilehoundRunningHoundMarkView, context: Context) {
        uiView.apply(
            size: CGSize(width: width, height: height),
            tint: tint,
            animate: animate,
            contentsScale: context.environment.displayScale
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MilehoundRunningHoundMarkView, context: Context) -> CGSize {
        CGSize(width: width, height: height)
    }
}

final class MilehoundRunningHoundMarkView: UIView {
    /// Leaves room for a stride’s swing inside the same Start box.
    private let fit: CGFloat = 0.88

    private var parts = LaunchIntroHoundParts.load()
    private var mounted: LaunchIntroHoundLayerTree.Mounted?
    private var flatLayer: CALayer?
    private var lastSize: CGSize = .zero
    private var lastTint: UIColor?
    private var lastScale: CGFloat = 0
    private var looping = false

    override var intrinsicContentSize: CGSize { lastSize == .zero ? CGSize(width: 28, height: 14) : lastSize }

    func apply(size: CGSize, tint: UIColor, animate: Bool, contentsScale: CGFloat) {
        let sizeChanged = lastSize != size || lastScale != contentsScale
        lastSize = size
        lastScale = contentsScale
        invalidateIntrinsicContentSize()
        if sizeChanged {
            rebuild(tint: tint, contentsScale: contentsScale)
        } else if !sameColor(tint, lastTint) {
            lastTint = tint
            if let mounted, let parts {
                LaunchIntroHoundLayerTree.applyTint(tint, to: mounted, parts: parts)
            } else {
                flatLayer?.contents = tintedFlat(tint)?.cgImage
            }
        }
        syncMotion(animate)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if mounted == nil, flatLayer == nil, lastSize.width > 1 {
            rebuild(tint: lastTint ?? tintColor ?? .white, contentsScale: max(lastScale, window?.screen.scale ?? contentScaleFactor))
        }
    }

    private func rebuild(tint: UIColor, contentsScale: CGFloat) {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        mounted = nil
        flatLayer = nil
        looping = false
        lastTint = tint
        let box = CGRect(origin: .zero, size: lastSize)
        if let parts {
            mounted = LaunchIntroHoundLayerTree.add(
                parts: parts,
                in: box,
                on: layer,
                contentsScale: contentsScale,
                tint: tint,
                fit: fit
            )
        } else if let image = tintedFlat(tint) {
            let mark = CALayer()
            mark.frame = box
            mark.contents = image.cgImage
            mark.contentsGravity = .resizeAspect
            mark.contentsScale = contentsScale
            layer.addSublayer(mark)
            flatLayer = mark
        }
    }

    private func syncMotion(_ animate: Bool) {
        guard let mounted else { return }
        if animate {
            guard !looping else { return }
            LaunchIntroHoundLayerTree.attachStrideLoop(to: mounted)
            looping = true
        } else if looping {
            LaunchIntroHoundLayerTree.removeStrideLoop(from: mounted)
            looping = false
        }
    }

    private func tintedFlat(_ tint: UIColor) -> UIImage? {
        UIImage(named: "MilehoundHound")?.withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    private func sameColor(_ a: UIColor, _ b: UIColor?) -> Bool {
        guard let b else { return false }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) < 0.002 && abs(ag - bg) < 0.002 && abs(ab - bb) < 0.002 && abs(aa - ba) < 0.002
    }
}

#Preview {
    HStack(spacing: 24) {
        MilehoundRunningHoundIcon(reduceMotion: true)
        MilehoundRunningHoundIcon(reduceMotion: false)
    }
    .padding()
}
