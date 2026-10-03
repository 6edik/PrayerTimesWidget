import SwiftUI

/// Add/edit form for a single personal note. The Zakat-due-date feature
/// lives entirely separately now, in the "Zakat-Stichtag" section at the
/// bottom of "Besondere Tage" (`IslamicHolidayOverviewSheet`) — this form
/// can only ever create or edit a plain `.note` entry.
struct PersonalCalendarEntryFormView: View {
    enum Mode {
        case create(date: Date)
        case edit(PersonalCalendarEntry)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PersonalCalendarViewModel
    let mode: Mode

    @State private var note: String
    @State private var showValidationError = false

    init(viewModel: PersonalCalendarViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode

        switch mode {
        case .create:
            _note = State(initialValue: "")
        case .edit(let entry):
            _note = State(initialValue: entry.note)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notiz") {
                    TextEditor(text: $note)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Notiz")
                }

                if showValidationError {
                    Section {
                        Label("Bitte gib eine Notiz ein.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(isEditing ? "Notiz bearbeiten" : "Notiz hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else {
            showValidationError = true
            return
        }

        let entry: PersonalCalendarEntry
        switch mode {
        case .create(let contextDate):
            entry = PersonalCalendarEntry(
                note: trimmedNote,
                isoDate: PersonalCalendarViewModel.isoDateString(from: contextDate)
            )
        case .edit(let existing):
            var updated = existing
            updated.note = trimmedNote
            entry = updated
        }

        viewModel.save(entry)
        dismiss()
    }
}
