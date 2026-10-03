import Foundation

struct IslamicCalendarDayItem: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelected: Bool

    let gregorianDayText: String
    let hijriText: String?

    /// Every AlAdhan special day attached to this Gregorian date that
    /// survived `IslamicHolidayClassifier.filterRelevant` — entries like
    /// "Urs of …" or "Birth of …" are dropped even when they share their
    /// exact Hijri date with a genuine curated holiday. Used for the day
    /// sheet's event list, never for deciding the orange highlight below.
    let allEventsForDay: [IslamicSpecialDay]

    /// True only when `allEventsForDay` contains one of the app's own
    /// curated `MajorIslamicHoliday` cases (via `IslamicHolidayClassifier`,
    /// the same Umm-al-Qura-based definitions the Feiertage-overview uses)
    /// — never merely "this day has some AlAdhan event". This is the only
    /// thing that should ever drive the cell's orange date-number color.
    let isHighlightedHoliday: Bool

    /// True only when this day matches the user's own, currently-active
    /// Zakat-due-date rule (`ZakatDueDateStore`) — never an AlAdhan entry.
    /// Drives its own distinct date-number color, independent of
    /// `isHighlightedHoliday` (orange).
    let hasZakatDueDate: Bool

    /// True when the user has at least one personal calendar entry on this
    /// day. Deliberately independent of `isHighlightedHoliday` (orange) and
    /// the Sunnah-fasting highlight (blue, computed in the cell itself) —
    /// drives only the small indicator dot, never the date-number color, so
    /// all three states can be shown at once.
    let hasPersonalEntries: Bool

    let prayerDay: PrayerDay?

    var id: String {
        ISO8601DateFormatter().string(from: date)
    }
}
