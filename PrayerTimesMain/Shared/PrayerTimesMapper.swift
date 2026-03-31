import Foundation

struct PrayerRow: Identifiable {
    let id = UUID()
    let name: String
    let time: String
}

enum PrayerTimesMapper {
    static func rows(from times: PrayerTimes) -> [PrayerRow] {
        [
            PrayerRow(name: "Fajr", time: times.fajr),
            PrayerRow(name: "Shuruk", time: times.shuruk),
            PrayerRow(name: "Dhuhr", time: times.dhuhr),
            PrayerRow(name: "Asr", time: times.asr),
            PrayerRow(name: "Maghrib", time: times.maghrib),
            PrayerRow(name: "Isha", time: times.isha)
        ]
    }
}
