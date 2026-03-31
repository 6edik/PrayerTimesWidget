import Foundation

struct PrayerDay: Codable, Identifiable {
    let isoDate: String
    let times: PrayerTimes

    var id: String { isoDate }
}

struct PrayerTimesCache: Codable {
    let addressKey: String
    let methodKey: String
    let fetchedAt: Date
    let days: [PrayerDay]

    var firstISODate: String? { days.first?.isoDate }
    var lastISODate: String? { days.last?.isoDate }

    static let empty = PrayerTimesCache(
        addressKey: "",
        methodKey: "",
        fetchedAt: .distantPast,
        days: []
    )
}
