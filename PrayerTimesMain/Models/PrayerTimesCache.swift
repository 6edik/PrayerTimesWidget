import Foundation

nonisolated struct HijriDay: Codable, Equatable {
    let day: String
    let month: String
    let year: String

    var displayText: String {
        "\(day). \(month) \(year)"
    }
}

nonisolated struct PrayerDay: Codable, Identifiable {
    let isoDate: String
    let hijri: HijriDay?
    let times: PrayerTimes

    var id: String { isoDate }
}

nonisolated struct PrayerTimesCache: Codable {
    // Coordinate-based when the settings that produced this cache had a
    // confirmed location, address-based otherwise — see `LocationKey`.
    // Never compare cache entries by display name alone: the bundled city
    // list has 22 duplicate names (e.g. two different "Essen"s).
    let locationKey: String
    let methodKey: String
    let fetchedAt: Date
    let days: [PrayerDay]

    var firstISODate: String? { days.first?.isoDate }
    var lastISODate: String? { days.last?.isoDate }

    static let empty = PrayerTimesCache(
        locationKey: "",
        methodKey: "",
        fetchedAt: .distantPast,
        days: []
    )
}
