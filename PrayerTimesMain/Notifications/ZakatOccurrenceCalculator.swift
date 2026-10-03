import Foundation

/// Turns a Zakat-due-date entry's fixed Hijri (day, month) rule into
/// concrete Gregorian occurrence dates. Every Zakat entry recurs this way
/// — there is no one-time variant and no Gregorian-based repeat option
/// (a fixed business decision, not a user toggle — see
/// `PersonalCalendarEntry`'s doc comment). This type has no notion of
/// "recurrence on/off" at all; it only ever expands a Hijri rule forward.
///
/// Walks forward Hijri year by Hijri year (never "+365 days", which would
/// silently drift relative to the actual, variable-length Hijri calendar)
/// and, for each year, explicitly checks — via `Calendar.range(of:in:
/// for:)` — whether the chosen (day, month) actually exists that year
/// before asking `Calendar.date(from:)` to build it. Some Hijri months
/// have 29 days, others 30, and which is which varies year to year under
/// `.islamicUmmAlQura`; a day that doesn't exist in a given year (e.g. the
/// 30th of a 29-day month) is skipped entirely for that one year — never
/// silently substituted with day 29 or rolled into the next month, which
/// is what asking `Calendar.date(from:)` for an out-of-range day would
/// otherwise do.
///
/// Documented re-planning behavior: `upcomingOccurrences` is re-run every
/// time `NotificationScheduler.reschedule()` runs, which itself fires on
/// app launch, app foreground, and any notification-settings/entry change
/// (see `PrayerTimesApp`) — not just from the best-effort
/// `BGAppRefreshTask`. Because several occurrences are considered at once
/// (not just the very next one), a missed or late background trigger
/// doesn't strand the user without a reminder.
nonisolated enum ZakatOccurrenceCalculator {
    /// - Parameters:
    ///   - hijriDay: 1...30, the entry's fixed rule.
    ///   - hijriMonth: 1...12, the entry's fixed rule.
    ///   - now: which Hijri year to start searching from — never used to
    ///     compute a fire time directly; every returned `Date` is an exact
    ///     Umm-al-Qura occurrence.
    ///   - limit: maximum number of concrete occurrences to return.
    ///   - maxHijriYearsAhead: hard search bound so a request can never
    ///     cause an unbounded loop — the "sicherer, begrenzter
    ///     Zukunftszeitraum" from the spec, never an unlimited search.
    static func upcomingOccurrences(
        hijriDay: Int,
        hijriMonth: Int,
        now: Date = Date(),
        limit: Int = 3,
        maxHijriYearsAhead: Int = 5,
        hijriCalendar: Calendar = HijriDateFormatting.calendar()
    ) -> [Date] {
        let currentHijriYear = hijriCalendar.component(.year, from: now)
        var hijriYear = currentHijriYear

        var results: [Date] = []
        var yearsSearched = 0

        while results.count < limit && yearsSearched < maxHijriYearsAhead {
            if let date = concreteDate(day: hijriDay, month: hijriMonth, hijriYear: hijriYear, hijriCalendar: hijriCalendar) {
                results.append(date)
            }
            // Else: the day doesn't exist in `hijriMonth` for this
            // particular Hijri year — deliberately skipped, no substitute.

            hijriYear += 1
            yearsSearched += 1
        }

        return results
    }

    /// The single nearest occurrence, searching starting at `now`'s own
    /// Hijri year — so it can land slightly in the past within that same
    /// Hijri year if this cycle's date already elapsed. Used for display
    /// (the "current/representative" occurrence shown next to the fixed
    /// Hijri rule), never for scheduling a notification, which always
    /// goes through `upcomingOccurrences` and is filtered to the future by
    /// `NotificationCandidate.prioritized`.
    static func nextOccurrence(
        hijriDay: Int,
        hijriMonth: Int,
        now: Date = Date(),
        maxHijriYearsAhead: Int = 5,
        hijriCalendar: Calendar = HijriDateFormatting.calendar()
    ) -> Date? {
        upcomingOccurrences(
            hijriDay: hijriDay,
            hijriMonth: hijriMonth,
            now: now,
            limit: 1,
            maxHijriYearsAhead: maxHijriYearsAhead,
            hijriCalendar: hijriCalendar
        ).first
    }

    /// Whether `date`'s own Hijri (day, month) — under `hijriCalendar`,
    /// which determines the timezone used for the day-boundary decision —
    /// matches the given rule. Used by the calendar grid and day sheet to
    /// decide whether a Zakat entry belongs on `date`, for *any* Gregorian
    /// year the user might be viewing (past or future), not just the next
    /// upcoming occurrence.
    static func matches(
        hijriDay: Int,
        hijriMonth: Int,
        date: Date,
        hijriCalendar: Calendar = HijriDateFormatting.calendar()
    ) -> Bool {
        let components = hijriCalendar.dateComponents([.day, .month], from: date)
        return components.day == hijriDay && components.month == hijriMonth
    }

    /// Builds the concrete date for (day, month, hijriYear) only after
    /// confirming that exact day is within the month's actual range that
    /// year. Returns `nil` (never a rolled-over/adjacent date) when it
    /// isn't.
    private static func concreteDate(day: Int, month: Int, hijriYear: Int, hijriCalendar: Calendar) -> Date? {
        var firstOfMonthComponents = DateComponents()
        firstOfMonthComponents.year = hijriYear
        firstOfMonthComponents.month = month
        firstOfMonthComponents.day = 1

        guard
            let firstOfMonth = hijriCalendar.date(from: firstOfMonthComponents),
            let dayRange = hijriCalendar.range(of: .day, in: .month, for: firstOfMonth),
            dayRange.contains(day)
        else {
            return nil
        }

        var components = DateComponents()
        components.year = hijriYear
        components.month = month
        components.day = day
        return hijriCalendar.date(from: components)
    }

    /// The exact title every synthetic Zakat `IslamicSpecialDay` carries —
    /// a single named constant instead of the string literal repeated at
    /// every call site, so `IslamicHolidayClassifier.dedupeKey`'s category
    /// fallback and every UI spot that needs to recognize "is this row the
    /// Zakat entry" (`IslamicHolidayOverviewSheet`, `IslamicDayEventsSheet`)
    /// can never drift out of sync with each other.
    static let specialDayTitle = "Zakat-Stichtag"

    /// Builds a display-only `IslamicSpecialDay` for one concrete Zakat
    /// occurrence — never persisted to `SharedIslamicCalendarStore` (this
    /// is not an AlAdhan entry) and never written to the prayer-times
    /// cache; purely a value used to merge the user's own Zakat-due-date
    /// rule into the same chronological "Besondere Tage" list the 8
    /// curated holidays use, via `IslamicHolidayClassifier
    /// .deduplicatedAndSorted`.
    static func specialDay(hijriDay: Int, hijriMonth: Int, occurrence: Date, hijriCalendar: Calendar = HijriDateFormatting.calendar()) -> IslamicSpecialDay {
        let gregorianFormatter = DateFormatter()
        gregorianFormatter.locale = Locale(identifier: "de_DE")
        gregorianFormatter.dateStyle = .long

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "de_DE")
        monthFormatter.dateFormat = "LLLL"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "de_DE")
        weekdayFormatter.dateFormat = "EEEE"

        return IslamicSpecialDay(
            title: specialDayTitle,
            gregorianReadable: gregorianFormatter.string(from: occurrence),
            gregorianMonthName: monthFormatter.string(from: occurrence),
            gregorianYear: yearFormatter.string(from: occurrence),
            hijriDay: "\(hijriDay)",
            hijriMonth: HijriDateFormatting.monthName(hijriMonth),
            hijriYear: "\(hijriCalendar.component(.year, from: occurrence))",
            hijriWeekday: weekdayFormatter.string(from: occurrence),
            sortDate: occurrence,
            hijriMonthNumber: hijriMonth
        )
    }
}
