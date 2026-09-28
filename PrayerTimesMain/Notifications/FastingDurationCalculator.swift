import Foundation

/// Central calculation of a day's voluntary-fasting duration: adjusted
/// Maghrib minus adjusted Fajr, both resolved as full `Date`s in the
/// prayer location's own timezone (via `PrayerMomentResolver`, so a
/// midnight-crossing adjustment is handled correctly) — never a naive
/// "HH:mm" string subtraction. Used by both the Islamic calendar's day
/// sheet (to show the estimate for a tapped day) and
/// `NotificationScheduler` (to phrase the existing voluntary-fasting
/// reminder's body text), so the two can never quietly disagree.
enum FastingDurationCalculator {
    struct Result {
        let fajrDate: Date
        let maghribDate: Date
        let timezoneIdentifier: String

        var duration: TimeInterval { maghribDate.timeIntervalSince(fajrDate) }
    }

    /// `nil` whenever either time can't be resolved into an absolute
    /// instant (malformed stored time, unknown timezone identifier) or the
    /// resolved Maghrib doesn't actually fall after Fajr — callers must show
    /// no estimate at all in that case, never a guessed or partial one.
    static func result(
        isoDate: String,
        times: PrayerTimes,
        adjustments: PrayerAdjustments
    ) -> Result? {
        guard
            let fajrDate = PrayerMomentResolver.resolve(
                isoDate: isoDate,
                rawTime: times.fajr,
                adjustmentMinutes: adjustments.fajr,
                timezoneIdentifier: times.timezone
            ),
            let maghribDate = PrayerMomentResolver.resolve(
                isoDate: isoDate,
                rawTime: times.maghrib,
                adjustmentMinutes: adjustments.maghrib,
                timezoneIdentifier: times.timezone
            ),
            maghribDate > fajrDate
        else { return nil }

        return Result(fajrDate: fajrDate, maghribDate: maghribDate, timezoneIdentifier: times.timezone)
    }

    /// "15 Std. 40 Min." — or just "15 Std." when there are no leftover
    /// minutes.
    static func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) Std." : "\(hours) Std. \(minutes) Min."
    }

    /// "05:00" — the clock time `date` represents in `timezoneIdentifier`
    /// (the prayer location's own timezone), for display next to the
    /// duration.
    static func clockString(_ date: Date, timezoneIdentifier: String) -> String {
        guard let zone = TimeZone(identifier: timezoneIdentifier) else { return "--:--" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
