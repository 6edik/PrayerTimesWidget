import Foundation

struct ManualPrayerResult: Equatable {
    let address: String
    let method: PrayerCalculationMethod
    let date: Date
    let times: PrayerTimes
}
