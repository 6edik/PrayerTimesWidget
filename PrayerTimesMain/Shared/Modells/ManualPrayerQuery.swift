import Foundation

struct ManualPrayerQuery: Equatable {
    var address: String = ""
    var method: PrayerCalculationMethod = .ditib
    var date: Date = Date()
    var adjustments: PrayerAdjustments = .zero

    init() {}

    init(seed: AutoPrayerSettings, date: Date = Date()) {
        self.address = seed.address
        self.method = seed.method
        self.date = date
        self.adjustments = seed.adjustments
    }

    var asPrayerSettings: PrayerSettings {
        PrayerSettings(
            address: address,
            date: date,
            method: method
        )
    }
}
