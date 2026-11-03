import SwiftData
import SwiftUI

enum TravelJournalCornerMode: Equatable {
    case compact
    case expanded
}

struct TravelJournalEditPanel: View {
    @Bindable var journal: TravelJournal
    let trips: [Trip]
    let selectedTripID: UUID?
    let places: [SavedPlace]
    let restHeight: CGFloat
    let isExpanded: Bool
    /// Wide landscape and the open book. The trip list fills the pane. No sheet grabber.
    var fillsColumn: Bool = false
    /// Closed cover, landscape. Compact is the summary; expanded is the summary plus the trips.
    var cornerMode: TravelJournalCornerMode? = nil
    var columnTopInset: CGFloat = 0
    var columnBottomInset: CGFloat = 0
    let reduceMotion: Bool
    var onSelectTrip: (UUID) -> Void
    var onOpenTrip: (Trip) -> Void
    var onRemoveTrip: (Trip) -> Void
    var onEdit: () -> Void
    var onToggleExpanded: () -> Void
    var onGrabberDragChanged: (CGFloat) -> Void
    var onGrabberDragEnded: (CGFloat) -> Void
    /// Closed cover only. Height of the grabber and summary, which is the whole compact card.
    var onCornerSummaryHeight: (CGFloat) -> Void = { _ in }

    @Bindable private var settings = AppSettings.shared
    @State private var grabberHint = false

    private var showsTrips: Bool { fillsColumn || isExpanded || cornerMode == .expanded }

    private var showsGrabber: Bool { !fillsColumn }

    var body: some View {
        if cornerMode != nil {
            cornerBody
        } else {
            sheetBody
        }
    }

    /// Compact, the summary keeps its natural height, so the card ends under the metrics.
    /// Expanded, the summary and the trips scroll together under the grabber.
    private var cornerBody: some View {
        VStack(spacing: 0) {
            if showsTrips {
                panelGrabber
                List {
                    cornerSummaryRow
                    cornerTripRows
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(.bottom, TripDetailKeyboardLayout.restingScrollBottomInset, for: .scrollContent)
            } else {
                VStack(spacing: 0) {
                    panelGrabber
                    panelHeader
                        .padding(.horizontal, GlassTokens.listContentHorizontalInset)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { onCornerSummaryHeight(proxy.size.height) }
                            .onChange(of: proxy.size.height) { _, height in
                                onCornerSummaryHeight(height)
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cornerSummaryRow: some View {
        panelHeader
            .listRowInsets(
                EdgeInsets(
                    top: 4,
                    leading: GlassTokens.listContentHorizontalInset,
                    bottom: 12,
                    trailing: GlassTokens.listContentHorizontalInset
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var sheetBody: some View {
        VStack(spacing: 0) {
            if showsGrabber {
                panelGrabber
            }

            List {
                Section {
                    panelHeader
                        .listRowInsets(
                            EdgeInsets(
                                top: 4,
                                leading: GlassTokens.listContentHorizontalInset,
                                bottom: 8,
                                trailing: GlassTokens.listContentHorizontalInset
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if showsTrips {
                    tripSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(!showsTrips)
            .contentMargins(.top, fillsColumn ? columnTopInset : 0, for: .scrollContent)
            .contentMargins(
                .bottom,
                fillsColumn ? columnBottomInset : TripDetailKeyboardLayout.restingScrollBottomInset,
                for: .scrollContent
            )
        }
        .frame(maxWidth: .infinity, maxHeight: fillsColumn ? .infinity : nil)
        .frame(height: fillsColumn ? nil : restHeight)
        .animation(reduceMotion || fillsColumn ? nil : MilehoundMotion.sheetRise, value: isExpanded)
    }

    /// Day labels are rows, not plain-list section headers, so none of them pins under the grabber.
    private var cornerTripRows: some View {
        ForEach(dayGroups, id: \.day) { group in
            Text(DateFormatters.tripDateOnly.string(from: group.day))
                .font(.caption.weight(.semibold))
                .glassSecondaryInk()
                .listRowInsets(
                    EdgeInsets(
                        top: 10,
                        leading: GlassTokens.listContentHorizontalInset,
                        bottom: 4,
                        trailing: GlassTokens.listContentHorizontalInset
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(group.trips, id: \.id) { trip in
                tripRow(trip)
            }
        }
    }

    private var tripSections: some View {
        ForEach(dayGroups, id: \.day) { group in
            Section {
                ForEach(group.trips, id: \.id) { trip in
                    tripRow(trip)
                }
            } header: {
                Text(DateFormatters.tripDateOnly.string(from: group.day))
                    .font(.caption.weight(.semibold))
                    .glassSecondaryInk()
                    .textCase(nil)
            }
        }
    }

    private var panelGrabber: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 11, weight: .semibold))
                .glassTertiaryInk()
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .offset(y: grabberNudge)
                .padding(.top, 4)
                .onAppear { startGrabberHint() }
                .onChange(of: isExpanded) { _, _ in
                    startGrabberHint()
                }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard abs(value.translation.height) >= 8 else { return }
                    onGrabberDragChanged(value.translation.height)
                }
                .onEnded { value in
                    if abs(value.translation.height) < 8 {
                        onToggleExpanded()
                    } else {
                        onGrabberDragEnded(value.predictedEndTranslation.height)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(cornerGrabberIdentifier)
        .accessibilityLabel(isExpanded
            ? L10n.string("journal.map.collapse")
            : L10n.journalTrips)
    }

    private var cornerGrabberIdentifier: String {
        guard cornerMode != nil else { return "journal.sheet.grabber" }
        return isExpanded ? "journal.cornerCard.collapse" : "journal.cornerCard.expand"
    }

    /// A short lift while the sheet is compact, so the chevron reads as “pull up”.
    private var grabberNudge: CGFloat {
        guard !reduceMotion, !isExpanded, grabberHint else { return 0 }
        return -5
    }

    private func startGrabberHint() {
        guard !reduceMotion, !isExpanded else {
            grabberHint = false
            return
        }
        grabberHint = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            grabberHint = true
        }
    }

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journal.title)
                        .font(cornerMode == nil ? .headline : .subheadline.weight(.semibold))
                        .lineLimit(cornerMode == .compact ? 1 : nil)
                    Text(L10n.journalDateRange(start: journal.startedOn, end: journal.endedOn))
                        .font(cornerMode == nil ? .caption : .caption2)
                        .glassSecondaryInk()
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                editButton
            }

            if let note = journal.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .glassSecondaryInk()
                    .lineLimit(showsTrips ? 4 : 2)
            }

            metricRow
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Text(L10n.string("journal.edit"))
                .font(cornerMode == nil ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .glassAccentForeground()
                .padding(.horizontal, cornerMode == nil ? 10 : 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPlainHit)
    }

    private func tripRow(_ trip: Trip) -> some View {
        let isSelected = trip.id == selectedTripID
        return Button {
            onSelectTrip(trip.id)
        } label: {
            TripRowView(
                trip: trip,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )
            .padding(8)
            .glassChrome(cornerRadius: 14, enabled: isSelected)
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityIdentifier(cornerMode != nil ? "journal.cornerCard.member" : "journal.member.\(trip.id.uuidString)")
        .animation(reduceMotion ? nil : MilehoundMotion.gentle, value: selectedTripID)
        .listRowInsets(
            EdgeInsets(
                top: 3,
                leading: GlassTokens.listContentHorizontalInset,
                bottom: 3,
                trailing: GlassTokens.listContentHorizontalInset
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .confirmingDeleteSwipe(.journalRemove, title: L10n.journalRemove) {
            onRemoveTrip(trip)
        }
        .contextMenu {
            Button { onOpenTrip(trip) } label: {
                Text(L10n.string("journal.open.trip"))
            }
            Button(role: .destructive) {
                DeleteConfirmPresenter.shared.confirm(.journalRemove) {
                    onRemoveTrip(trip)
                }
            } label: {
                Text(L10n.journalRemove)
            }
        }
    }

    private var dayGroups: [(day: Date, trips: [Trip])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: trips) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, (grouped[day] ?? []).sorted { $0.startedAt > $1.startedAt })
        }
    }

    /// Phone uses the caption chips. The upright Duo card is narrower, so the row
    /// steps down until trips, distance, and cost sit on one line.
    private var metricRow: some View {
        ViewThatFits(in: .horizontal) {
            metricLine(text: .caption.weight(.semibold), icon: .caption2.weight(.semibold), spacing: 8, horizontalPad: 8, verticalPad: 5)
            metricLine(text: .caption2.weight(.semibold), icon: .caption2.weight(.semibold), spacing: 4, horizontalPad: 6, verticalPad: 4)
            metricLine(text: .system(size: 10, weight: .semibold), icon: .system(size: 9, weight: .semibold), spacing: 3, horizontalPad: 5, verticalPad: 3)
        }
    }

    /// The sheet chip opens the trip list. The landscape column already shows that list.
    @ViewBuilder
    private func tripCountChip(text: Font, icon: Font, horizontalPad: CGFloat, verticalPad: CGFloat) -> some View {
        if fillsColumn {
            metric(
                L10n.journalTripCount(journal.tripCount),
                icon: "map",
                textFont: text,
                iconFont: icon,
                horizontalPad: horizontalPad,
                verticalPad: verticalPad
            )
        } else {
            Button(action: onToggleExpanded) {
                metric(
                    L10n.journalTripCount(journal.tripCount),
                    icon: "map",
                    textFont: text,
                    iconFont: icon,
                    horizontalPad: horizontalPad,
                    verticalPad: verticalPad
                )
            }
            .buttonStyle(.glassPlainHit)
            .accessibilityHint(isExpanded
                ? L10n.string("journal.map.collapse")
                : L10n.string("journal.map.expand"))
        }
    }

    private func metricLine(text: Font, icon: Font, spacing: CGFloat, horizontalPad: CGFloat, verticalPad: CGFloat) -> some View {
        HStack(spacing: spacing) {
            tripCountChip(text: text, icon: icon, horizontalPad: horizontalPad, verticalPad: verticalPad)

            metric(DateFormatters.formatDistance(journal.distanceMeters), icon: "road.lanes", textFont: text, iconFont: icon, horizontalPad: horizontalPad, verticalPad: verticalPad)
            if journal.fuelCost > 0 {
                metric(FuelCostCalculator.formatCost(journal.fuelCost), icon: "fuelpump", textFont: text, iconFont: icon, horizontalPad: horizontalPad, verticalPad: verticalPad)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func metric(_ text: String, icon: String, textFont: Font, iconFont: Font, horizontalPad: CGFloat, verticalPad: CGFloat) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(iconFont)
            Text(text)
                .font(textFont)
                .lineLimit(1)
        }
        .glassAccentForeground()
        .padding(.horizontal, horizontalPad)
        .padding(.vertical, verticalPad)
        .background {
            Capsule().fill(MilehoundBrandColors.brandBottom.opacity(0.12))
        }
    }
}
