import SwiftUI
import UIKit

/// Matches the system launch screen, so the first SwiftUI frame does not flash.
struct LaunchIntroLaunchFill: View {
    var body: some View {
        Color("LaunchBackground")
            .ignoresSafeArea()
    }
}

/// Full-screen cold-launch intro. Tap anywhere to open the app in a quarter second.
struct LaunchIntroOverlay: View {
    var onReveal: () -> Void
    /// First intro frame is committed. Safe to build the app underneath.
    var onStarted: () -> Void
    var onLanded: () -> Void
    var onFinished: (_ playedMotion: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var skipped = false

    var body: some View {
        let timeline = LaunchIntroTimeline.resolve(reduceMotion: reduceMotion, lowPower: isLowPower)
        LaunchIntroSceneView(
            timeline: skipped ? .skip : timeline,
            launch: UIColor(named: "LaunchBackground") ?? .systemBlue,
            plate: uiColor(shellPalette.homeScreenIconFillRGB(for: colorScheme)),
            logo: MilehoundThemedLogo.image(palette: shellPalette, scheme: colorScheme),
            hound: UIImage(named: "MilehoundHound"),
            houndParts: LaunchIntroHoundParts.load(),
            skipped: skipped,
            onReveal: {
                guard timeline.allowsMotion, !skipped else { return }
                onReveal()
            },
            onStarted: onStarted,
            onLanded: {
                guard !skipped else { return }
                onLanded()
            },
            onFinished: {
                onFinished(timeline.allowsMotion && !skipped)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .task(id: skipped) {
            let duration = (skipped ? LaunchIntroTimeline.skip.total : timeline.total) + 0.45
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            onFinished(timeline.allowsMotion && !skipped)
        }
        .onTapGesture {
            guard !skipped else { return }
            skipped = true
            if timeline.allowsMotion {
                onReveal()
            }
        }
        .accessibilityHidden(true)
    }

    private var isLowPower: Bool {
        let process = ProcessInfo.processInfo
        return process.isLowPowerModeEnabled
            || process.thermalState == .serious
            || process.thermalState == .critical
    }

    private func uiColor(_ rgb: ShellRGB) -> UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
}
