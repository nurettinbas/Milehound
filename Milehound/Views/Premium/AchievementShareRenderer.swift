import SwiftUI
import UIKit

@MainActor
enum AchievementShareRenderer {
    static let pixelSize = RecapShareRenderer.pixelSize
    static let layoutWidth = RecapShareRenderer.layoutWidth
    static var layoutSize: CGSize { RecapShareRenderer.layoutSize }

    private static var cache: [String: UIImage] = [:]

    static func caption(for item: AchievementDisplay) -> String {
        var parts = [
            L10n.string(item.id.titleKey),
            L10n.string("premium.achievements.unlocked")
        ]
        if let unlockedAt = item.unlockedAt {
            parts.append(unlockedAt.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("Milehound")
        return parts.joined(separator: " · ")
    }

    static func image(
        for item: AchievementDisplay,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> UIImage {
        let key = cacheKey(for: item, palette: palette, scheme: scheme)
        if let cached = cache[key] { return cached }
        let rendered = render(item: item, palette: palette, scheme: scheme)
        cache[key] = rendered
        return rendered
    }

    private static func cacheKey(
        for item: AchievementDisplay,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> String {
        let unlocked = item.unlockedAt.map { String($0.timeIntervalSince1970) } ?? "locked"
        return "\(item.id.rawValue)-\(palette.rawValue)-\(scheme == .dark ? "d" : "l")-\(unlocked)"
    }

    private static func render(
        item: AchievementDisplay,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> UIImage {
        let layout = layoutSize
        let card = AchievementShareCardView(item: item)
            .frame(width: layout.width, height: layout.height)
            .environment(\.shellPalette, palette)
            .environment(\.colorScheme, scheme)
            .environment(\.achievementIdleTime, nil)
            .preferredColorScheme(scheme)
            .milehoundShareCaptureEnvironment()

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: layout.width, height: layout.height)
        renderer.scale = pixelSize.width / layout.width
        return renderer.uiImage ?? UIImage()
    }
}

/// Story-sized poster: palette atmosphere, brand, frozen glass plate, 3D medal + copy.
private struct AchievementShareCardView: View {
    let item: AchievementDisplay

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        ZStack {
            AtmosphericBackground()
            VStack(spacing: 0) {
                MilehoundBrandMark(showsWordmark: true, symbolSize: 36)
                    .padding(.top, 28)
                Spacer(minLength: 0)
                badgePlate
                    .padding(.horizontal, 28)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGlassShell()
        }
        .clipped()
    }

    @ViewBuilder
    private var badgePlate: some View {
        let palette = AchievementTheme.medalPalette(for: item.id, scheme: colorScheme)
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(palette.glow.opacity(colorScheme == .dark ? 0.42 : 0.28))
                    .frame(width: 188, height: 188)
                AchievementMedalMark(
                    item: item,
                    size: AchievementGalleryTokens.expandedMedalSize,
                    playsMotion: false
                )
            }
            .frame(height: 188)

            Text(L10n.string("premium.achievements.unlocked"))
                .font(.subheadline.weight(.semibold))
                .glassSecondaryInk()

            Text(L10n.string(item.id.titleKey))
                .font(.title2.weight(.bold))
                .glassPrimaryInk()
                .multilineTextAlignment(.center)

            Text(L10n.string(item.id.bodyKey))
                .font(.body.weight(.medium))
                .glassSecondaryInk()
                .multilineTextAlignment(.center)

            if let unlockedAt = item.unlockedAt {
                Text(unlockedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .glassSecondaryInk()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: GlassTokens.cardRadius, contentInset: 0, frozen: true, allowsNative: false)
        .shadow(color: palette.glow.opacity(0.22), radius: 28, y: 12)
        .shadow(color: shellPalette.tintColor(for: colorScheme).opacity(0.16), radius: 18, y: 8)
    }
}
