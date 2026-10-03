import Foundation

/// Centralizes "what is the currently active prayer window, and what comes
/// next" for a given instant — the single source of truth shared by every
/// widget family, so Small/Medium/lock-screen layouts can never disagree
/// about the current/next prayer, the countdown, or the progress fraction.
///
/// A window always chains yesterday's Isha, today's six prayers and
/// tomorrow's Fajr into one sorted list of absolute `Date`s, resolved in
/// the prayer location's own timezone (never the device's — see
/// `LastThirdOfNightResolver`/`QiratTimeResolver`, which already follow
/// this convention) with personal minute adjustments applied exactly once
/// (by the caller, via `applyingAdjustmentsWithDayOffsets`, before the
/// already-adjusted times are passed in here). This is what correctly
/// carries a window across midnight, whether or not an adjustment pushed a
/// prayer onto the previous/next calendar day.
nonisolated enum PrayerWindowResolver {
    struct Window: Equatable {
        let currentName: String
        let currentTime: String
        let nextName: String
        let nextTime: String
        let start: Date
        let end: Date
        let timezoneIdentifier: String

        /// Clamped 0...1 fraction of the window elapsed at `date`. Only for
        /// contexts that can't use a live `ProgressView(timerInterval:)`
        /// (e.g. a one-shot "is this prayer currently active" highlight
        /// check) — the Home-screen medium widget drives its progress bar
        /// directly from `start...end` instead of a snapshot value, so it
        /// keeps animating between timeline entries.
        func progress(at date: Date) -> Double {
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return 0 }
            return min(max(date.timeIntervalSince(start) / total, 0), 1)
        }
    }

    private struct Moment {
        let name: String
        let time: String
        let date: Date
    }

    /// Resolves the window around `now` from already-loaded, already-
    /// adjusted day data. `previousDayTimes`/`nextDayTimes` being `nil`
    /// (cache miss for that neighboring day) is tolerated — the window is
    /// built from whatever is actually available — but `nil` is returned
    /// instead of a fabricated placeholder whenever there isn't enough
    /// data to form *any* real forward-looking window (today missing, or
    /// only a single moment resolvable). Callers must show an honest empty
    /// state in that case, never a bar frozen at 0%.
    static func resolve(
        now: Date,
        todayTimes: AdjustedPrayerTimes,
        previousDayTimes: AdjustedPrayerTimes?,
        nextDayTimes: AdjustedPrayerTimes?,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Window? {
        var locationCalendar = calendar
        locationCalendar.timeZone = TimeZone(identifier: todayTimes.times.timezone) ?? .current

        let today = locationCalendar.startOfDay(for: now)
        let yesterday = locationCalendar.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = locationCalendar.date(byAdding: .day, value: 1, to: today) ?? today

        var moments: [Moment] = []

        if let previousDayTimes,
           let date = PrayerTimeAdjuster.date(
               forAdjusted: .init(value: previousDayTimes.times.isha, dayOffset: previousDayTimes.dayOffsets.isha),
               base: yesterday,
               calendar: locationCalendar
           ) {
            moments.append(Moment(name: "Isha", time: previousDayTimes.times.isha, date: date))
        }

        let todayMoments: [(name: String, time: String, dayOffset: Int)] = [
            ("Fajr", todayTimes.times.fajr, todayTimes.dayOffsets.fajr),
            ("Shuruk", todayTimes.times.shuruk, todayTimes.dayOffsets.shuruk),
            ("Dhuhr", todayTimes.times.dhuhr, todayTimes.dayOffsets.dhuhr),
            ("Asr", todayTimes.times.asr, todayTimes.dayOffsets.asr),
            ("Maghrib", todayTimes.times.maghrib, todayTimes.dayOffsets.maghrib),
            ("Isha", todayTimes.times.isha, todayTimes.dayOffsets.isha)
        ]
        for item in todayMoments {
            if let date = PrayerTimeAdjuster.date(
                forAdjusted: .init(value: item.time, dayOffset: item.dayOffset),
                base: today,
                calendar: locationCalendar
            ) {
                moments.append(Moment(name: item.name, time: item.time, date: date))
            }
        }

        if let nextDayTimes,
           let date = PrayerTimeAdjuster.date(
               forAdjusted: .init(value: nextDayTimes.times.fajr, dayOffset: nextDayTimes.dayOffsets.fajr),
               base: tomorrow,
               calendar: locationCalendar
           ) {
            moments.append(Moment(name: "Fajr", time: nextDayTimes.times.fajr, date: date))
        }

        moments.sort { $0.date < $1.date }
        guard moments.count > 1 else { return nil }

        let currentIndex = moments.lastIndex(where: { $0.date <= now }) ?? 0
        let current = moments[currentIndex]
        let nextIndex = min(currentIndex + 1, moments.count - 1)
        let next = moments[nextIndex]

        guard next.date > current.date else { return nil }

        return Window(
            currentName: current.name,
            currentTime: current.time,
            nextName: next.name,
            nextTime: next.time,
            start: current.date,
            end: next.date,
            timezoneIdentifier: todayTimes.times.timezone
        )
    }
}
