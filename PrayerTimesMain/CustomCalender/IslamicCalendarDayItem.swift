import Foundation

struct IslamicCalendarDayItem: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelected: Bool

    let gregorianDayText: String
    let hijriText: String?

    /// Every AlAdhan special day attached to this Gregorian date, unfiltered
    /// — includes entries like "Urs of …" or "Birth of …" that are not one
    /// of the app's selected major holidays. Used for the day sheet's event
    /// list, never for deciding the orange highlight below.
    let allEventsForDay: [IslamicSpecialDay]

    /// True only when `allEventsForDay` contains one of the app's own
    /// curated `MajorIslamicHoliday` cases (via `IslamicHolidayClassifier`,
    /// the same Umm-al-Qura-based definitions the Feiertage-overview uses)
    /// — never merely "this day has some AlAdhan event". This is the only
    /// thing that should ever drive the cell's orange date-number color.
    let isHighlightedHoliday: Bool

    let prayerDay: PrayerDay?

    var id: String {
        ISO8601DateFormatter().string(from: date)
    }
}
