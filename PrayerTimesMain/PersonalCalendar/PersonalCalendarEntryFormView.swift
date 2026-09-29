import SwiftUI

/// Add/edit form for a single personal note, or a Zakat-due-date rule.
///
/// A Zakat entry always recurs every Hijri year — a fixed business
/// decision, not a user-facing toggle: there is no one-time Zakat entry
/// and no option to repeat by a fixed Gregorian date instead. The user
/// sets only the Hijri day and month; the app never computes this from a
/// payment date, a wealth amount, or prayer times, and never claims to
/// determine a binding religious due date — a computed Umm-al-Qura
/// mapping can differ from a local moon sighting. This is purely a
/// personal reminder.
struct PersonalCalendarEntryFormView: View {
    enum Mode {
        case create(date: Date)
        case edit(PersonalCalendarEntry)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PersonalCalendarViewModel
    let mode: Mode

    @State private var note: String
    @State private var isZakatDueDate: Bool
    @State private var hijriDay: Int
    @State private var hijriMonth: Int
    @State private var showValidationError = false

    private let hijriCalendar = HijriDateFormatting.calendar()

    init(viewModel: PersonalCalendarViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode

        let hijriCalendar = HijriDateFormatting.calendar()

        switch mode {
        case .create(let initialDate):
            _note = State(initialValue: "")
            _isZakatDueDate = State(initialValue: false)
            let comps = hijriCalendar.dateComponents([.day, .month], from: initialDate)
            _hijriDay = State(initialValue: comps.day ?? 1)
            _hijriMonth = State(initialValue: comps.month ?? 1)

        case .edit(let entry):
            _note = State(initialValue: entry.note)
            _isZakatDueDate = State(initialValue: entry.kind == .zakatDueDate)
            _hijriDay = State(initialValue: entry.hijriDay ?? 1)
            _hijriMonth = State(initialValue: entry.hijriMonth ?? 1)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var nextOccurrencePreview: Date? {
        ZakatOccurrenceCalculator.nextOccurrence(hijriDay: hijriDay, hijriMonth: hijriMonth, hijriCalendar: hijriCalendar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notiz") {
                    TextEditor(text: $note)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Notiz")
                }

                Section {
                    Toggle("Zakat-Stichtag", isOn: zakatToggleBinding)
                        .accessibilityHint("Markiert diesen Eintrag als persönliche Zakat-Erinnerung, keine Berechnung")
                } footer: {
                    Text("Nur eine persönliche Erinnerung an einen von dir gewählten Hijri-Tag — die App berechnet oder prüft keine Zakat.")
                }

                if isZakatDueDate {
                    Section {
                        Picker("Hijri-Monat", selection: $hijriMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(HijriDateFormatting.monthName(month)).tag(month)
                            }
                        }

                        Picker("Hijri-Tag", selection: $hijriDay) {
                            ForEach(1...30, id: \.self) { day in
                                Text("\(day).").tag(day)
                            }
                        }
                    } header: {
                        Text("Hijri-Stichtag")
                    } footer: {
                        Text("Wiederholt sich jedes Hijri-Jahr an diesem Tag — nicht an einem festen gregorianischen Datum.")
                    }

                    Section("Nächster Termin") {
                        if let preview = nextOccurrencePreview {
                            HStack {
                                Text("Gregorianisch")
                                Spacer()
                                Text(formattedGregorian(preview))
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Hijri")
                                Spacer()
                                Text(HijriDateFormatting.displayText(for: preview))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Für dieses Datum kann derzeit kein Termin berechnet werden.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if hijriDay >= 30 {
                        Section {
                            Text("Der 30. Tag existiert nicht in jedem Hijri-Monat. Fällt er in einem Jahr aus (der Monat hat dann nur 29 Tage), wird für dieses eine Jahr keine Erinnerung geplant — es wird kein anderer Tag automatisch eingesetzt.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Section {
                        Text("Die berechnete Umm-al-Qura-Zuordnung kann von einer lokalen Mondsichtung abweichen. Die App prüft keine verbindliche religiöse Fälligkeit — nur deine persönliche Erinnerung.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // Pre-fills a neutral placeholder note only when turning the toggle on
    // with an empty note — never overwrites text the user already typed,
    // and turning it back off leaves whatever text is currently there.
    private var zakatToggleBinding: Binding<Bool> {
        Binding(
            get: { isZakatDueDate },
            set: { newValue in
                isZakatDueDate = newValue
                if newValue, note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    note = "Zakat-Stichtag"
                }
            }
        )
    }

    private func formattedGregorian(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else {
            showValidationError = true
            return
        }

        let entry: PersonalCalendarEntry

        if isZakatDueDate {
            let id: UUID
            let createdAt: Date
            switch mode {
            case .create:
                id = UUID()
                createdAt = Date()
            case .edit(let existing):
                id = existing.id
                createdAt = existing.createdAt
            }

            entry = PersonalCalendarEntry(
                id: id,
                note: trimmedNote,
                kind: .zakatDueDate,
                hijriDay: hijriDay,
                hijriMonth: hijriMonth,
                createdAt: createdAt
            )
        } else {
            switch mode {
            case .create(let contextDate):
                entry = PersonalCalendarEntry(
                    note: trimmedNote,
                    isoDate: PersonalCalendarViewModel.isoDateString(from: contextDate)
                )
            case .edit(let existing):
                var updated = existing
                updated.note = trimmedNote
                updated.kind = .note
                // Converting a Zakat entry back into a plain note has no
                // original Gregorian day to fall back to (it never stored
                // one) — defaults to today rather than inventing one from
                // the Hijri rule.
                updated.isoDate = existing.isoDate ?? PersonalCalendarViewModel.isoDateString(from: Date())
                updated.hijriDay = nil
                updated.hijriMonth = nil
                entry = updated
            }
        }

        viewModel.save(entry)
        dismiss()
    }
}
