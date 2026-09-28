import Foundation

/// Resolves the absolute `Date` a prayer notification should fire at.
///
/// This is the one place that combines a cached day's ISO date, its raw
/// (unadjusted) API time string, the user's minute adjustment and the
/// *location's* own timezone (not the device's) into a single instant —
/// reusing `PrayerTimeAdjuster` (already midnight-safe from the earlier
/// display-layer fix) so a Fajr/Isha adjustment that crosses midnight lands
/// on the correct calendar day here too.
///
/// Building the day's start-of-day in the location's timezone (via
/// `TimeZone(identifier:)`) rather than the device's means DST transitions
/// and a location in a different timezone than the device are both handled
/// correctly — `TimeZone(identifier:)` resolves the correct UTC offset for
/// the specific date automatically.
enum PrayerMomentResolver {
    /// Local midnight of `isoDate` in the timezone identified by
    /// `timezoneIdentifier` — the shared building block `resolve` below
    /// uses to anchor an ISO date string to an absolute instant in a
    /// specific location's timezone. Exposed separately so other callers
    /// that need the same "which absolute instant does this ISO-date label
    /// refer to, in this location" resolution — e.g. the voluntary-fasting
    /// scheduler deciding which Gregorian/Hijri calendar day a cached
    /// prayer day falls on — can reuse it instead of re-implementing the
    /// same date-formatting recipe.
    static func dayStart(isoDate: String, timezoneIdentifier: String) -> Date? {
        guard let zone = TimeZone(identifier: timezoneIdentifier) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let isoFormatter = DateFormatter()
        isoFormatter.calendar = calendar
        isoFormatter.timeZone = zone
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd"

        return isoFormatter.date(from: isoDate)
    }

    static func resolve(
        isoDate: String,
        rawTime: String,
        adjustmentMinutes: Int,
        timezoneIdentifier: String
    ) -> Date? {
        guard
            let zone = TimeZone(identifier: timezoneIdentifier),
            let dayStart = dayStart(isoDate: isoDate, timezoneIdentifier: timezoneIdentifier)
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let adjusted = PrayerTimeAdjuster.adjustTime(rawTime, by: adjustmentMinutes)
        return PrayerTimeAdjuster.date(forAdjusted: adjusted, base: dayStart, calendar: calendar)
    }
}
