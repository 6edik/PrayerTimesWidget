import Foundation
import Combine

/// Owns the in-memory list of the user's personal notes, and mirrors every
/// change straight through to `PersonalCalendarStore`. A single shared
/// instance is created once by `IslamicCalendarView` and handed to the
/// calendar grid, the day sheet and the "Meine Notizen" overview, so a
/// create/edit/delete performed anywhere updates all three immediately —
/// no app restart, no manual refresh.
///
/// Zakat-due-date entries (`kind == .zakatDueDate`) are a legacy shape from
/// before this feature moved to its own `ZakatDueDateStore` under
/// "Besondere Tage" (see `ZakatDueDateStore.migrateFromPersonalCalendarIfNeeded`).
/// This view model deliberately only ever surfaces `.note` entries — a
/// Zakat entry that somehow survives migration must never reappear in
/// "Meine Notizen" or be editable through the notes form.
@MainActor
final class PersonalCalendarViewModel: ObservableObject {
    @Published private(set) var entries: [PersonalCalendarEntry]

    private let store: PersonalCalendarStore

    init(store: PersonalCalendarStore = PersonalCalendarStore()) {
        self.store = store
        self.entries = store.loadAll()
    }

    private var notes: [PersonalCalendarEntry] {
        entries.filter { $0.kind == .note }
    }

    /// Entries attached to exactly one calendar day, in creation order —
    /// the same list shown in the day sheet.
    func entries(for date: Date) -> [PersonalCalendarEntry] {
        let iso = Self.isoDateString(from: date)
        return notes
            .filter { $0.isoDate == iso }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func hasEntries(for date: Date) -> Bool {
        let iso = Self.isoDateString(from: date)
        return notes.contains { $0.isoDate == iso }
    }

    /// All notes, past and future, sorted chronologically — feeds the
    /// "Meine Notizen" overview.
    var allEntriesSortedByDate: [PersonalCalendarEntry] {
        notes.sorted {
            let lhsKey = $0.isoDate ?? ""
            let rhsKey = $1.isoDate ?? ""
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return $0.createdAt < $1.createdAt
        }
    }

    func save(_ entry: PersonalCalendarEntry) {
        var updated = entry
        updated.updatedAt = Date()
        store.upsert(updated)
        entries = store.loadAll()
    }

    func delete(_ entry: PersonalCalendarEntry) {
        store.delete(id: entry.id)
        entries = store.loadAll()
    }

    nonisolated static func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated static func date(from isoDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: isoDate)
    }
}
