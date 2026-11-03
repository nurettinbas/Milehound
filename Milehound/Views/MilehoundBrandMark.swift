import SwiftUI
import UIKit

/// Recolors the Sky `MilehoundLogo` so the hound/road stay white and the plate
/// matches the current Home Screen icon fill (palette tint in Light, mid in Dark).
@MainActor
enum MilehoundThemedLogo {
    private static var cache: [String: UIImage] = [:]

    static func image(palette: ShellPalette, scheme: ColorScheme) -> UIImage? {
        let key = "\(palette.rawValue)-\(scheme == .dark ? "d" : "l")"
        if let cached = cache[key] { return cached }
        guard let base = UIImage(named: "MilehoundLogo") else { return nil }
        if palette == .sky, scheme == .light {
            cache[key] = base
            return base
        }
        let fill = UIColor(
            red: palette.homeScreenIconFillRGB(for: scheme).r,
            green: palette.homeScreenIconFillRGB(for: scheme).g,
            blue: palette.homeScreenIconFillRGB(for: scheme).b,
            alpha: 1
        )
        let themed = recoloringNonWhitePixels(base, fill: fill) ?? base
        cache[key] = themed
        return themed
    }

    private static func recoloringNonWhitePixels(_ image: UIImage, fill: UIColor) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var fillR: CGFloat = 0
        var fillG: CGFloat = 0
        var fillB: CGFloat = 0
        var fillA: CGFloat = 0
        fill.getRed(&fillR, green: &fillG, blue: &fillB, alpha: &fillA)

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let fr = UInt8((fillR * 255).rounded())
        let fg = UInt8((fillG * 255).rounded())
        let fb = UInt8((fillB * 255).rounded())

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[index]
            let green = pixels[index + 1]
            let blue = pixels[index + 2]
            let luminance = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
            guard luminance < 200 else { continue }
            pixels[index] = fr
            pixels[index + 1] = fg
            pixels[index + 2] = fb
        }

        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }
}

/// App icon mark + Milehound wordmark for onboarding, share preview, and prep overlay.
struct MilehoundBrandMark: View {
    var showsWordmark: Bool = true
    var symbolSize: CGFloat = 88
    var axis: Axis = .vertical

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 10) {
                    logo
                    wordmark(font: .headline.weight(.bold))
                }
            } else {
                VStack(spacing: 14) {
                    logo
                    wordmark(font: .title2.weight(.bold))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Milehound")
    }

    @ViewBuilder
    private var logo: some View {
        Group {
            if let logo = MilehoundThemedLogo.image(palette: shellPalette, scheme: colorScheme) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("MilehoundLogo")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: symbolSize, height: symbolSize)
        .clipShape(RoundedRectangle(cornerRadius: symbolSize * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: symbolSize * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(
            color: shellPalette.tintColor(for: colorScheme).opacity(axis == .horizontal ? 0.18 : 0.28),
            radius: axis == .horizontal ? 8 : 16,
            y: axis == .horizontal ? 4 : 8
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func wordmark(font: Font) -> some View {
        if showsWordmark {
            Text("Milehound")
                .font(font)
                .foregroundStyle(GlassText.primary(for: colorScheme))
        }
    }
}

#Preview {
    ZStack {
        AtmosphericBackground(style: .canvas)
        MilehoundBrandMark()
    }
}
