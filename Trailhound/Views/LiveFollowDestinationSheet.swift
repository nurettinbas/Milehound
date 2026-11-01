import CoreLocation
import SwiftData
import SwiftUI

/// A saved place or a search hit the user can drive to.
struct LiveFollowDestinationOption: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String?
    let systemImage: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var destination: PlannedRouteDestination {
        PlannedRouteDestination(id: id, name: name, coordinate: coordinate)
    }

    init(
        id: String,
        name: String,
        subtitle: String?,
        systemImage: String,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    init(place: SavedPlace) {
        self.init(
            id: "place.\(place.id.uuidString)",
            name: place.name,
            subtitle: place.kind.displayName,
            systemImage: place.kind.systemImage,
            coordinate: place.coordinate
        )
    }

    init(result: NearbyPlaceOption) {
        self.init(
            id: "search.\(result.id)",
            name: result.name,
            subtitle: result.subtitle,
            systemImage: "mappin.and.ellipse",
            coordinate: result.coordinate
        )
    }
}

/// Live-map destination picker. Saved places are one tap at any speed; search is typed only
/// while the car is stopped or the trip is paused (`DestinationEntryPolicy`).
struct LiveFollowDestinationSheet: View {
    var currentDestination: PlannedRouteDestination?
    var searchCenter: CLLocationCoordinate2D?
    var onPick: (PlannedRouteDestination) -> Void
    var onClear: () -> Void
    var onDismiss: () -> Void

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(\.trailhoundLayout) private var layout
    @Query(sort: \SavedPlace.name) private var places: [SavedPlace]

    @State private var query = ""
    @State private var results: [LiveFollowDestinationOption] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private let geocodingService = GeocodingService()

    /// Open Duo and iPad get a centered form; phones keep the bottom sheet.
    static func usesFormSizing(_ layout: TrailhoundLayoutSnapshot) -> Bool {
        switch layout.layoutClass {
        case .duoOpen, .pad:
            return true
        case .phone, .phoneLandscape:
            return false
        }
    }

    private var allowsSearch: Bool {
        DestinationEntryPolicy.allowsSearch(
            speedMps: UITestSupport.plannedRouteSpeedOverrideMps ?? recordingService.displaySpeedMps,
            isPaused: recordingService.state == .paused
        )
    }

    var body: some View {
        LiveFollowDestinationSheetContent(
            savedPlaces: places.map(LiveFollowDestinationOption.init(place:)),
            currentDestinationName: currentDestination?.name,
            allowsSearch: allowsSearch,
            query: Binding(
                get: { query },
                set: { query = DestinationEntryPolicy.sanitizedQuery($0) }
            ),
            results: results,
            isSearching: isSearching,
            onPick: { option in
                onPick(option.destination)
            },
            onClear: onClear,
            onDismiss: onDismiss
        )
        .modifier(LiveFollowDestinationPresentation(formSizing: Self.usesFormSizing(layout)))
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onChange(of: allowsSearch) { _, allowed in
            if !allowed {
                cancelSearch()
                query = ""
            }
        }
        .onDisappear {
            cancelSearch()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsSearch, trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let center = searchCenter
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found: [NearbyPlaceOption]
            if let center {
                found = await geocodingService.searchPlaces(query: trimmed, near: center)
            } else {
                found = await geocodingService.searchPlaces(
                    query: trimmed,
                    near: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    regionSpan: 90
                )
            }
            guard !Task.isCancelled else { return }
            results = found.map(LiveFollowDestinationOption.init(result:))
            isSearching = false
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        results = []
    }
}

/// Stateless body so snapshots render it without SwiftData, GPS, or network.
struct LiveFollowDestinationSheetContent: View {
    var savedPlaces: [LiveFollowDestinationOption]
    var currentDestinationName: String?
    var allowsSearch: Bool
    @Binding var query: String
    var results: [LiveFollowDestinationOption]
    var isSearching: Bool
    var onPick: (LiveFollowDestinationOption) -> Void
    var onClear: () -> Void
    var onDismiss: () -> Void

    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let currentDestinationName {
                    currentRow(name: currentDestinationName)
                }
                savedSection
                searchSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .trailhoundReadableColumn()
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("recording.live_map.destination.sheet.title"))
                    .font(.title3.weight(.semibold))
                    .glassPrimaryInk()
                Text(L10n.string("recording.live_map.destination.sheet.subtitle"))
                    .font(.caption)
                    .glassSecondaryInk()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            GlassToolbarCircleButton(systemName: "xmark", action: onDismiss)
                .accessibilityLabel(L10n.actionClose)
                .accessibilityIdentifier("destinationSheet.close")
        }
    }

    private func currentRow(name: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    currentLabel(name: name)
                    clearButton
                }
            } else {
                HStack(spacing: 12) {
                    currentLabel(name: name)
                    Spacer(minLength: 8)
                    clearButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func currentLabel(name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.body.weight(.semibold))
                .glassPrimaryInk()
                .accessibilityHidden(true)
            Text(name)
                .font(.body.weight(.semibold))
                .glassPrimaryInk()
                .lineLimit(2)
        }
    }

    private var clearButton: some View {
        Button(L10n.string("recording.live_map.destination.clear")) {
            TrailhoundHaptics.selection()
            onClear()
        }
        .trailhoundDestructiveButton()
        .accessibilityIdentifier("liveMap.destination.clear")
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.string("recording.live_map.destination.sheet.saved"))
            if savedPlaces.isEmpty {
                Text(L10n.string("recording.live_map.destination.sheet.saved.empty"))
                    .font(.subheadline)
                    .glassSecondaryInk()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                optionList(savedPlaces, identifierPrefix: "destinationSheet.place")
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.string("recording.live_map.destination.sheet.search"))
            if allowsSearch {
                searchField
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.placePickerSearchLoading)
                            .font(.subheadline)
                            .glassSecondaryInk()
                    }
                    .padding(.vertical, 4)
                } else if !results.isEmpty {
                    optionList(results, identifierPrefix: "destinationSheet.result")
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    Text(L10n.placePickerSearchEmpty)
                        .font(.subheadline)
                        .glassSecondaryInk()
                        .padding(.vertical, 4)
                }
            } else {
                GlassNoticeCallout(
                    systemImage: "car.fill",
                    title: L10n.string("recording.live_map.destination.sheet.search.locked.title"),
                    message: L10n.string("recording.live_map.destination.sheet.search.locked.message")
                )
                .accessibilityIdentifier("destinationSheet.search.locked")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .glassSecondaryInk()
                .accessibilityHidden(true)
            TextField(
                L10n.string("recording.live_map.destination.sheet.search.placeholder"),
                text: $query
            )
            .font(.body)
            .focused($searchFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier("destinationSheet.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .glassSecondaryInk()
                        .glassGlyphHit()
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityLabel(L10n.placePickerSearchClear)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassInputWell(cornerRadius: 12)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .glassSecondaryInk()
            .accessibilityAddTraits(.isHeader)
    }

    private func optionList(
        _ options: [LiveFollowDestinationOption],
        identifierPrefix: String
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    TrailhoundHaptics.selection()
                    onPick(option)
                } label: {
                    optionRow(option)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityIdentifier(
                    identifierPrefix == "destinationSheet.place"
                        ? "\(identifierPrefix).\(option.id.replacingOccurrences(of: "place.", with: ""))"
                        : "\(identifierPrefix).\(index)"
                )
                if index < options.count - 1 {
                    Divider()
                }
            }
        }
        .glassCard()
    }

    private func optionRow(_ option: LiveFollowDestinationOption) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: option.systemImage)
                .font(.body.weight(.semibold))
                .glassAccentForeground()
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.body.weight(.medium))
                    .glassPrimaryInk()
                    .lineLimit(2)
                if let subtitle = option.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .glassSecondaryInk()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            GlassDisclosureChevron()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Bottom sheet on phones; centered form on the open Duo and iPad.
private struct LiveFollowDestinationPresentation: ViewModifier {
    var formSizing: Bool

    func body(content: Content) -> some View {
        content
            .modifier(Sizing(formSizing: formSizing))
            .presentationCornerRadius(28)
            .presentationBackground {
                AtmosphericBackground(style: .full)
                    .ignoresSafeArea()
            }
            .onGlassShell()
    }

    private struct Sizing: ViewModifier {
        var formSizing: Bool

        func body(content: Content) -> some View {
            if formSizing {
                if #available(iOS 18.0, *) {
                    content
                        .presentationSizing(.form)
                        .presentationDetents([.large])
                } else {
                    content.presentationDetents([.large])
                }
            } else {
                content.presentationDetents([.medium, .large])
            }
        }
    }
}
