import Foundation

struct ManualPrayerQuery: Equatable {
    var address: String = ""
    var method: PrayerCalculationMethod = .ditib
    var date: Date = Date()

    init() {}

    init(seed: AutoPrayerSettings, date: Date = Date()) {
        self.address = seed.address
        self.method = seed.method
        self.date = date
    }

    var asPrayerSettings: PrayerSettings {
        PrayerSettings(
            address: address,
            date: date,
            method: method
        )
    }
}
