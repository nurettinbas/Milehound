import AppIntents
import SwiftData
import SwiftUI

private enum VehicleNavDestination: Hashable {
    case detail(UUID)
}

struct PairingTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Bindable private var settings = AppSettings.shared
    @Bindable private var tabSelection = TabSelection.shared
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]

    @State private var navigationPath = NavigationPath()
    @State private var showShortcutsAutomationGuide = false
    @State private var shortcutsGuideEntry: ShortcutsWizardEntry = .start
    @Environment(\.milehoundLayout) private var layout
    @State private var focusedVehicleID: UUID?

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if layout.showsPairingVehicleFocus {
                    // The split already paints one atmosphere. A second glow on the list
                    // shifts the color on the leading half. Phone portrait and the closed cover stay one list.
                    MilehoundPaneSplit(
                        leadingFraction: MilehoundLayoutResolver.flatBookLeadingFraction(
                            isPhoneBook: layout.isPhoneBook,
                            layoutClass: layout.layoutClass,
                            isLandscape: layout.isLandscape,
                            hingeFullyOpen: MilehoundHingeMonitor.shared.isFullyOpen,
                            fraction: MilehoundLayoutResolver.flatVehicleListFraction,
                            isPadBook: false
                        )
                    ) {
                        pairingList(paintsAtmosphere: false)
                    } focus: {
                        vehicleFocus
                    }
                } else {
                    pairingList()
                }
            }
                .navigationDestination(for: VehicleNavDestination.self) { destination in
                    switch destination {
                    case .detail(let id):
                        VehicleDetailView(vehicleID: id)
                    }
                }
        }
        .background(Color.clear)
        .onAppear {
            consumePendingCareDeepLink()
        }
        .onChange(of: tabSelection.pendingVehicleCareID) { _, _ in
            consumePendingCareDeepLink()
        }
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: sortedVehicles)
        }
    }

    private var vehiclePhotoPrefetchID: String {
        sortedVehicles
            .map { "\($0.id.uuidString):\($0.photoFileName ?? "")" }
            .joined(separator: "|")
    }

    private var vehicleFocus: some View {
        let vehicle = sortedVehicles.first { $0.id == focusedVehicleID } ?? sortedVehicles.first
        return VStack(alignment: .leading, spacing: 8) {
            if let vehicle {
                HStack(alignment: .center, spacing: 16) {
                    VehicleAvatarView(
                        systemImage: vehicle.systemImage,
                        photoFileName: vehicle.photoFileName,
                        size: 96,
                        cornerRadius: 18,
                        showsBrandRing: true,
                        symbolFitsFrame: true,
                        showsPhotoShine: vehicle.photoFileName != nil
                    )
                    MilehoundHeroRail(collapsed: false) {
                        if vehicle.isDefault {
                            Text(L10n.pairingTabDefaultVehicle)
                        }
                    } figure: {
                        Text(vehicle.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } detail: {
                        Text(fuelSubtitle(vehicle))
                    }
                }
                Button(L10n.string("vehicles.care.detail.title")) {
                    navigationPath.append(VehicleNavDestination.detail(vehicle.id))
                }
                .milehoundProminentButton()
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pairingList(paintsAtmosphere: Bool = true) -> some View {
        List {
            Section {
                PairingShortcutsAutomationCard(
                    onOpenGuide: { openShortcutsGuide(.start) },
                    onOpenTest: { openShortcutsGuide(.test) },
                    onOpenTroubleshoot: { openShortcutsGuide(.checklist) }
                )
                .glassListRow()
            }

            if locationService.authorizationState != .authorizedAlways {
                Section {
                    LocationAlwaysRequiredBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            if sortedVehicles.isEmpty {
                Section {
                    PairingEmptyState {
                        addFirstVehicle()
                    }
                    .glassListRow()
                }
            } else {
                Section(sortedVehicles.count == 1 ? L10n.pairingTabVehicleSection : L10n.pairingTabSavedVehicles) {
                    let rowCount = sortedVehicles.count + 1
                    addVehicleButton
                        .glassRow(position: .first)

                    ForEach(Array(sortedVehicles.enumerated()), id: \.element.id) { index, vehicle in
                        vehicleRow(vehicle)
                            .confirmingDeleteSwipe(
                                .vehicle(isActivePaired: vehicle.isDefault)
                            ) {
                                deleteVehicle(vehicle.id)
                            }
                            .glassRow(position: GlassRowPosition.index(index + 1, in: rowCount))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .glassListChrome(showsAtmosphere: paintsAtmosphere)
        .navigationTitle(L10n.string("vehicles.tab.title"))
        .navigationBarTitleDisplayMode(.inline)
        .milehoundShellToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LocationPermissionBadge(state: locationService.authorizationState)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .hideSharedToolbarBackgroundIfAvailable()
        }
        .sheet(isPresented: $showShortcutsAutomationGuide) {
            PairingShortcutsAutomationGuideView(entry: shortcutsGuideEntry)
        }
    }

    private var addVehicleButton: some View {
        Button(action: addVehiclePrompt) {
            Label(L10n.pairingTabAddVehicle, systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .glassPrimaryInk()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassPlainHit)
    }

    private func vehicleRow(_ vehicle: VehicleProfile) -> some View {
        let urgent = urgentCareItem(for: vehicle)
        return PairingVehicleRow(
            vehicle: vehicle,
            subtitle: fuelSubtitle(vehicle),
            careTitle: urgent?.title,
            careSystemImage: urgent?.kind.systemImage,
            dueState: urgent?.state,
            scheduleID: urgent?.scheduleID,
            onOpen: { openDetail(for: vehicle.id) }
        )
    }

    private func urgentCareItem(for vehicle: VehicleProfile) -> VehicleDueItem? {
        let vehicleSchedules = schedules.filter { $0.vehicle?.id == vehicle.id && $0.isEnabled }
        return VehicleCareDueCalculator.dueItems(from: vehicleSchedules, urgentOnly: true).first
    }

    private func fuelSubtitle(_ vehicle: VehicleProfile) -> String {
        let consumption = String(format: "%.1f %@", vehicle.consumption, vehicle.consumptionLabel)
        return [vehicle.fuelType.displayName, consumption].joined(separator: " · ")
    }

    private func suggestedVehicleName() -> String {
        let base = L10n.vehicleDefaultName
        let existing = Set(vehicles.map(\.name))
        if !existing.contains(base) { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func openDetail(for vehicleID: UUID) {
        Task { @MainActor in
            await Task.yield()
            navigationPath.append(VehicleNavDestination.detail(vehicleID))
        }
    }

    private func openShortcutsGuide(_ entry: ShortcutsWizardEntry) {
        shortcutsGuideEntry = entry
        showShortcutsAutomationGuide = true
    }

    private func consumePendingCareDeepLink() {
        guard let vehicleID = tabSelection.consumePendingVehicleCareID() else { return }
        openDetail(for: vehicleID)
    }

    private func addFirstVehicle() {
        let vehicle = VehicleProfile(
            name: suggestedVehicleName(),
            consumption: settings.fuelLitersPer100km
        )
        modelContext.insert(vehicle)
        guard (try? modelContext.save()) != nil else { return }
        VehiclePairingService.setDefaultVehicle(vehicle, in: modelContext)
        settings.skipCarSetup()
        openDetail(for: vehicle.id)
    }

    private func addVehiclePrompt() {
        let vehicle = VehicleProfile(
            name: suggestedVehicleName(),
            consumption: settings.fuelLitersPer100km
        )
        modelContext.insert(vehicle)
        guard (try? modelContext.save()) != nil else { return }
        if !UITestSupport.shouldSkipExternalEffects {
            MilehoundShortcuts.updateAppShortcutParameters()
        }
        openDetail(for: vehicle.id)
    }

    private func deleteVehicle(_ vehicleID: UUID) {
        guard let vehicle = vehicles.first(where: { $0.id == vehicleID }) else { return }

        if !navigationPath.isEmpty {
            navigationPath = NavigationPath()
        }

        if VehiclePairingService.deleteVehicle(vehicle, in: modelContext) {
            ToastPresenter.shared.show(.deleted)
        }
    }
}

#Preview {
    PairingTabView()
        .modelContainer(PreviewData.shared.container)
        .environment(LocationService())
        .environment(PreviewData.shared.recordingService)
}
