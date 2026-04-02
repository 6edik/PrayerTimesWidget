import Foundation

struct AutoPrayerSettings: Codable, Equatable {
    var address: String = "Gelsenkirchen, DE"
    var method: PrayerCalculationMethod = .ditib

    func asPrayerSettings(for date: Date = Date()) -> PrayerSettings {
        PrayerSettings(
            address: address,
            date: date,
            method: method
        )
    }
}
