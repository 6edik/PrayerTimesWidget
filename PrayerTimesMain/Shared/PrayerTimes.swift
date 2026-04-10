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

/// Result of applying a `PrayerAdjustments` to a `PrayerTimes`: the adjusted
/// display strings plus, for each prayer, whether the adjustment pushed it
/// onto the previous/next calendar day. Only code that needs to reconstruct
/// an absolute `Date` (the widget's timeline/"next prayer" logic) needs
/// `dayOffsets` — plain display code can keep using `times`.
struct AdjustedPrayerTimes {
    let times: PrayerTimes
    let dayOffsets: PrayerDayOffsets
}

extension PrayerTimes {
    func applyingAdjustmentsWithDayOffsets(_ adjustments: PrayerAdjustments) -> AdjustedPrayerTimes {
        let fajr = PrayerTimeAdjuster.adjustTime(self.fajr, by: adjustments.fajr)
        let shuruk = PrayerTimeAdjuster.adjustTime(self.shuruk, by: adjustments.shuruk)
        let dhuhr = PrayerTimeAdjuster.adjustTime(self.dhuhr, by: adjustments.dhuhr)
        let asr = PrayerTimeAdjuster.adjustTime(self.asr, by: adjustments.asr)
        let maghrib = PrayerTimeAdjuster.adjustTime(self.maghrib, by: adjustments.maghrib)
        let isha = PrayerTimeAdjuster.adjustTime(self.isha, by: adjustments.isha)

        let times = PrayerTimes(
            fajr: fajr.value,
            shuruk: shuruk.value,
            dhuhr: dhuhr.value,
            asr: asr.value,
            maghrib: maghrib.value,
            isha: isha.value,
            readableDate: readableDate,
            readableDay: readableDay,
            hijriDate: hijriDate,
            hijriDay: hijriDay,
            timezone: timezone
        )

        let dayOffsets = PrayerDayOffsets(
            fajr: fajr.dayOffset,
            shuruk: shuruk.dayOffset,
            dhuhr: dhuhr.dayOffset,
            asr: asr.dayOffset,
            maghrib: maghrib.dayOffset,
            isha: isha.dayOffset
        )

        return AdjustedPrayerTimes(times: times, dayOffsets: dayOffsets)
    }

    /// Display-only convenience: the adjusted "HH:mm" strings without the
    /// day-offset information. Safe for anything that just prints a clock
    /// time (home screen rows, manual-query result, widget prayer rows) —
    /// it wraps across midnight exactly like the API's own strings do, it
    /// just doesn't say *which* day the wrapped time belongs to.
    func applyingAdjustments(_ adjustments: PrayerAdjustments) -> PrayerTimes {
        applyingAdjustmentsWithDayOffsets(adjustments).times
    }
}
