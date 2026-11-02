import CoreLocation
import SwiftData
import SwiftUI
import UIKit

struct RecordingVehiclePicker: View {
    let vehicles: [VehicleProfile]
    let selectedVehicleID: UUID?
    let onSelect: (UUID) -> Void
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedVehicle: VehicleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var selectedName: String {
        selectedVehicle?.name ?? L10n.string("recording.vehicle.choose")
    }

    /// Mark-only chip: the glyph now fits its frame, so the box grows to keep the same optical size.
    private var avatarSize: CGFloat { compact ? 26 : 28 }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
    }

    var body: some View {
        Menu {
            ForEach(sortedVehicles) { vehicle in
                Button {
                    onSelect(vehicle.id)
                    TrailhoundHaptics.selection()
                } label: {
                    if vehicle.id == selectedVehicleID {
                        Label(vehicle.name, systemImage: "checkmark")
                    } else {
                        Text(vehicle.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                VehicleAvatarView(
                    systemImage: VehicleIconOption.default.rawValue,
                    photoFileName: selectedVehicle?.photoFileName,
                    size: avatarSize,
                    cornerRadius: avatarSize * 0.28,
                    isElectricAccent: selectedVehicle?.fuelType == .electric,
                    symbolColor: compact ? .white : nil,
                    showsSymbolPlate: false,
                    symbolFitsFrame: true
                )
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(compact ? Color.white.opacity(0.9) : shellPalette.tintColor(for: colorScheme))
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 2 : 4)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(L10n.string("recording.vehicle.accessibility"))
        .accessibilityValue(selectedName)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
    }
}

enum RecordingMorphID {
    static let statusChip = "recording.statusChip"
    static let car = "recording.car"
}

/// One-shot labeled popout on the live-map chip when a trip starts.
@MainActor
enum RecordingLiveMapHint {
    static let appearDelay: Duration = .milliseconds(140)
    static let expandedHold: Duration = .milliseconds(3800)

    private static var playedTripIDs: Set<UUID> = []

    static func shouldPlay(for tripID: UUID?) -> Bool {
        guard let tripID else { return true }
        return !playedTripIDs.contains(tripID)
    }

    static func markPlayed(for tripID: UUID?) {
        guard let tripID else { return }
        playedTripIDs.insert(tripID)
    }

    static func resetForTests() {
        playedTripIDs.removeAll()
    }
}

/// Prominent live-map chip: pulse while recording, then a labeled popout after trip start.
private struct RecordingLiveMapOpenButton: View {
    var hintExpanded: Bool
    var isPulsing: Bool
    var onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Button {
            TrailhoundHaptics.selection()
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "map.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .symbolEffect(.bounce, options: .nonRepeating, value: hintExpanded)

                if hintExpanded {
                    HStack(spacing: 4) {
                        Text(L10n.string("recording.live_map.open_hint"))
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .leading))
                    )
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, hintExpanded ? 11 : 9)
            .frame(width: hintExpanded ? nil : 32, height: 32, alignment: .center)
            .background {
                Capsule(style: .continuous)
                    .fill(shellPalette.glassReadabilityTint(for: colorScheme))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        shellPalette.tintColor(for: colorScheme).opacity(hintExpanded ? 0.55 : 0.40),
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
            .animation(reduceMotion ? nil : TrailhoundMotion.liveMapHintPop, value: hintExpanded)
            .shadow(color: Color.black.opacity(0.32), radius: 8, y: 4)
            .shadow(
                color: shellPalette.glowColor(for: colorScheme).opacity(0.55),
                radius: hintExpanded ? 12 : 8,
                y: 2
            )
            .background {
                SoftPulseRing(
                    color: UIColor(shellPalette.tintColor(for: colorScheme)),
                    isActive: isPulsing && !hintExpanded,
                    reduceMotion: reduceMotion
                )
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
            }
        }
        .buttonStyle(LiveMapOpenPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(L10n.string("recording.live_map.open"))
        .accessibilityIdentifier("recording.live_map.open")
    }
}

private struct LiveMapOpenPressStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect((configuration.isPressed && !reduceMotion) ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: configuration.isPressed)
    }
}

/// Pause / Resume / Stop label: glyph and title crossfade as one (no laggy SF replace).
struct RecordingActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    /// Tighter type for the live-follow HUD (~0.75 scale).
    var compact: Bool = false
    /// When false, the glyph and title swap instantly.
    var animatedSymbolSwap: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: compact ? 4 : 6) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(compact ? 0.85 : 1)
            }
            .id(labelIdentity)
            .transition(labelTransition)
        }
        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .animation(shouldAnimate ? TrailhoundMotion.recordingToggle : nil, value: labelIdentity)
    }

    private var labelIdentity: String { "\(systemImage)|\(title)" }

    private var shouldAnimate: Bool {
        animatedSymbolSwap && !reduceMotion
    }

    private var labelTransition: AnyTransition {
        guard shouldAnimate else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.88)),
            removal: .opacity.combined(with: .scale(scale: 1.06))
        )
    }
}

struct ActiveTripView: View {
    var morphNamespace: Namespace.ID?
    var morphID: UUID?
    /// Whole-card fade-in on trip start.
    var playEntranceReveal: Bool = false
    var onEntranceFinished: (() -> Void)?
    var onStop: ((RecordingCardAnchor) -> Void)?
    /// Opens the optional full-screen live follow map (trips list owns presentation).
    var onOpenLiveFollow: ((RecordingCardAnchor) -> Void)?
    /// When false, pauses the road animation while another tab is selected or live map is open.
    var isRecordingCardVisible: Bool = true

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(LocationService.self) private var locationService
    @Environment(\.modelContext) private var modelContext
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.trailhoundLayout) private var screenLayout

    @State private var cardReveal: CGFloat = 1
    @State private var carDriveIn: CGFloat = 1
    @State private var detailsReveal: CGFloat = 1
    @State private var didRunEntrance = false
    @State private var liveMapHintExpanded = false
    @State private var anchorBox = RecordingCardAnchorBox()
    /// Optimistic pause chrome — icon + title stay in lockstep before service work finishes.
    @State private var displayedPaused = false
    /// Decoded thumb for the road scene — injected so TimelineView never hits disk.
    @State private var roadVehiclePhoto: UIImage?
    /// Kept through a turn so the road, stats, and buttons are not rebuilt mid-slide.
    @State private var settledArrangement: RecordingCardArrangement?

    init(
        morphNamespace: Namespace.ID? = nil,
        morphID: UUID? = nil,
        playEntranceReveal: Bool = false,
        onEntranceFinished: (() -> Void)? = nil,
        onStop: ((RecordingCardAnchor) -> Void)? = nil,
        onOpenLiveFollow: ((RecordingCardAnchor) -> Void)? = nil,
        isRecordingCardVisible: Bool = true
    ) {
        self.morphNamespace = morphNamespace
        self.morphID = morphID
        self.playEntranceReveal = playEntranceReveal
        self.onEntranceFinished = onEntranceFinished
        self.onStop = onStop
        self.onOpenLiveFollow = onOpenLiveFollow
        self.isRecordingCardVisible = isRecordingCardVisible
        let settled = !self.playEntranceReveal
        _cardReveal = State(initialValue: settled ? 1 : 0)
        _carDriveIn = State(initialValue: settled ? 1 : 0)
        _detailsReveal = State(initialValue: settled ? 1 : 0)
    }

    private var isPaused: Bool {
        displayedPaused
    }

    private var cardVisible: Bool {
        cardReveal > 0.02
    }

    /// Keep the road clock mounted while the card is on-screen (pause freezes the scene, no view swap).
    private var shouldRunRoadClock: Bool {
        cardVisible && isRecordingCardVisible
    }

    private var recordingVehicle: VehicleProfile? {
        let id = recordingService.activeRecordingVehicleID(from: vehicles)
        guard let id else { return nil }
        return vehicles.first(where: { $0.id == id })
    }

    private var roadPhotoIdentity: String {
        let id = recordingVehicle?.id.uuidString ?? "none"
        let file = recordingVehicle?.photoFileName ?? "none"
        // Epoch forces reload when Observation misses nested SwiftData vehicleID mutations.
        return "\(id)|\(file)|\(recordingService.recordingVehicleEpoch)"
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
    }

    private var urgentServiceDue: VehicleDueItem? {
        guard let vehicleID = recordingService.activeRecordingVehicleID(from: vehicles) else {
            return nil
        }
        return VehicleCareDueCalculator.urgentServiceDue(for: vehicleID, from: schedules)
    }

    var body: some View {
        if recordingService.state.isActiveSession {
            recordingCard
        } else {
            EmptyView()
        }
    }

    private var recordingCard: some View {
        arrangedRecordingStack
        .padding(screenLayout.isPhoneBook ? 10 : 14)
        .frame(
            maxWidth: presentedArrangement == .list ? .infinity : GlassTokens.paneCardMaxWidth,
            alignment: .leading
        )
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            RecordingCardStyle.glassSurface(isPaused: isPaused)
        }
        .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .padding(.horizontal)
        .opacity(cardReveal)
        .offset(y: (1 - cardReveal) * 22)
        .scaleEffect(0.96 + 0.04 * cardReveal, anchor: .top)
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { updateCardAnchor(frame) }
                    .onChange(of: frame.origin.y) { _, _ in updateCardAnchor(frame) }
                    .onChange(of: frame.size.width) { _, _ in updateCardAnchor(frame) }
                    .onChange(of: frame.size.height) { _, _ in updateCardAnchor(frame) }
            }
        }
        .accessibilityElement(children: .combine)
        .modifier(RecordingCardAccessibilityLabel(statusText: statusText))
        .accessibilityHidden(!cardVisible)
        .task(id: morphID) {
            await runEntranceIfNeeded()
            await playLiveMapHintIfNeeded()
        }
        .task(id: roadPhotoIdentity) {
            await loadRoadVehiclePhoto()
        }
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
        .onAppear {
            displayedPaused = recordingService.state == .paused
            if settledArrangement == nil {
                settledArrangement = screenLayout.recordingCardArrangement
            }
        }
        .onChange(of: screenLayout.recordingCardArrangement) { _, newValue in
            guard !TrailhoundInterfaceRotation.shared.isRotating else { return }
            settledArrangement = newValue
        }
        .onChange(of: TrailhoundInterfaceRotation.shared.isRotating) { _, rotating in
            guard !rotating else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                settledArrangement = screenLayout.recordingCardArrangement
            }
        }
        .onChange(of: recordingService.state) { _, newState in
            if newState.isActiveSession {
                applyRecordingPauseChrome(newState == .paused, animate: true)
            } else {
                displayedPaused = false
            }
        }
        .onChange(of: playEntranceReveal) { wasPlaying, shouldPlay in
            guard shouldPlay, !wasPlaying else { return }
            prepareEntranceReplay()
            Task {
                await runEntranceIfNeeded()
                await playLiveMapHintIfNeeded()
            }
        }
    }

    /// During a turn the card keeps the arrangement it started with. The panes
    /// slide around it; swapping the road for a second copy is the ghost.
    private var presentedArrangement: RecordingCardArrangement {
        if TrailhoundInterfaceRotation.shared.isRotating, let settledArrangement {
            return settledArrangement
        }
        return screenLayout.recordingCardArrangement
    }

    private var arrangedRecordingStack: some View {
        let arrangement = presentedArrangement
        // The phone book is only ~400pt tall once the tab bar is in. The Duo road
        // and the 2×2 grid push Pause and Stop under that bar.
        let phoneBook = screenLayout.isPhoneBook
        let compactRoad = phoneBook
            || (screenLayout.layoutClass == .phoneLandscape && !screenLayout.isPhoneBook)
            || arrangement == .list
        let capsRoadHeight = compactRoad || arrangement == .banner
        let actionsBeside = arrangement == .banner
        let reveals = arrangement == .list
        let statsArrangement: ActiveTripStatsArrangement = phoneBook
            ? .strip
            : (arrangement == .pane ? .grid : .inline)
        return HStack(alignment: .center, spacing: actionsBeside ? 16 : 0) {
            VStack(alignment: .leading, spacing: phoneBook ? 8 : 10) {
                statusRow
                roadScene(compact: compactRoad, reportsMorph: arrangement != .pane)
                    .frame(maxWidth: .infinity)
                    .frame(height: capsRoadHeight ? 72 : nil)
                    .opacity(reveals ? detailsReveal : 1)
                    .scaleEffect(reveals ? 0.92 + 0.08 * detailsReveal : 1)
                ActiveTripLiveStats(compact: phoneBook, arrangement: statsArrangement)
                    .opacity(reveals ? detailsReveal : 1)
                    .offset(y: reveals ? (1 - detailsReveal) * 10 : 0)
                if !actionsBeside {
                    actionsRow
                        .opacity(reveals ? detailsReveal : 1)
                        .offset(y: reveals ? (1 - detailsReveal) * 8 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            if actionsBeside {
                actionsRow
                    .frame(maxWidth: 280)
            }
        }
    }

    private func roadScene(compact: Bool, reportsMorph: Bool) -> some View {
        RecordingCarAnimationView(
            compact: compact,
            isAnimating: shouldRunRoadClock,
            isPaused: isPaused,
            driveInProgress: carDriveIn,
            systemImage: VehicleIconOption.default.rawValue,
            vehiclePhoto: roadVehiclePhoto,
            symbolScaleX: -1,
            allowsVerticalBounce: true
        ) { carLayout in
            if let serviceDue = urgentServiceDue {
                RecordingVehicleServiceBadge(
                    carSize: carLayout.carSize,
                    isOverdue: serviceDue.state.isOverdue
                )
                .recordingVehicleServiceBadgePosition(layout: carLayout)
            }
        }
        .matchedGeometryEffectIfAvailable(
            stringID: RecordingMorphID.car,
            namespace: morphNamespace,
            isSource: true
        )
        .matchedGeometryEffectIfAvailable(
            id: morphID,
            namespace: morphNamespace,
            isSource: reportsMorph
        )
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { updateCarAnchor(frame) }
                    .onChange(of: frame.origin.y) { _, _ in updateCarAnchor(frame) }
                    .onChange(of: frame.size.width) { _, _ in updateCarAnchor(frame) }
                    .onChange(of: frame.size.height) { _, _ in updateCarAnchor(frame) }
            }
        }
    }

    private func loadRoadVehiclePhoto() async {
        let fileName = recordingVehicle?.photoFileName
        guard let fileName, !fileName.isEmpty else {
            roadVehiclePhoto = nil
            return
        }
        let image: UIImage?
        if let synced = VehiclePhotoStore.shared.imageSync(fileName: fileName) {
            image = synced
        } else {
            image = await VehiclePhotoStore.shared.image(fileName: fileName)
        }
        guard recordingVehicle?.photoFileName == fileName else { return }
        // Same asset as RecordingVehiclePicker — no backdrop punch (that eats light vehicles).
        roadVehiclePhoto = image
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if onOpenLiveFollow != nil {
                RecordingLiveMapOpenButton(
                    hintExpanded: liveMapHintExpanded,
                    isPulsing: !isPaused && isRecordingCardVisible,
                    onOpen: {
                        liveMapHintExpanded = false
                        RecordingLiveMapHint.markPlayed(for: morphID)
                        onOpenLiveFollow?(anchorBox.value)
                    }
                )
                .layoutPriority(2)
            }

            if !liveMapHintExpanded {
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .contentTransition(.opacity)
                        .symbolEffect(
                            .pulse,
                            options: .repeating,
                            isActive: !isPaused && !reduceMotion && isRecordingCardVisible
                        )
                    Text(statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.opacity)
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.recordingToggle, value: isPaused)
                .layoutPriority(1)
                .modifier(RecordingStatusChipMorphModifier(
                    morphNamespace: morphNamespace
                ))
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.92))
                )
            }

            Spacer(minLength: 4)

            if !vehicles.isEmpty {
                RecordingVehiclePicker(
                    vehicles: vehicles,
                    selectedVehicleID: recordingService.activeRecordingVehicleID(from: vehicles),
                    onSelect: { recordingService.setRecordingVehicle($0) },
                    compact: true
                )
            }

            RecordingLocationChromeRow()
        }
    }

    private var statusText: String {
        isPaused ? L10n.recordingPaused : L10n.recordingStarted
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button(action: togglePlayback) {
                RecordingActionLabel(
                    title: isPaused ? L10n.resume : L10n.pause,
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
            .controlSize(.small)
            .tint(.white)
            .frame(maxWidth: .infinity, minHeight: 34)

            Button(role: .destructive) {
                if let onStop {
                    onStop(anchorBox.value)
                } else {
                    recordingService.stopManualRecording()
                }
            } label: {
                RecordingActionLabel(title: L10n.stop, systemImage: "stop.fill")
            }
            .buttonStyle(
                SoftPressBorderedButtonStyle(
                    reduceMotion: reduceMotion,
                    prominent: true
                )
            )
            .controlSize(.small)
            .tint(GlassSemantic.notificationBadge)
            .frame(maxWidth: .infinity, minHeight: 34)
        }
    }

    /// Writing to the box costs nothing and never invalidates the view, so no threshold is
    /// needed — Stop now sees the card's exact current frame.
    private func updateCardAnchor(_ frame: CGRect) {
        guard frame.width > 0 else { return }
        var next = anchorBox.value
        next.minX = frame.minX
        next.minY = frame.minY
        next.width = frame.width
        next.height = frame.height
        anchorBox.value = next
    }

    private func updateCarAnchor(_ frame: CGRect) {
        guard frame.width > 0 else { return }
        var next = anchorBox.value
        next.carMinX = frame.minX
        next.carMinY = frame.minY
        next.carWidth = frame.width
        next.carHeight = frame.height
        anchorBox.value = next
    }

    @MainActor
    private func prepareEntranceReplay() {
        didRunEntrance = false
        liveMapHintExpanded = false
        guard !reduceMotion else { return }
        cardReveal = 0
        carDriveIn = 0
        detailsReveal = 0
    }

    @MainActor
    private func settleEntrance() {
        cardReveal = 1
        carDriveIn = 1
        detailsReveal = 1
    }

    @MainActor
    private func runEntranceIfNeeded() async {
        guard playEntranceReveal else {
            if !didRunEntrance {
                settleEntrance()
                didRunEntrance = true
            }
            return
        }
        guard !didRunEntrance else { return }
        didRunEntrance = true

        if reduceMotion {
            settleEntrance()
            onEntranceFinished?()
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            cardReveal = 1
        }
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else {
            settleEntrance()
            onEntranceFinished?()
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            carDriveIn = 1
        }
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            settleEntrance()
            onEntranceFinished?()
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            detailsReveal = 1
        }
        try? await Task.sleep(for: .milliseconds(170))
        if Task.isCancelled {
            settleEntrance()
        }
        onEntranceFinished?()
    }

    @MainActor
    private func playLiveMapHintIfNeeded() async {
        guard onOpenLiveFollow != nil else { return }
        guard RecordingLiveMapHint.shouldPlay(for: morphID) else { return }
        RecordingLiveMapHint.markPlayed(for: morphID)

        if reduceMotion {
            liveMapHintExpanded = true
            try? await Task.sleep(for: RecordingLiveMapHint.expandedHold)
            if !Task.isCancelled {
                liveMapHintExpanded = false
            }
            return
        }

        try? await Task.sleep(for: RecordingLiveMapHint.appearDelay)
        guard !Task.isCancelled else { return }
        withAnimation(TrailhoundMotion.liveMapHintPop) {
            liveMapHintExpanded = true
        }
        try? await Task.sleep(for: RecordingLiveMapHint.expandedHold)
        guard !Task.isCancelled else { return }
        withAnimation(TrailhoundMotion.liveMapHintCollapse) {
            liveMapHintExpanded = false
        }
    }

    private var statusIcon: String {
        isPaused ? "pause.circle.fill" : "record.circle.fill"
    }

    private var statusColor: Color {
        isPaused ? .yellow : GlassSemantic.notificationBadge
    }

    private func togglePlayback() {
        let nextPaused = !displayedPaused
        applyRecordingPauseChrome(nextPaused, animate: true)
        if nextPaused {
            recordingService.pauseRecording()
        } else {
            recordingService.resumeRecording()
        }
    }

    private func applyRecordingPauseChrome(_ paused: Bool, animate: Bool) {
        guard paused != displayedPaused else { return }
        if animate, !reduceMotion {
            withAnimation(TrailhoundMotion.recordingToggle) {
                displayedPaused = paused
            }
        } else {
            displayedPaused = paused
        }
    }
}

// MARK: - Subviews (isolate observation)

/// The combined label needs the live counters, but reading them in the card's body made the
/// entire card track the display sampler. A modifier has its own body, so the dependency
/// stays here.
private struct RecordingCardAccessibilityLabel: ViewModifier {
    let statusText: String

    @Environment(TripRecordingService.self) private var recordingService

    func body(content: Content) -> some View {
        content.accessibilityLabel(
            RecordingAccessibility.summary(
                status: statusText,
                elapsed: recordingService.displayElapsedTime,
                speedMps: recordingService.displaySpeedMps,
                distanceMeters: recordingService.displayDistanceMeters
            )
        )
    }
}

private struct RecordingStatusChipMorphModifier: ViewModifier {
    var morphNamespace: Namespace.ID?

    func body(content: Content) -> some View {
        content.matchedGeometryEffectIfAvailable(
            stringID: RecordingMorphID.statusChip,
            namespace: morphNamespace,
            isSource: true
        )
    }
}

/// GPS / permission chrome — throttled so location fixes don't rebuild the whole card.
private struct RecordingLocationChromeRow: View {
    @Environment(LocationService.self) private var locationService
    @State private var displayedGPSQuality: LocationService.GPSQuality = .lost
    @State private var showsAlwaysLocationHint = false

    var body: some View {
        HStack(spacing: 4) {
            if showsAlwaysLocationHint {
                Button {
                    locationService.requestPermission()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.string("recording.location.always_required"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityLabel(L10n.string("recording.location.always_required"))
            }

            GPSQualityBadge(quality: displayedGPSQuality, compact: true)
        }
        .onAppear {
            refreshFromLocationService()
        }
        .task {
            while !Task.isCancelled {
                refreshFromLocationService()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshFromLocationService() {
        let quality = locationService.gpsQuality
        if quality != displayedGPSQuality {
            displayedGPSQuality = quality
        }
        let needsHint = !locationService.canRecordInBackground
        if needsHint != showsAlwaysLocationHint {
            showsAlwaysLocationHint = needsHint
        }
    }
}

/// Live duration / speed / distance — only this subtree tracks display sampler (~4 Hz).
enum ActiveTripStatsArrangement {
    case inline
    /// One row of four metrics. The phone book is too short for the 2×2 grid.
    case strip
    case grid
}

struct ActiveTripLiveStats: View {
    /// Tighter pills for the live-follow HUD (more room for outer padding).
    var compact: Bool = false
    var arrangement: ActiveTripStatsArrangement = .inline

    @Environment(TripRecordingService.self) private var recordingService

    private var speedText: String {
        RecordingAccessibility.speedText(speedMps: recordingService.displaySpeedMps)
    }

    private var elapsedText: String {
        DateFormatters.formatDuration(recordingService.displayElapsedTime)
    }

    private var distanceText: String {
        DateFormatters.formatDistance(recordingService.displayDistanceMeters)
    }

    private var averageText: String {
        let elapsed = recordingService.displayElapsedTime
        guard elapsed > 1 else { return "—" }
        let kmh = recordingService.displayDistanceMeters / elapsed * 3.6
        return L10n.formatSpeedKmh(kmh)
    }

    var body: some View {
        if arrangement == .grid {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                durationPill
                distancePill
                speedPill
                averagePill
            }
        } else {
            HStack(alignment: .top, spacing: compact ? 4 : 6) {
                durationPill
                speedPill
                distancePill
                if arrangement == .strip {
                    averagePill
                }
            }
        }
    }

    private var durationPill: some View {
        statPill(icon: "clock.fill", label: L10n.duration, text: elapsedText)
    }

    private var distancePill: some View {
        statPill(icon: "location.fill", label: L10n.string("label.distance"), text: distanceText)
    }

    private var speedPill: some View {
        statPill(icon: "speedometer", label: L10n.currentSpeed, text: speedText)
    }

    private var averagePill: some View {
        statPill(icon: "gauge.with.dots.needle.33percent", label: L10n.averageSpeed, text: averageText)
    }

    private func statPill(icon: String, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            HStack(spacing: compact ? 2 : 3) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 6 : 9, weight: .semibold))
                Text(label)
                    .font(.system(size: compact ? 7 : 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(.white.opacity(0.75))
            Text(text)
                .font(compact ? .system(size: 10, weight: .bold) : .caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .numericTextAnimation(value: text)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 4 : 7)
        .background(.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(text)")
    }
}

#Preview {
    ActiveTripView(playEntranceReveal: true)
        .environment(PreviewData.shared.recordingService)
        .environment(LocationService())
}
