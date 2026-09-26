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
    static func resolve(
        isoDate: String,
        rawTime: String,
        adjustmentMinutes: Int,
        timezoneIdentifier: String
    ) -> Date? {
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

        guard let dayStart = isoFormatter.date(from: isoDate) else {
            return nil
        }

        let adjusted = PrayerTimeAdjuster.adjustTime(rawTime, by: adjustmentMinutes)
        return PrayerTimeAdjuster.date(forAdjusted: adjusted, base: dayStart, calendar: calendar)
    }
}
