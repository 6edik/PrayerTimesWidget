import Foundation

struct IslamicCalendarDayItem: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelected: Bool

    let gregorianDayText: String
    let hijriText: String?
    let events: [IslamicSpecialDay]
    let prayerDay: PrayerDay?

    var id: String {
        ISO8601DateFormatter().string(from: date)
    }
}
