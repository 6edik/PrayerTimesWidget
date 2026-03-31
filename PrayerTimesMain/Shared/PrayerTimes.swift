import Foundation

struct PrayerTimes: Codable {
    let fajr: String
    let shuruk: String
    let dhuhr: String
    let asr: String
    let maghrib: String
    let isha: String
    let readableDate: String
    let readableDay: String
    let hijriDate: String
    let hijriDay: String
    let timezone: String
}
