import Foundation

struct PrayerTimes: Codable {
    let fajr: String
    let dhuhr: String
    let asr: String
    let maghrib: String
    let isha: String
    let readableDate: String
    let hijriDate: String
    let timezone: String
}
