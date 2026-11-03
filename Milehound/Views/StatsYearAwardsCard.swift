import SwiftUI

struct StatsYearAwardsCard: View {
    let snapshot: StatsYearAwardsSnapshot?
    let medals: [StatsYearAward]
    let years: [Int]
    @Binding var selectedYear: Int
    var reduceMotion: Bool
    var showsYearPicker: Bool = true
    var showsSectionTitle: Bool = true
    var onAppear: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if showsSectionTitle {
                        Text(L10n.string("stats.awards.section"))
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(L10n.string("stats.awards.unfiltered_hint"))
                        .font(.caption2)
                        .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                    if let snapshot, snapshot.hasData {
                        Text(DateFormatters.formatDistance(snapshot.totalDistanceMeters))
                            .font(.title3.weight(.bold))
                            .glassAccentForeground()
                    }
                }
                Spacer()
                if showsYearPicker {
                    if years.count > 1 {
                        Picker(L10n.string("stats.awards.year"), selection: $selectedYear) {
                            ForEach(years, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .glassMenuPicker()
                        .accessibilityIdentifier("recap.year.toggle")
                        .accessibilityLabel(L10n.string("stats.awards.year"))
                        .accessibilityValue(String(selectedYear))
                    } else {
                        Text(String(selectedYear))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                            .accessibilityIdentifier("recap.year.toggle")
                            .accessibilityLabel(L10n.string("stats.awards.year"))
                            .accessibilityValue(String(selectedYear))
                    }
                }
            }

            if snapshot == nil {
                StatsChartSkeleton(height: 168, reduceMotion: reduceMotion)
            } else if let snapshot, !snapshot.hasData {
                Text(L10n.string("stats.awards.empty"))
                    .font(.caption)
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
            ForEach(Array(medals.prefix(3))) { medal in
                            medalCell(medal)
                        }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(medals.dropFirst(3))) { medal in
                            medalCell(medal)
                        }
                    }
                }
            }
        }
        .onAppear(perform: onAppear)
    }

    private func medalCell(_ medal: StatsYearAward) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(medal.kind.badgeFill)
                    .frame(width: Self.medalSize, height: Self.medalSize)
                if !medal.isUnlocked {
                    AchievementMedalLockScrim(size: Self.medalSize)
                }
                Image(systemName: medal.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.white)
                    .opacity(1)
                if !medal.isUnlocked {
                    AchievementMedalLockOverlay(size: Self.medalSize)
                }
            }
            Text(medal.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(medal.detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(medal.title), \(medal.isUnlocked ? medal.detail : L10n.string("stats.awards.locked"))")
    }

    private static let medalSize: CGFloat = 52
}

private extension StatsYearAwardKind {
    var badgeAccent: Color {
        switch self {
        case .distance: MilehoundBrandColors.brandBottom
        case .nightOwl: Color(red: 0.52, green: 0.42, blue: 0.98)
        case .goal: Color(red: 0.18, green: 0.72, blue: 0.54)
        case .busiestDay: Color(red: 0.96, green: 0.58, blue: 0.16)
        case .expensiveVehicle: Color(red: 0.92, green: 0.36, blue: 0.52)
        case .expensiveMonth: Color(red: 0.22, green: 0.74, blue: 0.86)
        }
    }

    var badgeHighlight: Color {
        switch self {
        case .distance: MilehoundBrandColors.brandTop
        case .nightOwl: Color(red: 0.72, green: 0.58, blue: 1.0)
        case .goal: Color(red: 0.42, green: 0.90, blue: 0.68)
        case .busiestDay: Color(red: 1.0, green: 0.80, blue: 0.36)
        case .expensiveVehicle: Color(red: 1.0, green: 0.58, blue: 0.68)
        case .expensiveMonth: Color(red: 0.48, green: 0.90, blue: 0.96)
        }
    }

    var badgeFill: LinearGradient {
        LinearGradient(
            colors: [badgeHighlight, badgeAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
