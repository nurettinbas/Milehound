import SwiftData
import SwiftUI

struct TravelJournalRowView: View {
    let journal: TravelJournal
    var reduceMotion: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var mosaic: [UIImage] = []

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            mosaicView
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(journal.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme, palette: shellPalette))
                    .lineLimit(2)

                Text(L10n.journalDateRange(start: journal.startedOn, end: journal.endedOn))
                    .font(.system(size: 9))
                    .foregroundStyle(GlassText.secondary(for: colorScheme, palette: shellPalette))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    metaChip(icon: "map", text: L10n.journalTripCount(journal.tripCount))
                    metaChip(icon: "road.lanes", text: DateFormatters.formatDistance(journal.distanceMeters))
                    if journal.fuelCost > 0 {
                        metaChip(icon: "fuelpump", text: FuelCostCalculator.formatCost(journal.fuelCost))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .task(id: mosaicTaskID) {
            backfillMosaicIDsIfNeeded()
            await loadMosaic()
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            journal.title,
            L10n.journalDateRange(start: journal.startedOn, end: journal.endedOn),
            L10n.journalTripCount(journal.tripCount),
            DateFormatters.formatDistance(journal.distanceMeters)
        ]
        if journal.fuelCost > 0 {
            parts.append(FuelCostCalculator.formatCost(journal.fuelCost))
        }
        return parts.joined(separator: ", ")
    }

    private var mosaicTaskID: String {
        "\(journal.mosaicTripIDsRaw)-\(MapSnapshotAppearance(colorScheme).rawValue)"
    }

    private var mosaicSize: CGFloat { 40 }
    private var mosaicCorner: CGFloat { 9 }
    private var mosaicGap: CGFloat { 1.5 }

    private var mosaicView: some View {
        Group {
            if mosaic.isEmpty {
                RoundedRectangle(cornerRadius: mosaicCorner, style: .continuous)
                    .fill(MilehoundBrandColors.brandBottom.opacity(0.18))
                    .overlay {
                        Image(systemName: "map")
                            .font(.system(size: 13, weight: .semibold))
                            .glassAccentForeground()
                    }
            } else if mosaic.count == 1 {
                mosaicTile(mosaic[0], size: mosaicSize)
            } else {
                let cell = (mosaicSize - mosaicGap) / 2
                VStack(spacing: mosaicGap) {
                    HStack(spacing: mosaicGap) {
                        mosaicCell(0, size: cell)
                        mosaicCell(1, size: cell)
                    }
                    HStack(spacing: mosaicGap) {
                        mosaicCell(2, size: cell)
                        mosaicCell(3, size: cell)
                    }
                }
            }
        }
        .frame(width: mosaicSize, height: mosaicSize)
        .clipShape(RoundedRectangle(cornerRadius: mosaicCorner, style: .continuous))
        .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: mosaic.count)
    }

    @ViewBuilder
    private func mosaicCell(_ index: Int, size: CGFloat) -> some View {
        if index < mosaic.count {
            mosaicTile(mosaic[index], size: size)
        } else {
            MilehoundBrandColors.brandBottom.opacity(0.18)
                .frame(width: size, height: size)
        }
    }

    private func mosaicTile(_ image: UIImage, size: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(GlassText.secondary(for: colorScheme, palette: shellPalette))
    }

    @MainActor
    private func backfillMosaicIDsIfNeeded() {
        let needed = min(journal.tripCount, TravelJournal.mosaicSlotCount)
        guard journal.mosaicTripIDs.count < needed else { return }
        TravelJournalTotals.refresh(journal)
        try? modelContext.save()
    }

    @MainActor
    private func loadMosaic() async {
        let appearance = MapSnapshotAppearance(colorScheme)
        var images: [UIImage] = []
        for tripID in journal.mosaicTripIDs.prefix(TravelJournal.mosaicSlotCount) {
            if Task.isCancelled { return }
            if let cached = TripMapSnapshotCache.shared.cachedImage(for: tripID, appearance: appearance) {
                images.append(cached)
                continue
            }
            let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
            guard let trip = try? modelContext.fetch(descriptor).first else { continue }
            if let image = await TripMapSnapshotCache.shared.snapshot(
                for: trip,
                appearance: appearance,
                container: modelContext.container
            ) {
                images.append(image)
            }
        }
        guard !Task.isCancelled else { return }
        mosaic = images
    }
}
