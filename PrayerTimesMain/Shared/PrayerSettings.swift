import Foundation

nonisolated struct PrayerSettings: Codable {
    let address: String
    // Confirmed coordinate for this request, if one is available (city
    // list selection or GPS fix). When nil, callers fall back to the
    // existing address-based AlAdhan endpoints.
    let location: PrayerLocation?
    let date: Date
    let method: PrayerCalculationMethod
}
