import SwiftData
import SwiftUI

struct TravelJournalEditorDraft: Identifiable {
    var id: UUID
    var title: String
    var note: String
    var selectedTripIDs: Set<UUID>
    var existing: TravelJournal?

    static func create(preselectedTripIDs: Set<UUID> = []) -> TravelJournalEditorDraft {
        TravelJournalEditorDraft(
            id: UUID(),
            title: "",
            note: "",
            selectedTripIDs: preselectedTripIDs,
            existing: nil
        )
    }

    static func edit(_ journal: TravelJournal) -> TravelJournalEditorDraft {
        TravelJournalEditorDraft(
            id: journal.id,
            title: journal.title,
            note: journal.note ?? "",
            selectedTripIDs: Set(journal.trips.map(\.id)),
            existing: journal
        )
    }
}

private enum TravelJournalEditorFocusedField: Hashable {
    case title
    case note
}

struct TravelJournalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Trip> { $0.endedAt != nil }, sort: \Trip.startedAt, order: .reverse)
    private var completedTrips: [Trip]

    @State var draft: TravelJournalEditorDraft
    @FocusState private var focusedField: TravelJournalEditorFocusedField?

    private var focusedFieldTitle: String {
        switch focusedField {
        case .title:
            return L10n.journalTitle
        case .note:
            return L10n.journalNote
        case .none:
            return ""
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.journalTitle)
                            .font(.caption.weight(.semibold))
                            .glassSecondaryInk()
                        TextField(L10n.journalTitlePlaceholder, text: $draft.title)
                            .glassInputField()
                            .focused($focusedField, equals: .title)
                            .submitLabel(.done)
                            .onSubmit { dismissEditorKeyboard() }
                    }
                    .glassListRow()
                }
                .listSectionSpacing(8)

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.journalNote)
                            .font(.caption.weight(.semibold))
                            .glassSecondaryInk()
                        TextField(L10n.journalNotePlaceholder, text: $draft.note, axis: .vertical)
                            .lineLimit(2...4)
                            .glassInputField()
                            .focused($focusedField, equals: .note)
                            .submitLabel(.done)
                            .onSubmit { dismissEditorKeyboard() }
                    }
                    .glassListRow()
                }

                Section(L10n.journalTrips) {
                    ForEach(selectableTrips, id: \.id) { trip in
                        let isSelected = draft.selectedTripIDs.contains(trip.id)
                        Button {
                            toggle(trip.id)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 23, weight: .semibold))
                                    .foregroundStyle(
                                        isSelected
                                            ? Color.primary
                                            : Color.secondary
                                    )
                                    .symbolEffect(
                                        .bounce,
                                        options: .nonRepeating,
                                        value: reduceMotion ? false : isSelected
                                    )
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(TripListViewModel.routeSummary(for: trip))
                                        .font(.caption.weight(.semibold))
                                        .glassPrimaryInk()
                                        .lineLimit(2)
                                    Text(TripListViewModel.dateText(for: trip))
                                        .font(.caption2)
                                        .glassSecondaryInk()
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.glassPlainHit)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .glassListRow()
                    }
                }
            }
            .glassListChrome()
            .dismissKeyboardOnTap(focus: $focusedField)
            .dismissKeyboardOnScroll()
            .fieldKeyboardAccessory(
                title: focusedFieldTitle,
                focusID: focusedField.map { AnyHashable($0) },
                onDone: { dismissEditorKeyboard() }
            )
            .navigationTitle(draft.existing == nil ? L10n.journalNew : L10n.journalTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        GlassToolbarTitle(title: L10n.cancel)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        GlassToolbarTitle(title: L10n.journalSave)
                    }
                }
            }
        }
        .presentationBackground {
            AtmosphericBackground(style: .full)
        }
        .toastHost()
        .deleteConfirmHost()
    }

    private var selectableTrips: [Trip] {
        let trips = completedTrips.filter { trip in
            trip.journalID == nil || trip.journalID == draft.existing?.id || draft.selectedTripIDs.contains(trip.id)
        }
        // Query is already newest-first; keep that order inside each group.
        let selected = trips.filter { draft.selectedTripIDs.contains($0.id) }
        let unselected = trips.filter { !draft.selectedTripIDs.contains($0.id) }
        return selected + unselected
    }

    private func dismissEditorKeyboard() {
        focusedField = nil
        KeyboardDismiss.dismiss()
    }

    private func toggle(_ id: UUID) {
        MilehoundHaptics.selection()
        if draft.selectedTripIDs.contains(id) {
            draft.selectedTripIDs.remove(id)
        } else {
            draft.selectedTripIDs.insert(id)
        }
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            ToastPresenter.shared.show(.journalTitleRequired)
            return
        }
        let journal: TravelJournal
        if let existing = draft.existing {
            journal = existing
            journal.title = title
            journal.note = draft.note.isEmpty ? nil : draft.note
        } else {
            journal = TravelJournal(id: draft.id, title: title, note: draft.note.isEmpty ? nil : draft.note)
            modelContext.insert(journal)
        }

        let members = completedTrips.filter { draft.selectedTripIDs.contains($0.id) }
        let currentMembers = journal.trips
        for trip in currentMembers where !draft.selectedTripIDs.contains(trip.id) {
            TravelJournalTotals.assign(trip: trip, to: nil, in: modelContext)
        }
        for trip in members {
            TravelJournalTotals.assign(trip: trip, to: journal, in: modelContext)
        }
        TravelJournalTotals.refresh(journal)
        try? modelContext.save()
        ToastPresenter.shared.show(.journalSaved)
        dismiss()
    }
}
