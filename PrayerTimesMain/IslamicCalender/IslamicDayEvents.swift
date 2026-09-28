import Foundation

struct IslamicDaySheetData: Identifiable {
    let id = UUID()
    let date: Date
    // Computed via IslamicCalendarViewModel.hijriDisplayText(for:) — the
    // same Umm-al-Qura logic already used elsewhere in the calendar — so
    // the Hijri display never depends on whether prayer-time data is
    // cached, missing, or still being fetched.
    let hijriText: String
    let events: [IslamicSpecialDay]
}
