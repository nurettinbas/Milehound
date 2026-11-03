import SwiftUI
import UIKit

/// LinkedIn-style framing controls shown under the editor hero (no separate screen).
struct VehiclePhotoInlineFraming: View {
    @Binding var workingImage: UIImage
    @Binding var userScale: CGFloat
    @Binding var offset: CGSize
    let cropSide: CGFloat
    var onApply: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minZoom = VehiclePhotoCropMath.minUserScale
    private let maxZoom = VehiclePhotoCropMath.maxUserScale
    private let toolStripHeight: CGFloat = 38
    private let zoomThumbSize: CGFloat = 15
    private let zoomTrackHeight: CGFloat = 3.5

    var body: some View {
        VStack(spacing: 10) {
            orientationRow
            zoomRow
            actionRow
        }
        .padding(.top, 2)
        .transition(reduceMotion ? .opacity : MilehoundMotion.softRiseTransition)
    }

    private var orientationRow: some View {
        HStack(spacing: 0) {
            orientButton("rotate.left", L10n.pairingTabVehiclePhotoRotateLeft) {
                applyOrientation(.rotateLeft)
            }
            orientDivider
            orientButton("rotate.right", L10n.pairingTabVehiclePhotoRotateRight) {
                applyOrientation(.rotateRight)
            }
            orientDivider
            orientButton(
                "arrow.left.and.right.righttriangle.left.righttriangle.right",
                L10n.pairingTabVehiclePhotoFlipHorizontal
            ) {
                applyOrientation(.flipHorizontal)
            }
            orientDivider
            orientButton(
                "arrow.up.and.down.righttriangle.up.righttriangle.down",
                L10n.pairingTabVehiclePhotoFlipVertical
            ) {
                applyOrientation(.flipVertical)
            }
        }
        .frame(height: toolStripHeight)
        .glassChrome(cornerRadius: GlassTokens.chipRadius)
    }

    private var orientDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    private func orientButton(
        _ systemImage: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .accessibilityLabel(label)
    }

    private var zoomRow: some View {
        HStack(spacing: 10) {
            zoomChip(
                systemImage: "minus.magnifyingglass",
                disabled: userScale <= minZoom + 0.001
            ) {
                nudgeZoom(-0.12)
            }

            framingZoomTrack

            zoomChip(
                systemImage: "plus.magnifyingglass",
                disabled: userScale >= maxZoom - 0.001
            ) {
                nudgeZoom(0.12)
            }
        }
    }

    private func zoomChip(
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(disabled ? 0.35 : 0.75))
                .frame(width: 32, height: 32)
                .glassChrome(cornerRadius: 16)
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .disabled(disabled)
        .accessibilityHidden(true)
    }

    private var framingZoomTrack: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let usable = max(width - zoomThumbSize, 1)
            let progress = zoomProgress
            let thumbCenterX = zoomThumbSize / 2 + progress * usable

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: zoomTrackHeight)
                    .padding(.horizontal, zoomThumbSize / 2)

                Capsule(style: .continuous)
                    .fill(shellPalette.tintColor(for: colorScheme))
                    .frame(
                        width: max(thumbCenterX - zoomThumbSize / 2, zoomTrackHeight),
                        height: zoomTrackHeight
                    )
                    .padding(.leading, zoomThumbSize / 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: zoomThumbSize, height: zoomThumbSize)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: thumbCenterX - zoomThumbSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max((value.location.x - zoomThumbSize / 2) / usable, 0), 1)
                        setZoom(zoomValue(for: ratio), haptic: true)
                    }
            )
        }
        .frame(height: 32)
        .accessibilityLabel(L10n.pairingTabVehiclePhotoZoom)
        .accessibilityValue(Text("\(Int((zoomProgress * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudgeZoom(0.12)
            case .decrement: nudgeZoom(-0.12)
            @unknown default: break
            }
        }
    }

    private var zoomProgress: CGFloat {
        let span = maxZoom - minZoom
        guard span > 0 else { return 0 }
        return (userScale - minZoom) / span
    }

    private func zoomValue(for progress: CGFloat) -> CGFloat {
        minZoom + progress * (maxZoom - minZoom)
    }

    private var actionRow: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text(L10n.cancel)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .glassPrimaryInk()
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(VehiclePhotoPressStyle())

                Button(action: onApply) {
                    Text(L10n.pairingTabVehiclePhotoApply)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(shellPalette.tintColor(for: colorScheme))
                        )
                }
                .buttonStyle(VehiclePhotoPressStyle())
            }
            .frame(width: geometry.size.width * 0.7)
            .frame(width: geometry.size.width, alignment: .center)
        }
        .frame(height: 32)
        .padding(.bottom, 14)
    }

    private func applyOrientation(_ edit: VehiclePhotoCropMath.OrientationEdit) {
        MilehoundHaptics.selection()
        let next = VehiclePhotoCropMath.applying(edit, to: workingImage)
        if reduceMotion {
            workingImage = next
            offset = .zero
        } else {
            withAnimation(MilehoundMotion.photoSettle) {
                workingImage = next
                offset = .zero
            }
        }
    }

    private func nudgeZoom(_ delta: CGFloat) {
        MilehoundHaptics.selection()
        setZoom(userScale + delta, haptic: false)
    }

    private func setZoom(_ value: CGFloat, haptic: Bool) {
        let clamped = min(max(value, minZoom), maxZoom)
        if haptic {
            let stepped = (clamped * 10).rounded() / 10
            let previous = (userScale * 10).rounded() / 10
            if stepped != previous {
                MilehoundHaptics.selection()
            }
        }
        userScale = clamped
        let draw = VehiclePhotoCropMath.drawSize(
            imageSize: workingImage.size,
            cropSide: cropSide,
            userScale: userScale
        )
        offset = VehiclePhotoCropMath.clampedOffset(offset, drawSize: draw, cropSide: cropSide)
    }
}

/// Pan + pinch for the editor hero while framing.
struct VehiclePhotoFramingGestures: ViewModifier {
    let imageSize: CGSize
    let cropSide: CGFloat
    @Binding var userScale: CGFloat
    @Binding var offset: CGSize
    @State private var dragStart: CGSize = .zero
    @State private var pinchBase: CGFloat = VehiclePhotoCropMath.defaultUserScale

    func body(content: Content) -> some View {
        content.gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        let draw = VehiclePhotoCropMath.drawSize(
                            imageSize: imageSize,
                            cropSide: cropSide,
                            userScale: userScale
                        )
                        let proposed = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                        offset = VehiclePhotoCropMath.clampedOffset(
                            proposed,
                            drawSize: draw,
                            cropSide: cropSide
                        )
                    }
                    .onEnded { _ in
                        dragStart = offset
                    },
                MagnificationGesture()
                    .onChanged { magnification in
                        let next = min(
                            max(pinchBase * magnification, VehiclePhotoCropMath.minUserScale),
                            VehiclePhotoCropMath.maxUserScale
                        )
                        userScale = next
                        let draw = VehiclePhotoCropMath.drawSize(
                            imageSize: imageSize,
                            cropSide: cropSide,
                            userScale: userScale
                        )
                        offset = VehiclePhotoCropMath.clampedOffset(
                            offset,
                            drawSize: draw,
                            cropSide: cropSide
                        )
                    }
                    .onEnded { _ in
                        pinchBase = userScale
                        dragStart = offset
                    }
            )
        )
        .onChange(of: userScale) { _, newValue in
            pinchBase = newValue
        }
    }
}

struct VehiclePhotoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(MilehoundMotion.snappy, value: configuration.isPressed)
    }
}

/// Corner v-badge chip used on empty add + filled tap-hint intros.
struct VehiclePhotoCornerChip: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(shellPalette.glassReadabilityTint(for: colorScheme))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(shellPalette.tintColor(for: colorScheme), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .allowsHitTesting(false)
    }
}

/// Empty-state add photo control — matches filled hero square + corner badge intro.
struct EmptyVehiclePhotoAddButton: View {
    let title: String
    var side: CGFloat = 132
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounceOffset: CGFloat = 0
    @State private var showBadge = true
    @State private var badgeOpacity: Double = 1
    @State private var didPlayIntro = false

    private let bounceAmplitude: CGFloat = 8
    private let bounceDuration: TimeInterval = 0.64
    private let bounceStep: Duration = .milliseconds(640)
    private let badgeFadeDuration: TimeInterval = 0.7

    /// Square top-trailing corner badge (further right than the old circle orb).
    private let badgeOffsetX: CGFloat = 18
    private let badgeOffsetY: CGFloat = -10
    /// Layout room above/beside the square so bounce + chip are not clipped by the list row.
    private let badgeTopClearance: CGFloat = 22
    private let badgeTrailingClearance: CGFloat = 22

    private var cornerRadius: CGFloat { side * 0.18 }

    private var containerHeight: CGFloat {
        side + badgeTopClearance + bounceAmplitude
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                ZStack(alignment: .topTrailing) {
                    photoFrame

                    if showBadge {
                        VehiclePhotoCornerChip(title: title)
                            .opacity(badgeOpacity)
                            .offset(x: badgeOffsetX, y: badgeOffsetY)
                    }
                }
                .frame(width: side, height: side, alignment: .topTrailing)
                .offset(y: badgeTopClearance + bounceAmplitude + bounceOffset)
            }
            // Symmetric horizontal room so the 132pt square stays centered while the chip peeks out.
            .frame(
                width: side + badgeTrailingClearance * 2,
                height: containerHeight,
                alignment: .top
            )
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .onAppear(perform: playIntroIfNeeded)
    }

    private func playIntroIfNeeded() {
        guard !didPlayIntro else { return }
        didPlayIntro = true

        if reduceMotion {
            showBadge = false
            return
        }

        Task { @MainActor in
            for _ in 0 ..< 2 {
                withAnimation(.easeInOut(duration: bounceDuration)) {
                    bounceOffset = -bounceAmplitude
                }
                try? await Task.sleep(for: bounceStep)
                withAnimation(.easeInOut(duration: bounceDuration)) {
                    bounceOffset = 0
                }
                try? await Task.sleep(for: bounceStep)
            }

            withAnimation(.easeOut(duration: badgeFadeDuration)) {
                badgeOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(Int(badgeFadeDuration * 1000)))
            showBadge = false
        }
    }

    private var photoFrame: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 30, weight: .semibold))
            .glassAccentForeground()
            .frame(width: side, height: side)
            .background {
                GlassSurface(
                    cornerRadius: cornerRadius,
                    density: .panel,
                    allowsNative: false
                )
            }
    }
}

/// Renders the framing preview inside a square hero.
struct VehiclePhotoFramingCanvas: View {
    let image: UIImage
    let userScale: CGFloat
    let offset: CGSize
    let side: CGFloat
    var showsCheckerboard: Bool = false
    var showsCropChrome: Bool = true
    var showsExtendedPreview: Bool = true

    private var cornerRadius: CGFloat { side * 0.18 }

    private var drawSize: CGSize {
        VehiclePhotoCropMath.drawSize(
            imageSize: image.size,
            cropSide: side,
            userScale: userScale
        )
    }

    /// Extra space around the crop window so zoomed-in overflow stays visible (dimmed).
    private var overflowPadding: CGFloat {
        guard showsExtendedPreview else { return 0 }
        let extraW = max(0, (drawSize.width - side) / 2)
        let extraH = max(0, (drawSize.height - side) / 2)
        return min(max(extraW, extraH), 52)
    }

    private var containerSide: CGFloat { side + overflowPadding * 2 }

    private var showsLetterbox: Bool {
        drawSize.width < side - 0.5 || drawSize.height < side - 0.5
    }

    var body: some View {
        ZStack {
            if overflowPadding > 0 {
                imageLayer
                    .opacity(0.34)
                    .allowsHitTesting(false)
            }

            cropWindowContent

            if showsCropChrome {
                VehiclePhotoCropFrameOverlay(cornerRadius: cornerRadius)
                    .frame(width: side, height: side)
            }
        }
        .frame(width: containerSide, height: containerSide)
        .animation(MilehoundMotion.snappy, value: userScale)
        .animation(MilehoundMotion.snappy, value: offset)
    }

    private var cropWindowContent: some View {
        ZStack {
            letterboxBackground

            imageLayer
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var letterboxBackground: some View {
        if showsCheckerboard && VehiclePhotoStore.imageHasAlpha(image) {
            CheckerboardBackground()
        } else if showsLetterbox {
            Color.primary.opacity(0.08)
        }
    }

    private var imageLayer: some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: drawSize.width, height: drawSize.height)
            .offset(offset)
    }
}

/// Visible crop boundary while framing — shows exactly what will be saved.
private struct VehiclePhotoCropFrameOverlay: View {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.38), lineWidth: 3)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(shellPalette.tintColor(for: colorScheme).opacity(0.55), lineWidth: 1)
                .padding(2)
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .allowsHitTesting(false)
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let dark = (row + col) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell, height: cell)),
                        with: .color(dark ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.06))
                    )
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}
