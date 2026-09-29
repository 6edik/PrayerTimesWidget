import Foundation
import Combine

/// Owns the in-memory list of the user's personal notes and Zakat-due-date
/// entries, and mirrors every change straight through to
/// `PersonalCalendarStore`. A single shared instance is created once by
/// `IslamicCalendarView` and handed to the calendar grid, the day sheet
/// and the "Meine Notizen" overview, so a create/edit/delete performed
/// anywhere updates all three immediately — no app restart, no manual
/// refresh.
@MainActor
final class PersonalCalendarViewModel: ObservableObject {
    @Published private(set) var entries: [PersonalCalendarEntry]

    private let store: PersonalCalendarStore
    private let hijriCalendar: Calendar

    init(store: PersonalCalendarStore = PersonalCalendarStore()) {
        self.store = store
        self.entries = store.loadAll()
        self.hijriCalendar = HijriDateFormatting.calendar()
    }

    /// Entries attached to exactly one calendar day, in creation order —
    /// the same list shown in the day sheet. A plain note matches by its
    /// stored `isoDate`; a Zakat entry matches whenever `date`'s own
    /// Hijri (day, month) equals the entry's fixed rule — so it reappears
    /// every matching Hijri year the user navigates to, past or future,
    /// never just a single cached date.
    func entries(for date: Date) -> [PersonalCalendarEntry] {
        let iso = Self.isoDateString(from: date)
        return entries
            .filter { matches($0, date: date, iso: iso) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func hasEntries(for date: Date) -> Bool {
        let iso = Self.isoDateString(from: date)
        return entries.contains { matches($0, date: date, iso: iso) }
    }

    private func matches(_ entry: PersonalCalendarEntry, date: Date, iso: String) -> Bool {
        switch entry.kind {
        case .note:
            return entry.isoDate == iso
        case .zakatDueDate:
            guard let day = entry.hijriDay, let month = entry.hijriMonth else { return false }
            return ZakatOccurrenceCalculator.matches(hijriDay: day, hijriMonth: month, date: date, hijriCalendar: hijriCalendar)
        }
    }

    /// All entries, past and future, sorted chronologically — feeds the
    /// "Meine Notizen" overview. A plain note sorts by its `isoDate`; a
    /// Zakat entry sorts by its current representative occurrence (this
    /// Hijri year's date, via `ZakatOccurrenceCalculator.nextOccurrence`)
    /// — computed fresh every time, never from a persisted Gregorian
    /// date, since none is stored for this kind.
    var allEntriesSortedByDate: [PersonalCalendarEntry] {
        entries.sorted {
            let lhsKey = sortKey(for: $0)
            let rhsKey = sortKey(for: $1)
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return $0.createdAt < $1.createdAt
        }
    }

    private func sortKey(for entry: PersonalCalendarEntry) -> String {
        switch entry.kind {
        case .note:
            return entry.isoDate ?? ""
        case .zakatDueDate:
            guard
                let day = entry.hijriDay, let month = entry.hijriMonth,
                let occurrence = ZakatOccurrenceCalculator.nextOccurrence(hijriDay: day, hijriMonth: month, hijriCalendar: hijriCalendar)
            else { return "" }
            return Self.isoDateString(from: occurrence)
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
