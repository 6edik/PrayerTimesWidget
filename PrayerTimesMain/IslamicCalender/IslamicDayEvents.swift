import Foundation

struct IslamicDaySheetData: Identifiable {
    let id = UUID()
    let date: Date
    let prayerDay: PrayerDay?
    let events: [IslamicSpecialDay]
}
