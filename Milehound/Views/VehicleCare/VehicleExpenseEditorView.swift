import SwiftData
import SwiftUI

private enum VehicleExpenseFocusedField: Hashable {
    case amount
    case note

    var previous: VehicleExpenseFocusedField? {
        self == .note ? .amount : nil
    }

    var next: VehicleExpenseFocusedField? {
        self == .amount ? .note : nil
    }
}

struct VehicleExpenseEditorView: View {
    let vehicleID: UUID
    var expenseID: UUID?
    var prefillCategory: VehicleExpenseCategory = .fuel
    /// When set, save completes this schedule (tracking Mark done) instead of a plain expense insert.
    var completeScheduleID: UUID?
    /// Wide-book trailing pane. Nil keeps the sheet dismiss.
    var onFinish: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Bindable private var settings = AppSettings.shared
    @Query private var vehicles: [VehicleProfile]
    @Query private var expenses: [VehicleExpense]
    @Query private var schedules: [VehicleSchedule]

    @State private var draft: VehicleExpenseEditorDraft?
    @State private var isSaving = false
    @State private var didSave = false
    @State private var isReceiptSourcePresented = false
    @State private var isReceiptViewerPresented = false
    @State private var isReceiptScanPresented = false
    @State private var isImportingReceipt = false
    @FocusState private var focusedField: VehicleExpenseFocusedField?

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    private var expense: VehicleExpense? {
        guard let expenseID else { return nil }
        return expenses.first { $0.id == expenseID }
    }

    private var completeSchedule: VehicleSchedule? {
        guard let completeScheduleID else { return nil }
        return schedules.first { $0.id == completeScheduleID }
    }

    private var isCompletingSchedule: Bool { completeSchedule != nil }

    private var activeDraft: VehicleExpenseEditorDraft {
        draft ?? VehicleExpenseEditorDraft(category: prefillCategory)
    }

    private var focusedFieldTitle: String {
        switch focusedField {
        case .note:
            return L10n.string("vehicles.care.expense.note")
        case .amount:
            return amountFieldTitle
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
                    if let expense {
                        let siblings = VehicleExpenseInstallmentService.siblings(of: expense, in: modelContext)
                        draft = VehicleExpenseEditorDraft(from: expense, siblings: siblings)
                    } else if let schedule = completeSchedule {
                        draft = VehicleExpenseEditorDraft(category: .suggested(for: schedule.kind))
                    } else {
                        draft = VehicleExpenseEditorDraft(category: prefillCategory)
                    }
                }
            }
            .onDisappear {
                // A full-screen cover hides the form without closing it.
                guard !isReceiptViewerPresented else { return }
                discardUnsavedReceipt()
            }
            .sheet(isPresented: $isReceiptSourcePresented) {
                VehiclePhotoFlowSheet(
                    copy: .receipt,
                    onPicked: { image in
                        isReceiptSourcePresented = false
                        importReceipt(image)
                    },
                    onCancel: {
                        isReceiptSourcePresented = false
                    }
                )
            }
            .sheet(isPresented: $isReceiptScanPresented) {
                if let fileName = activeDraft.receiptFileName {
                    ExpenseReceiptScanSheet(
                        fileName: fileName,
                        onUse: { wholeUnits in
                            var next = activeDraft
                            next.applyScannedAmount(wholeUnits)
                            draft = next
                            isReceiptScanPresented = false
                        },
                        onDismiss: {
                            isReceiptScanPresented = false
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $isReceiptViewerPresented) {
                if let fileName = activeDraft.receiptFileName {
                    ExpenseReceiptViewer(fileName: fileName) {
                        isReceiptViewerPresented = false
                    }
                }
            }
            .deleteConfirmHost()
    }

    private var saveDisabled: Bool {
        isSaving || activeDraft.amount == nil
    }

    @ViewBuilder
    private var editorChrome: some View {
        if onFinish != nil {
            VStack(spacing: 0) {
                VehicleCarePaneEditorBar(
                    title: navigationTitle,
                    saveDisabled: saveDisabled,
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
                .navigationTitle(navigationTitle)
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
                        .disabled(saveDisabled)
                        .accessibilityIdentifier("expense.save")
                    }
                }
        }
    }

    private var editorForm: some View {
        Form {
            Section {
                if isCompletingSchedule, let schedule = completeSchedule {
                    LabeledContent(L10n.string("vehicles.care.schedule.title")) {
                        Text(schedule.title)
                            .glassSecondaryInk()
                    }
                    .glassRow(position: .first)
                } else {
                    LabeledContent(L10n.string("vehicles.care.expense.category")) {
                        Picker(L10n.string("vehicles.care.expense.category"), selection: draftBinding(\.category)) {
                            ForEach(VehicleExpenseCategory.allCases, id: \.self) { category in
                                Label(category.displayName, systemImage: category.systemImage)
                                    .tag(category)
                                    .accessibilityIdentifier("expense.category.\(category.rawValue)")
                            }
                        }
                        .glassMenuPicker()
                        .accessibilityIdentifier("expense.category")
                    }
                    .glassRow(position: .first)
                }

                GlassFieldLabel(title: amountFieldTitle) {
                    HStack {
                        TextField("", text: draftBinding(\.amountText))
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .amount)
                            .accessibilityIdentifier("expense.amount")
                        Text(settings.fuelCurrency.symbol)
                            .glassSecondaryInk()
                    }
                }
                .glassRow(position: .middle)

                Stepper(
                    value: draftBinding(\.installmentCount),
                    in: VehicleExpenseInstallmentPlan.minCount...VehicleExpenseInstallmentPlan.maxCount
                ) {
                    Text(installmentStepperLabel)
                }
                .glassStepper()
                .glassRow(position: .middle)

                if activeDraft.isInstallmentPlan, let preview = installmentPreviewText {
                    Text(preview)
                        .font(.footnote)
                        .glassSecondaryInk()
                        .glassRow(position: .middle)
                }

                LabeledContent(dateFieldTitle) {
                    DatePicker(
                        dateFieldTitle,
                        selection: draftBinding(\.occurredAt),
                        displayedComponents: .date
                    )
                    .glassDatePicker()
                }
                .glassRow(position: .middle)

                GlassFieldLabel(title: L10n.string("vehicles.care.expense.note")) {
                    TextField("", text: draftBinding(\.note), axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .note)
                }
                .glassRow(position: .last)
            } header: {
                Text(
                    isCompletingSchedule
                        ? L10n.string("vehicles.care.complete")
                        : L10n.string("vehicles.care.expense.section")
                )
            } footer: {
                if activeDraft.isInstallmentPlan {
                    Text(
                        expense?.isInstallment == true
                            ? L10n.string("vehicles.care.expense.installments.edit_footer")
                            : L10n.string("vehicles.care.expense.installments.preview_footer")
                    )
                }
            }

            ExpenseReceiptSection(
                fileName: activeDraft.receiptFileName,
                isImporting: isImportingReceipt,
                onAdd: {
                    focusedField = nil
                    isReceiptSourcePresented = true
                },
                onView: {
                    focusedField = nil
                    isReceiptViewerPresented = true
                },
                onScan: {
                    focusedField = nil
                    isReceiptScanPresented = true
                },
                onRemove: removeReceipt
            )

            if expense != nil {
                Section {
                    if expense?.isInstallment == true {
                        Button(L10n.string("vehicles.care.expense.delete_this"), role: .destructive) {
                            DeleteConfirmPresenter.shared.confirm(.generic) {
                                deleteThisInstallment()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .destructiveTint()
                        .glassRow(position: .first)

                        Button(deletePlanLabel, role: .destructive) {
                            let count = expense?.installmentCount ?? activeDraft.installmentCount
                            DeleteConfirmPresenter.shared.confirm(.installmentPlan(count: count)) {
                                deletePlan()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .destructiveTint()
                        .glassRow(position: .last)
                    } else {
                        Button(L10n.delete, role: .destructive) {
                            DeleteConfirmPresenter.shared.confirm(.generic) {
                                deleteExpense()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .destructiveTint()
                        .glassRow(position: .only)
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        if isCompletingSchedule {
            return L10n.string("vehicles.care.complete")
        }
        return expenseID == nil
            ? L10n.string("vehicles.care.expense.add")
            : L10n.string("vehicles.care.expense.edit")
    }

    private var amountFieldTitle: String {
        activeDraft.isInstallmentPlan
            ? L10n.string("vehicles.care.expense.total")
            : L10n.string("vehicles.care.expense.amount")
    }

    private var dateFieldTitle: String {
        activeDraft.isInstallmentPlan
            ? L10n.string("vehicles.care.expense.first_payment")
            : L10n.string("vehicles.care.expense.date")
    }

    private var installmentStepperLabel: String {
        if activeDraft.installmentCount <= 1 {
            return L10n.string("vehicles.care.expense.installments.one")
        }
        return String(
            format: L10n.string("vehicles.care.expense.installments.count"),
            activeDraft.installmentCount
        )
    }

    private var deletePlanLabel: String {
        let count = expense?.installmentCount ?? activeDraft.installmentCount
        return String(format: L10n.string("vehicles.care.expense.delete_plan"), count)
    }

    private var installmentPreviewText: String? {
        guard let amount = activeDraft.amount, activeDraft.installmentCount > 1 else { return nil }
        let slices = VehicleExpenseInstallmentPlan.slices(
            total: amount,
            count: activeDraft.installmentCount,
            start: activeDraft.occurredAt
        )
        guard let first = slices.first, let last = slices.last else { return nil }
        let monthly = String(format: "%.2f %@", first.amount, settings.fuelCurrency.symbol)
        let start = DateFormatters.monthYear.string(from: first.dueDate)
        let end = DateFormatters.monthYear.string(from: last.dueDate)
        return String(
            format: L10n.string("vehicles.care.expense.installments.preview"),
            slices.count,
            monthly,
            start,
            end
        )
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<VehicleExpenseEditorDraft, Value>) -> Binding<Value> {
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
            if let expense {
                try activeDraft.apply(to: expense, in: modelContext)
            } else if let schedule = completeSchedule, let amount = activeDraft.amount {
                _ = try VehicleScheduleCompletionService.complete(
                    schedule: schedule,
                    amount: amount,
                    occurredAt: activeDraft.occurredAt,
                    installmentCount: activeDraft.installmentCount,
                    note: activeDraft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : activeDraft.note.trimmingCharacters(in: .whitespacesAndNewlines),
                    receiptFileName: activeDraft.receiptFileName,
                    in: modelContext
                )
            } else {
                _ = try activeDraft.insert(for: vehicle, in: modelContext)
            }
            didSave = true
            ExpenseReceiptStore.shared.removeIfUnreferenced(
                fileName: activeDraft.receiptToDeleteAfterSave,
                in: modelContext
            )
            ToastPresenter.shared.show(.vehicleExpenseSaved)
            TripStore.syncWidgetWeekDistance(in: modelContext)
            close()
        } catch {
            AppErrorPresenter.shared.present(
                error as? VehicleCareError == .invalidAmount
                    ? L10n.string("vehicles.care.expense.invalid_amount")
                    : error.localizedDescription
            )
            isSaving = false
        }
    }

    private func importReceipt(_ image: UIImage) {
        isImportingReceipt = true
        Task { @MainActor in
            defer { isImportingReceipt = false }
            do {
                let fileName = try await ExpenseReceiptStore.shared.save(image)
                var next = activeDraft
                let orphan = next.attachReceipt(fileName)
                draft = next
                if let orphan {
                    ExpenseReceiptStore.shared.remove(fileName: orphan)
                }
            } catch {
                AppErrorPresenter.shared.present(L10n.string("vehicles.care.expense.receipt.save_failed"))
            }
        }
    }

    private func removeReceipt() {
        var next = activeDraft
        let orphan = next.removeReceipt()
        draft = next
        if let orphan {
            ExpenseReceiptStore.shared.remove(fileName: orphan)
        }
    }

    /// New receipt picked in this form, then the form closed without Save.
    private func discardUnsavedReceipt() {
        guard !didSave, let orphan = activeDraft.receiptToDeleteOnCancel else { return }
        ExpenseReceiptStore.shared.removeIfUnreferenced(fileName: orphan, in: modelContext)
        var next = activeDraft
        _ = next.removeReceipt()
        draft = next
    }

    private func deleteExpense() {
        guard let expense else { return }
        discardUnsavedReceipt()
        VehicleExpenseInstallmentService.deleteOne(expense, in: modelContext)
        TripStore.syncWidgetWeekDistance(in: modelContext)
        close()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }

    private func close() {
        discardUnsavedReceipt()
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func deleteThisInstallment() {
        deleteExpense()
    }

    private func deletePlan() {
        guard let expense else { return }
        discardUnsavedReceipt()
        VehicleExpenseInstallmentService.deleteGroup(of: expense, in: modelContext)
        TripStore.syncWidgetWeekDistance(in: modelContext)
        close()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }
}
