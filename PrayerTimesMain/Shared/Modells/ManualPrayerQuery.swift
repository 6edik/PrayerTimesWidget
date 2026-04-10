import Foundation

struct ManualPrayerQuery: Equatable {
    var address: String = ""
    // Confirmed coordinate for `address`, if the current selection came
    // from the city list or GPS. Cleared whenever the address is edited by
    // hand so a stale coordinate never gets attached to a different place.
    var location: PrayerLocation? = nil
    var method: PrayerCalculationMethod = .ditib
    var date: Date = Date()
    var adjustments: PrayerAdjustments = .zero

    init() {}

    init(seed: AutoPrayerSettings, date: Date = Date()) {
        self.address = seed.address
        self.location = seed.location
        self.method = seed.method
        self.date = date
        self.adjustments = seed.adjustments
    }

    var asPrayerSettings: PrayerSettings {
        PrayerSettings(
            address: address,
            location: location,
            date: date,
            method: method
        )
    }
}
