import SwiftData
import SwiftUI

private enum VehicleScheduleFocusedField: Hashable {
    case title
    case notes

    var previous: VehicleScheduleFocusedField? {
        self == .notes ? .title : nil
    }

    var next: VehicleScheduleFocusedField? {
        self == .title ? .notes : nil
    }
}

struct VehicleScheduleEditorView: View {
    let vehicleID: UUID
    var scheduleID: UUID?
    /// Wide-book trailing pane. Nil keeps the sheet dismiss.
    var onFinish: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]

    @State private var draft: VehicleScheduleEditorDraft?
    @State private var isSaving = false
    @FocusState private var focusedField: VehicleScheduleFocusedField?
    @Namespace private var kmPresetNamespace

    private static let kmPresets = [1_000, 4_000, 6_000, 10_000, 15_000]

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    private var schedule: VehicleSchedule? {
        guard let scheduleID else { return nil }
        return schedules.first { $0.id == scheduleID }
    }

    private var activeDraft: VehicleScheduleEditorDraft {
        draft ?? {
            if let schedule { return VehicleScheduleEditorDraft(from: schedule) }
            return VehicleScheduleEditorDraft()
        }()
    }

    private var focusedFieldTitle: String {
        switch focusedField {
        case .notes:
            return L10n.string("vehicles.care.schedule.notes")
        case .title:
            return L10n.string("vehicles.care.schedule.title")
        case .none:
            return ""
        }
    }

    var body: some View {
        editorChrome
            .dismissKeyboardOnTap(focus: $focusedField)
            .dismissKeyboardOnScroll()
            .fieldKeyboardAccessory(
                title: focusedFieldTitle,
                focusID: focusedField.map { AnyHashable($0) },
                onDone: {
                    focusedField = nil
                    KeyboardDismiss.dismiss()
                }
            )
            .onAppear {
                if draft == nil {
                    var initial = schedule.map(VehicleScheduleEditorDraft.init(from:))
                        ?? VehicleScheduleEditorDraft()
                    if schedule == nil, let current = vehicle?.currentOdometerKm {
                        initial.nextDueOdometerKm = current + initial.intervalKm
                    }
                    draft = initial
                }
            }
            .deleteConfirmHost()
    }

    private var navigationTitleText: String {
        scheduleID == nil
            ? L10n.string("vehicles.care.schedule.add")
            : L10n.string("vehicles.care.schedule.edit")
    }

    @ViewBuilder
    private var editorChrome: some View {
        if onFinish != nil {
            VStack(spacing: 0) {
                VehicleCarePaneEditorBar(
                    title: navigationTitleText,
                    saveDisabled: isSaving,
                    onBack: close,
                    onSave: save
                )
                editorForm
                    .vehicleCareEmbeddedListChrome()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            editorForm
                .glassListChrome()
                .navigationTitle(navigationTitleText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        GlassToolbarBackButton(action: close)
                    }
                    .hideSharedToolbarBackgroundIfAvailable()
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            save()
                        } label: {
                            GlassToolbarSaveButton(title: L10n.pairingTabSave)
                        }
                        .disabled(isSaving)
                    }
                }
        }
    }

    private var editorForm: some View {
        Form {
            Section(L10n.string("vehicles.care.schedule.kind")) {
                LabeledContent(L10n.string("vehicles.care.schedule.kind")) {
                    Picker(L10n.string("vehicles.care.schedule.kind"), selection: draftBinding(\.kind)) {
                        ForEach(VehicleScheduleKind.allCases, id: \.self) { kind in
                            Text(kind.defaultTitle).tag(kind)
                        }
                    }
                    .onChange(of: activeDraft.kind) { _, newKind in
                        guard draft != nil else { return }
                        if draft?.title == VehicleScheduleKind.service.defaultTitle
                            || draft?.title == VehicleScheduleKind.inspection.defaultTitle
                            || draft?.title == VehicleScheduleKind.trafficInsurance.defaultTitle
                            || draft?.title == VehicleScheduleKind.casco.defaultTitle
                            || draft?.title == VehicleScheduleKind.custom.defaultTitle
                            || draft?.title.isEmpty == true {
                            draft?.title = newKind.defaultTitle
                        }
                        let keepsKilometres = draft?.intervalKind == .everyKm || draft?.intervalKind == .whicheverFirst
                        if !keepsKilometres {
                            draft?.intervalMonths = newKind == .inspection ? 24 : 12
                            draft?.intervalKind = newKind == .service ? .everyMonths : .everyYears
                        }
                    }
                    .glassMenuPicker()
                }
                .glassRow(position: .first)

                GlassFieldLabel(title: L10n.string("vehicles.care.schedule.title")) {
                    TextField("", text: draftBinding(\.title))
                        .focused($focusedField, equals: .title)
                }
                .glassRow(position: .middle)

                Toggle(L10n.string("vehicles.care.schedule.enabled"), isOn: draftBinding(\.isEnabled))
                    .glassToggleStyle()
                    .glassRow(position: .last)
            }

            Section(L10n.string("vehicles.care.schedule.due")) {
                if activeDraft.intervalKind != .everyKm {
                    LabeledContent(L10n.string("vehicles.care.schedule.next_due")) {
                        DatePicker(
                            L10n.string("vehicles.care.schedule.next_due"),
                            selection: draftBinding(\.nextDueDate),
                            displayedComponents: .date
                        )
                        .glassDatePicker()
                    }
                    .glassRow(position: .first)
                }

                LabeledContent(L10n.string("vehicles.care.schedule.interval")) {
                    Picker(L10n.string("vehicles.care.schedule.interval"), selection: draftBinding(\.intervalKind)) {
                        ForEach(VehicleScheduleIntervalKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .glassMenuPicker()
                }
                .glassRow(position: activeDraft.intervalKind == .everyKm ? .first : .middle)

                if activeDraft.intervalKind == .everyMonths
                    || activeDraft.intervalKind == .everyYears
                    || activeDraft.intervalKind == .whicheverFirst {
                    Stepper(
                        value: draftBinding(\.intervalMonths),
                        in: 1...60
                    ) {
                        Text("\(activeDraft.intervalMonths) \(L10n.string("vehicles.care.schedule.months"))")
                    }
                    .glassStepper()
                    .glassRow(position: .middle)
                }

                if activeDraft.intervalKind == .everyKm
                    || activeDraft.intervalKind == .whicheverFirst {
                    if vehicle?.currentOdometerKm == nil {
                        Button {
                            close()
                        } label: {
                            Text(L10n.string("vehicles.odometer.missing"))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .buttonStyle(.glassPlainHit)
                        .accessibilityIdentifier("vehicle.care.odometer.prompt")
                        .glassRow(position: .middle)
                    } else if let current = vehicle?.currentOdometerKm {
                        Text(String(
                            format: L10n.string("vehicles.detail.odometer"),
                            VehicleCareDueCalculator.formatKilometers(current)
                        ))
                        .font(.caption)
                        .glassSecondaryInk()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .glassRow(position: .middle)
                    }

                    LabeledContent(L10n.string("vehicles.care.schedule.next_due_km")) {
                        TextField(
                            "",
                            value: draftBinding(\.nextDueOdometerKm),
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .glassInputField()
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("vehicle.care.nextDueKm")
                    }
                    .glassRow(position: .middle)

                    Stepper(
                        value: draftBinding(\.intervalKm),
                        in: 500...50_000,
                        step: 500
                    ) {
                        Text("\(VehicleCareDueCalculator.formatKilometers(activeDraft.intervalKm))")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .glassStepper()
                    .glassRow(position: .middle)

                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassChipGroup(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(Self.kmPresets, id: \.self) { preset in
                                    GlassFilterChip(
                                        title: VehicleCareDueCalculator.formatKilometers(preset),
                                        isSelected: activeDraft.intervalKm == preset,
                                        namespace: kmPresetNamespace,
                                        highlightID: "kmPreset-\(preset)",
                                        size: .compact
                                    ) {
                                        draftBinding(\.intervalKm).wrappedValue = preset
                                    }
                                    .accessibilityIdentifier("vehicle.care.km.preset.\(preset)")
                                }
                            }
                        }
                    }
                    .glassChipScroller()
                    .glassRow(position: .middle)
                }

                GlassFieldLabel(title: L10n.string("vehicles.care.schedule.notes")) {
                    TextField("", text: draftBinding(\.notes), axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .notes)
                }
                .glassRow(position: .last)
            }

            if schedule != nil {
                Section {
                    Button(L10n.delete, role: .destructive) {
                        DeleteConfirmPresenter.shared.confirm(.generic) {
                            deleteSchedule()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .destructiveTint()
                    .glassRow(position: .only)
                }
            }
        }
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<VehicleScheduleEditorDraft, Value>) -> Binding<Value> {
        Binding(
            get: { activeDraft[keyPath: keyPath] },
            set: { newValue in
                var next = activeDraft
                next[keyPath: keyPath] = newValue
                draft = next
            }
        )
    }

    private func save() {
        guard let vehicle else { return }
        isSaving = true
        do {
            if let schedule {
                try activeDraft.apply(to: schedule, in: modelContext)
            } else {
                _ = try activeDraft.insert(for: vehicle, in: modelContext)
            }
            TripNotificationService.requestAuthorizationIfNeeded()
            ToastPresenter.shared.show(.vehicleReminderSaved)
            close()
        } catch {
            AppErrorPresenter.shared.present(error.localizedDescription)
            isSaving = false
        }
    }

    private func close() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func deleteSchedule() {
        guard let schedule else { return }
        if let vehicle = schedule.vehicle {
            VehicleCareNotificationScheduler.cancelAll(for: vehicle.id)
        }
        modelContext.delete(schedule)
        try? modelContext.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: modelContext)
        close()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }
}
