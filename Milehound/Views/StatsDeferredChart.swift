import SwiftUI

/// Reserves chart layout, then mounts heavy Swift Charts content after the row appears.
struct StatsDeferredChart<Content: View, TitleAccessory: View>: View {
    let title: String
    let chartHeight: CGFloat
    var reduceMotion: Bool
    var isPageActive: Bool = true
    var titleAlignment: HorizontalAlignment = .leading
    @ViewBuilder var titleAccessory: () -> TitleAccessory
    @ViewBuilder let content: () -> Content

    @State private var isLoaded = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: titleAlignment, spacing: 8) {
            if isLoaded {
                content()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .chartStatsAppearAnimation(reduceMotion: reduceMotion)
            } else {
                StatsChartSkeleton(height: chartHeight, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            titleAccessory()
        }
        .onAppear {
            hasAppeared = true
            scheduleLoadIfNeeded()
        }
        .onDisappear {
            hasAppeared = false
        }
        .onChange(of: isPageActive) { _, _ in
            scheduleLoadIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func scheduleLoadIfNeeded() {
        guard hasAppeared, isPageActive, !isLoaded else { return }
        if reduceMotion {
            isLoaded = true
        } else {
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, hasAppeared, isPageActive else { return }
                isLoaded = true
            }
        }
    }
}

extension StatsDeferredChart where TitleAccessory == EmptyView {
    init(
        title: String,
        chartHeight: CGFloat,
        reduceMotion: Bool,
        isPageActive: Bool = true,
        titleAlignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.chartHeight = chartHeight
        self.reduceMotion = reduceMotion
        self.isPageActive = isPageActive
        self.titleAlignment = titleAlignment
        self.titleAccessory = { EmptyView() }
        self.content = content
    }
}

/// Defers mounting a heavy chart block (e.g. donut + legend) without a separate title row.
struct StatsDeferredContent<Content: View>: View {
    let placeholderHeight: CGFloat
    var reduceMotion: Bool
    var isPageActive: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var isLoaded = false
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if isLoaded {
                content()
                    .chartStatsAppearAnimation(reduceMotion: reduceMotion)
            } else {
                StatsChartSkeleton(height: placeholderHeight, reduceMotion: reduceMotion)
            }
        }
        .onAppear {
            hasAppeared = true
            scheduleLoadIfNeeded()
        }
        .onDisappear {
            hasAppeared = false
        }
        .onChange(of: isPageActive) { _, _ in
            scheduleLoadIfNeeded()
        }
    }

    private func scheduleLoadIfNeeded() {
        guard hasAppeared, isPageActive, !isLoaded else { return }
        if reduceMotion {
            isLoaded = true
        } else {
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, hasAppeared, isPageActive else { return }
                isLoaded = true
            }
        }
    }
}

struct StatsChartSkeleton: View {
    let height: CGFloat
    var reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var shimmerPhase = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(baseFill)
            .overlay {
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    MilehoundBrandColors.brandBottom.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                    Color.clear
                                ],
                                startPoint: shimmerPhase ? .trailing : .leading,
                                endPoint: shimmerPhase ? .init(x: 1.5, y: 0.5) : .init(x: 0.5, y: 0.5)
                            )
                        )
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    shimmerPhase = true
                }
            }
    }

    private var baseFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : shellPalette.glassReadabilityTint(for: .light).opacity(GlassContrast.nestedTileTintOpacity)
    }
}
