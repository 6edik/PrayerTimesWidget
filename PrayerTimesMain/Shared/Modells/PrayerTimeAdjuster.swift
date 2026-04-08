import Foundation

struct PrayerAdjustments: Codable, Equatable {
    var fajr: Int = 0
    var shuruk: Int = 0
    var dhuhr: Int = 0
    var asr: Int = 0
    var maghrib: Int = 0
    var isha: Int = 0

    static let zero = PrayerAdjustments()
}

enum PrayerTimeAdjuster {
    static func adjustTimeString(_ value: String, by minutes: Int) -> String {
        let parts = value.split(separator: ":")
        guard
            parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else { return value }

        let total = hour * 60 + minute + minutes
        let normalized = ((total % 1440) + 1440) % 1440
        let h = normalized / 60
        let m = normalized % 60
        return String(format: "%02d:%02d", h, m)
    }
}
