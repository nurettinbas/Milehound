import SwiftUI
import UIKit

/// Compact vehicle mark: optional disk thumb with SF Symbol fallback.
/// Transparent PNG areas show the glass/tint behind — never a white plate.
struct VehicleAvatarView: View {
    let systemImage: String
    var photoFileName: String?
    var pendingImage: UIImage?
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 8
    var isElectricAccent: Bool = false
    var showsBrandRing: Bool = false
    /// Brand ring stroke opacity when `showsBrandRing` is on (hero can pulse this once).
    var brandRingOpacity: Double = 0.45
    /// Overrides brand/electric symbol tint (e.g. white on the recording card chip).
    var symbolColor: Color? = nil
    /// When false, skip the tinted plate behind the SF Symbol (photo still uses clear glass).
    var showsSymbolPlate: Bool = true
    /// Keeps wide side-profile glyphs inside `size`; without it they bleed over neighbouring
    /// labels in tight rows (font-sized symbols only constrain height, not width).
    var symbolFitsFrame: Bool = false
    /// One-shot shine when a real photo first appears (list rows).
    var showsPhotoShine: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadedImage: UIImage?
    @State private var photoVisible = false

    private var displayImage: UIImage? {
        pendingImage ?? loadedImage
    }

    private var resolvedSymbolColor: Color {
        if let symbolColor { return symbolColor }
        return isElectricAccent ? .yellow : shellPalette.tintColor(for: colorScheme)
    }

    var body: some View {
        ZStack {
            if showsSymbolPlate {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
                    .frame(width: size, height: size)
            }

            if let displayImage {
                photoImage(displayImage)
            } else {
                symbolMark
            }
        }
        .overlay {
            if showsBrandRing, size > 72 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        shellPalette.tintColor(for: colorScheme).opacity(brandRingOpacity),
                        lineWidth: 1.5
                    )
            }
        }
        .frame(width: size, height: size)
        .task(id: photoIdentity) {
            await loadPhoto()
        }
    }

    @ViewBuilder
    private func photoImage(_ image: UIImage) -> some View {
        let base = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(photoVisible || reduceMotion ? 1 : 0)

        if showsPhotoShine, photoVisible || reduceMotion {
            base.photoIdleShine(cornerRadius: cornerRadius, id: photoIdentity)
        } else {
            base
        }
    }

    @ViewBuilder
    private var symbolMark: some View {
        // Always the fixed default side-car facing travel-right; `systemImage` is ignored.
        let mark = VehicleIconOption.default.rawValue
        if symbolFitsFrame {
            Image(systemName: mark)
                .resizable()
                .scaledToFit()
                .foregroundStyle(resolvedSymbolColor)
                .scaleEffect(x: -1, y: 1)
                .frame(width: size, height: size)
        } else {
            Image(systemName: mark)
                .font(size <= 40 ? .body : .title2)
                .foregroundStyle(resolvedSymbolColor)
                .scaleEffect(x: -1, y: 1)
        }
    }

    private var photoIdentity: String {
        if let pendingImage {
            return "pending-\(ObjectIdentifier(pendingImage))"
        }
        return photoFileName ?? "none"
    }

    private var fillColor: Color {
        if isElectricAccent {
            return Color.yellow.opacity(0.15)
        }
        return shellPalette.tintColor(for: colorScheme).opacity(displayImage != nil ? 0.10 : 0.12)
    }

    private func revealPhoto() {
        if reduceMotion {
            photoVisible = true
        } else {
            withAnimation(MilehoundMotion.gentle) {
                photoVisible = true
            }
        }
    }

    private func loadPhoto() async {
        if pendingImage != nil {
            loadedImage = nil
            revealPhoto()
            return
        }
        guard let photoFileName else {
            loadedImage = nil
            photoVisible = false
            return
        }

        photoVisible = false

        if let cached = VehiclePhotoStore.shared.cachedImage(fileName: photoFileName) {
            loadedImage = cached
            revealPhoto()
            return
        }

        let image = await VehiclePhotoStore.shared.image(fileName: photoFileName)
        loadedImage = image
        if image != nil {
            revealPhoto()
        } else {
            // Fall back to SF Symbol (displayImage becomes nil).
            photoVisible = false
        }
    }
}
