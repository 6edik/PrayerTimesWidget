import Foundation

nonisolated struct PrayerAdjustments: Codable, Equatable {
    var fajr: Int = 0
    var shuruk: Int = 0
    var dhuhr: Int = 0
    var asr: Int = 0
    var maghrib: Int = 0
    var isha: Int = 0

    nonisolated static let zero = PrayerAdjustments()
}

/// Per-prayer day offset produced by an adjustment that pushed a time across
/// a midnight boundary (e.g. Isha 23:50 +20 min -> 00:10 the *next* day, or
/// Fajr 00:05 -20 min -> 23:45 the *previous* day). Only -1, 0 or +1 are
/// possible since adjustments are bounded to ±60 minutes.
struct PrayerDayOffsets: Equatable {
    var fajr = 0
    var shuruk = 0
    var dhuhr = 0
    var asr = 0
    var maghrib = 0
    var isha = 0

    nonisolated static let zero = PrayerDayOffsets()
}

nonisolated enum PrayerTimeAdjuster {
    struct AdjustedTime {
        /// The adjusted, wrapped "HH:mm" clock time — always a value within
        /// a single day, exactly like the un-adjusted API strings.
        let value: String
        /// -1, 0 or +1: which calendar day (relative to the day the
        /// un-adjusted time belongs to) this clock time actually falls on.
        let dayOffset: Int
    }

    /// Adjusts a "HH:mm" time by the given number of minutes, wrapping
    /// across midnight, and reports whether the result landed on the
    /// previous/next calendar day. This is the single place that decides
    /// midnight-wrap behavior; both the display string and the day offset
    /// come from the same computation so they can never disagree.
    static func adjustTime(_ value: String, by minutes: Int) -> AdjustedTime {
        let parts = value.split(separator: ":")
        guard
            parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else { return AdjustedTime(value: value, dayOffset: 0) }

        let total = hour * 60 + minute + minutes
        // Floor division so negative totals wrap to the *previous* day
        // (e.g. total = -10 -> dayOffset = -1, normalized = 1430).
        let dayOffset = total >= 0 ? total / 1440 : (total - 1439) / 1440
        let normalized = total - dayOffset * 1440
        let h = normalized / 60
        let m = normalized % 60
        return AdjustedTime(value: String(format: "%02d:%02d", h, m), dayOffset: dayOffset)
    }

    /// Convenience for callers that only need the display string (e.g. the
    /// static prayer-time rows in the app UI, which show a clock time and
    /// don't need to reconstruct an absolute `Date`).
    static func adjustTimeString(_ value: String, by minutes: Int) -> String {
        adjustTime(value, by: minutes).value
    }

    /// Builds the absolute `Date` for a "HH:mm" clock time that belongs to
    /// `dayOffset` days relative to `base` (see `AdjustedTime.dayOffset`).
    /// Centralizing this avoids every call site separately having to
    /// remember to shift `base` before setting the hour/minute.
    static func date(
        forAdjusted adjusted: AdjustedTime,
        base: Date,
        calendar: Calendar
    ) -> Date? {
        guard let shiftedBase = calendar.date(byAdding: .day, value: adjusted.dayOffset, to: base) else {
            return nil
        }

        let parts = adjusted.value.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shiftedBase)
    }
}
