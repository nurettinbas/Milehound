import SwiftData
import SwiftUI

struct TripRowView: View {
    let trip: Trip
    var places: [SavedPlace] = []
    var categories: [UserCategory] = []
    var privacyRadius: Double = 500
    /// Resolved from `trip.vehicleID` upstream — relationship is not populated on list rows  .
    var vehicle: VehicleProfile? = nil
    var morphNamespace: Namespace.ID?
    var morphID: UUID?
    
    /// Soft-lands tzhe map thumbnail after stop→row morph.
    var emphasizeLanding: Bool = false
    /// Set on the combined row element so XCTest sees it (a parent `NavigationLink` id is easy to lose).
    var rowAccessibilityIdentifier: String? = nil

    @Bindable private var settings = AppSettings.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: UIImage?
    @State private var thumbnailAppearance: MapSnapshotAppearance?
    @State private var iconSway = false

    private static let thumbnailSize: CGFloat = 45
    private static let vehicleBadgeSize: CGFloat = 16

    private var routeSummary: String {
        TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
    }

    private var currentAppearance: MapSnapshotAppearance {
        MapSnapshotAppearance(colorScheme)
    }

    private var displayedThumbnail: UIImage? {
        TripMapSnapshotCache.shared.cachedImage(for: trip.id, appearance: currentAppearance)
            ?? thumbnail
    }

    private var isCurrentAppearanceReady: Bool {
        if TripMapSnapshotCache.shared.cachedImage(for: trip.id, appearance: currentAppearance) != nil {
            return true
        }
        return thumbnail != nil && thumbnailAppearance == currentAppearance
    }

    private var shouldAnimateLoadingIcon: Bool {
        !isCurrentAppearanceReady
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !UITestSupport.isEnabled
    }

    var body: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        HStack(alignment: .center, spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 5) {
                Text(routeSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme, palette: shellPalette))
                    .lineLimit(2)

                HStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 7, weight: .semibold))
                        Text(TripListViewModel.durationText(for: trip))
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }

                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(GlassText.tertiary(for: colorScheme, palette: shellPalette))

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 7, weight: .semibold))
                        Text(TripListViewModel.dateText(for: trip))
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }

                    if trip.categoryID == BuiltInCategory.businessID.uuidString {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 8))
                            .glassAccentForeground()
                    } else if let suggestedName = pendingSuggestedCategoryName {
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7, weight: .semibold))
                            Text(L10n.tripCategorySuggested(suggestedName))
                                .font(.system(size: 8, weight: .medium))
                                .lineLimit(1)
                        }
                        .glassAccentForeground()
                        .accessibilityHidden(true)
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(rowMetaColor)

                HStack(spacing: 5) {
                    metricChip(icon: "road.lanes", text: TripListViewModel.distanceText(for: trip))

                    if let fuel = TripListViewModel.fuelText(for: trip) {
                        metricChip(icon: "fuelpump", text: fuel)
                            .id(fuelCurrencyCode)
                    }

                    if let maxLabel = TripListViewModel.maxSpeedLabel(for: trip) {
                        metricChip(icon: "speedometer", text: maxLabel)
                    }

                    if let avgLabel = TripListViewModel.averageSpeedLabel(for: trip) {
                        metricChip(icon: "gauge.with.dots.needle.33percent", text: avgLabel)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background {
            if emphasizeLanding, !reduceMotion {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MilehoundBrandColors.brandBottom.opacity(0.14))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -4)
            }
        }
        .overlay {
            if emphasizeLanding, !reduceMotion {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MilehoundBrandColors.brandBottom.opacity(0.35), lineWidth: 1)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -4)
            }
        }
        .scaleEffect(emphasizeLanding && !reduceMotion ? 1.02 : 1)
        .animation(MilehoundMotion.recordingMorph, value: emphasizeLanding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .optionalAccessibilityIdentifier(rowAccessibilityIdentifier)
        .task(id: thumbnailTaskID) {
            let appearance = currentAppearance
            if let cached = TripMapSnapshotCache.shared.cachedImage(for: trip.id, appearance: appearance) {
                thumbnail = cached
                thumbnailAppearance = appearance
                return
            }

            if emphasizeLanding, !reduceMotion {
                // Brief hold so morph settles before snapshot lands.
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
            }

            let image = await TripMapSnapshotCache.shared.snapshot(
                for: trip,
                appearance: appearance,
                container: modelContext.container
            )
            guard !Task.isCancelled else { return }
            guard currentAppearance == appearance else { return }

            thumbnail = image
            thumbnailAppearance = appearance
        }
    }

    private var thumbnailTaskID: String {
        "\(trip.id.uuidString)-\(currentAppearance.rawValue)"
    }

    private var pendingSuggestedCategoryName: String? {
        guard trip.hasPendingCategorySuggestion,
              let pendingID = trip.pendingSuggestedCategoryID
        else { return nil }
        if let name = categories.first(where: { $0.id.uuidString == pendingID })?.name {
            return name
        }
        if pendingID == BuiltInCategory.businessID.uuidString {
            return L10n.categoryBusiness
        }
        return nil
    }

    private var accessibilitySummary: String {
        var parts = [routeSummary, TripListViewModel.durationText(for: trip)]
        parts.append(TripListViewModel.dateText(for: trip))
        parts.append(TripListViewModel.distanceText(for: trip))
        if let vehicle {
            parts.append(vehicle.name)
        }
        if let suggestedName = pendingSuggestedCategoryName {
            parts.append(L10n.tripCategorySuggested(suggestedName))
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let plate = shellPalette.glassReadabilityTint(for: colorScheme).opacity(
            colorScheme == .dark ? 0.18 : GlassContrast.nestedTileTintOpacity
        )
        ZStack {
            if let displayedThumbnail {
                Image(uiImage: displayedThumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                plate
            }

            if !isCurrentAppearanceReady {
                Image(systemName: "map")
                    .font(.system(size: 11))
                    .glassSecondaryInk()
                    .offset(x: shouldAnimateLoadingIcon ? (iconSway ? 3 : -3) : 0)
                    .animation(
                        shouldAnimateLoadingIcon
                            ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                            : nil,
                        value: iconSway
                    )
                    .onAppear {
                        iconSway = shouldAnimateLoadingIcon
                    }
                    .onChange(of: shouldAnimateLoadingIcon) { _, animate in
                        iconSway = animate
                    }
            }
        }
        .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let vehicle {
                vehicleBadge(for: vehicle)
                    .padding(2)
            }
        }
        .accessibilityHidden(true)
    }

    private func vehicleBadge(for vehicle: VehicleProfile) -> some View {
        let size = Self.vehicleBadgeSize
        return VehicleAvatarView(
            systemImage: VehicleIconOption.default.rawValue,
            photoFileName: vehicle.photoFileName,
            size: size,
            cornerRadius: size * 0.28,
            isElectricAccent: vehicle.fuelType == .electric,
            showsSymbolPlate: true,
            symbolFitsFrame: true
        )
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
    }

    private var rowMetaColor: Color {
        GlassText.secondary(for: colorScheme, palette: shellPalette)
    }

    private func metricChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(rowMetaColor)
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier, !identifier.isEmpty {
            self.accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

#Preview {
    List {
        TripRowView(trip: PreviewData.sampleTrip)
    }
    .modelContainer(PreviewData.shared.container)
}
