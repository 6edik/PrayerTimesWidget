import Foundation

/// Resolves which Maghrib/Fajr pair defines "the current night" for the
/// last-third-of-the-night window, mirroring the same yesterday/today/
/// tomorrow resolution the widget's own prayer-window logic already uses
/// for the five prayers: before today's Maghrib, the current night started
/// at *yesterday's* Maghrib and ends at *today's* Fajr; from today's
/// Maghrib onward, it started at *today's* Maghrib and ends at
/// *tomorrow's* Fajr. Both moments are resolved to real, adjusted `Date`s
/// (personal minute adjustments applied, each day's own location timezone
/// used) via `PrayerTimeAdjuster` — the same machinery the rest of the app
/// already relies on for midnight-safe day arithmetic.
///
/// Returns `nil` — never a fabricated time — whenever a required
/// previous/next day isn't cached.
nonisolated enum LastThirdOfNightResolver {
    struct ResolvedWindow: Equatable {
        let start: Date
        let end: Date
        /// The timezone `end` (the following Fajr) belongs to — the
        /// correct zone to format both `start` and `end` as clock times
        /// in, since they describe the same physical prayer location.
        let timezoneIdentifier: String
    }

    static func window(
        now: Date = Date(),
        store: SharedPrayerTimesStore,
        settings: AutoPrayerSettings,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ResolvedWindow? {
        guard let today = moment(.maghrib, dayOffset: 0, now: now, store: store, settings: settings, calendar: calendar) else {
            return nil
        }

        if now < today.date {
            guard
                let yesterday = moment(.maghrib, dayOffset: -1, now: now, store: store, settings: settings, calendar: calendar),
                let todayFajr = moment(.fajr, dayOffset: 0, now: now, store: store, settings: settings, calendar: calendar),
                let core = LastThirdOfNightCalculator.window(maghrib: yesterday.date, followingFajr: todayFajr.date)
            else { return nil }

            return ResolvedWindow(start: core.start, end: core.end, timezoneIdentifier: todayFajr.timezoneIdentifier)
        }

        guard
            let tomorrowFajr = moment(.fajr, dayOffset: 1, now: now, store: store, settings: settings, calendar: calendar),
            let core = LastThirdOfNightCalculator.window(maghrib: today.date, followingFajr: tomorrowFajr.date)
        else { return nil }

        return ResolvedWindow(start: core.start, end: core.end, timezoneIdentifier: tomorrowFajr.timezoneIdentifier)
    }

    private enum Prayer { case maghrib, fajr }

    /// Loads the cached day at `dayOffset` days from `now` (device-calendar
    /// day arithmetic — the same convention `SharedPrayerTimesStore`'s own
    /// ISO keys already use to pick *which* cached day to load), applies
    /// the stored minute adjustments, and resolves the requested prayer's
    /// "HH:mm" + day-offset to an absolute `Date` in that day's own
    /// location timezone.
    private static func moment(
        _ prayer: Prayer,
        dayOffset: Int,
        now: Date,
        store: SharedPrayerTimesStore,
        settings: AutoPrayerSettings,
        calendar: Calendar
    ) -> (date: Date, timezoneIdentifier: String)? {
        guard
            let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: now),
            let raw = store.load(for: targetDay, settings: settings)
        else { return nil }

        let adjusted = raw.applyingAdjustmentsWithDayOffsets(settings.adjustments)

        let value: String
        let offset: Int
        switch prayer {
        case .maghrib:
            value = adjusted.times.maghrib
            offset = adjusted.dayOffsets.maghrib
        case .fajr:
            value = adjusted.times.fajr
            offset = adjusted.dayOffsets.fajr
        }

        var locationCalendar = Calendar(identifier: .gregorian)
        locationCalendar.timeZone = TimeZone(identifier: adjusted.times.timezone) ?? .current

        guard let date = PrayerTimeAdjuster.date(
            forAdjusted: .init(value: value, dayOffset: offset),
            base: targetDay,
            calendar: locationCalendar
        ) else { return nil }

        return (date, adjusted.times.timezone)
    }
}
