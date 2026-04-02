import Foundation

enum PrayerCachePolicy {
    nonisolated static let pastDays = 1
    nonisolated static let futureDays = 30
    nonisolated static let totalDays = pastDays + 1 + futureDays   // 32

    nonisolated static func fetchStart(
        from now: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: -pastDays, to: now) ?? now
    }

    nonisolated static func fetchEnd(
        from now: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: futureDays, to: now) ?? now
    }
}
