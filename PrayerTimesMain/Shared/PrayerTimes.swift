import Foundation

struct PrayerTimes: Codable, Equatable {
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

extension PrayerTimes {
    func applyingAdjustments(_ adjustments: PrayerAdjustments) -> PrayerTimes {
        PrayerTimes(
            fajr: PrayerTimeAdjuster.adjustTimeString(fajr, by: adjustments.fajr),
            shuruk: PrayerTimeAdjuster.adjustTimeString(shuruk, by: adjustments.shuruk),
            dhuhr: PrayerTimeAdjuster.adjustTimeString(dhuhr, by: adjustments.dhuhr),
            asr: PrayerTimeAdjuster.adjustTimeString(asr, by: adjustments.asr),
            maghrib: PrayerTimeAdjuster.adjustTimeString(maghrib, by: adjustments.maghrib),
            isha: PrayerTimeAdjuster.adjustTimeString(isha, by: adjustments.isha),
            readableDate: readableDate,
            readableDay: readableDay,
            hijriDate: hijriDate,
            hijriDay: hijriDay,
            timezone: timezone
        )
    }
}
