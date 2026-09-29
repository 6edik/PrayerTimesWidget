import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `ZakatOccurrenceCalculator`: every Zakat entry is defined by a
/// fixed Hijri (day, month) rule, never a Gregorian anchor date and never
/// an opt-in/opt-out recurrence flag — there is no non-recurring variant.
/// - the same Hijri (day, month) produces several consecutive Hijri-year
///   occurrences, each with a *different* Gregorian date
/// - no "+365 days" arithmetic: consecutive occurrences are exactly one
///   Hijri year apart via `Calendar(identifier: .islamicUmmAlQura)`
/// - the explicit, no-silent-substitute rule for a chosen Hijri day that
///   doesn't exist in every year (e.g. day 30 of a month that has only 29
///   days in some years) — discovered dynamically against the live
///   Umm-al-Qura calendar data rather than a hardcoded assumed year
/// - the bounded search never searches more than the safety limit allows
/// - `matches(...)` agrees with `upcomingOccurrences` for calendar-grid
///   day matching
@MainActor
struct ZakatOccurrenceCalculatorTests {
    private var hijriCalendar: Calendar {
        HijriDateFormatting.calendar()
    }

    // MARK: - Multiple consecutive Hijri years, different Gregorian dates

    @Test func sameHijriDayAndMonthAppearsInSeveralConsecutiveHijriYears() async throws {
        // The 1st of any Hijri month always exists — a safe day to verify
        // plain multi-year expansion without hitting the day-30 edge case.
        let currentHijriYear = hijriCalendar.component(.year, from: Date())
        var anchorComponents = DateComponents()
        anchorComponents.year = currentHijriYear
        anchorComponents.month = 1
        anchorComponents.day = 1
        let now = try #require(hijriCalendar.date(from: anchorComponents))

        let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
            hijriDay: 1,
            hijriMonth: 1,
            now: now,
            limit: 3,
            hijriCalendar: hijriCalendar
        )

        #expect(occurrences.count == 3)

        // No "+365 days": consecutive occurrences are exactly one Hijri
        // year apart, and every one lands on Hijri day 1, month 1.
        let hijriYears = occurrences.map { hijriCalendar.component(.year, from: $0) }
        #expect(hijriYears == [currentHijriYear, currentHijriYear + 1, currentHijriYear + 2])

        for date in occurrences {
            let comps = hijriCalendar.dateComponents([.day, .month], from: date)
            #expect(comps.day == 1)
            #expect(comps.month == 1)
        }

        // The Gregorian dates themselves must differ between years — a
        // Hijri year is ~11 days shorter than a Gregorian year, so the
        // same Hijri rule never lands on the same Gregorian date twice in
        // a row.
        let gregorianDates = Set(occurrences.map { PersonalCalendarViewModel.isoDateString(from: $0) })
        #expect(gregorianDates.count == 3)
    }

    /// The concrete case from the spec: "Mein Zakat-Stichtag ist der 27.
    /// Ramadan." The stored rule is exclusively Hijri day 27 / Hijri
    /// month 9 (Ramadan) — never a Gregorian date. This test asserts the
    /// rule is honored for several *consecutive* Hijri years and rejects
    /// the two concrete failure modes named in the spec:
    /// - a constant Gregorian month/day being reused every year (which
    ///   would mean the code is actually keyed off a Gregorian date, not
    ///   the Hijri rule), and
    /// - consecutive occurrences being exactly 365 Gregorian days apart
    ///   (i.e. `date(byAdding: .day, value: 365, to:)` arithmetic, which
    ///   drifts relative to the real, variable-length Hijri year).
    @Test func the27thOfRamadanProducesCorrectHijriComponentsAcrossConsecutiveYearsWithShiftingGregorianDates() async throws {
        let zakatHijriDay = 27
        let zakatHijriMonth = 9 // Ramadan

        let currentHijriYear = hijriCalendar.component(.year, from: Date())
        var anchorComponents = DateComponents()
        anchorComponents.year = currentHijriYear
        anchorComponents.month = zakatHijriMonth
        anchorComponents.day = zakatHijriDay
        let now = try #require(hijriCalendar.date(from: anchorComponents))

        let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
            hijriDay: zakatHijriDay,
            hijriMonth: zakatHijriMonth,
            now: now,
            limit: 5,
            hijriCalendar: hijriCalendar
        )

        #expect(occurrences.count == 5)

        // Exactly one Hijri year apart, never skipped or duplicated —
        // 27 Ramadan exists every year (day 27 is always within range),
        // so all 5 consecutive Hijri years must be present.
        let hijriYears = occurrences.map { hijriCalendar.component(.year, from: $0) }
        #expect(hijriYears == [currentHijriYear, currentHijriYear + 1, currentHijriYear + 2, currentHijriYear + 3, currentHijriYear + 4])

        // Every single occurrence must be Hijri day 27, Hijri month 9 —
        // the rule itself, verified independently for each year.
        for date in occurrences {
            let comps = hijriCalendar.dateComponents([.day, .month], from: date)
            #expect(comps.day == zakatHijriDay, "occurrence \(date) must be Hijri day \(zakatHijriDay), got \(comps.day as Any)")
            #expect(comps.month == zakatHijriMonth, "occurrence \(date) must be Hijri month \(zakatHijriMonth), got \(comps.month as Any)")
        }

        // Failure mode 1: a constant Gregorian month/day reused every
        // year would mean the "rule" is secretly a Gregorian date, not a
        // Hijri one. The Hijri year is consistently shorter than the
        // Gregorian year, so the Gregorian (month, day) pair must differ
        // across at least some of these 5 years.
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = hijriCalendar.timeZone
        let gregorianMonthDayPairs = occurrences.map {
            gregorianCalendar.dateComponents([.month, .day], from: $0)
        }
        let distinctGregorianMonthDayPairs = Set(gregorianMonthDayPairs.map { "\($0.month ?? -1)-\($0.day ?? -1)" })
        #expect(
            distinctGregorianMonthDayPairs.count > 1,
            "the Gregorian month/day must shift between Hijri years — a fixed Gregorian month/day indicates the rule is not actually Hijri-based"
        )

        // Failure mode 2: consecutive occurrences must never be exactly
        // 365 Gregorian days apart — that's the "+365 days" arithmetic
        // the spec explicitly forbids. A real Hijri year is 354 or 355
        // days, so the gap must differ from 365.
        for index in 0..<(occurrences.count - 1) {
            let daysBetween = gregorianCalendar.dateComponents(
                [.day], from: occurrences[index], to: occurrences[index + 1]
            ).day ?? 0
            #expect(daysBetween != 365, "consecutive occurrences must not be exactly 365 days apart (that would be Gregorian, not Hijri, arithmetic)")
            // Sanity bound: a genuine Hijri year is 354 or 355 days —
            // never anywhere near a Gregorian year's 365/366.
            #expect((353...356).contains(daysBetween), "expected a Hijri-year-length gap (~354-355 days), got \(daysBetween)")
        }
    }

    // MARK: - The no-silent-substitute rule for a day that doesn't exist every year

    /// Finds a Hijri month whose length actually varies across nearby
    /// years (29 days some years, 30 days others) by asking the real
    /// `Calendar(identifier: .islamicUmmAlQura)` directly — never assumes
    /// a specific year/month combination ahead of time, since that's
    /// exactly the kind of silent, potentially-wrong assumption the
    /// production rule itself refuses to make.
    private func findMonthWithVaryingLength(
        startHijriYear: Int,
        searchYears: Int
    ) -> (month: Int, shortYear: Int, longYear: Int)? {
        for month in 1...12 {
            var shortYear: Int?
            var longYear: Int?

            for offset in 0..<searchYears {
                let year = startHijriYear + offset
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = 1

                guard
                    let firstOfMonth = hijriCalendar.date(from: comps),
                    let range = hijriCalendar.range(of: .day, in: .month, for: firstOfMonth)
                else { continue }

                if range.count == 29, shortYear == nil { shortYear = year }
                if range.count == 30, longYear == nil { longYear = year }
                if let s = shortYear, let l = longYear { return (month, s, l) }
            }
        }
        return nil
    }

    @Test func hijriDay30SkipsYearsWhereTheMonthHasOnly29DaysWithNoSubstitute() async throws {
        let currentHijriYear = hijriCalendar.component(.year, from: Date())
        guard let found = findMonthWithVaryingLength(startHijriYear: currentHijriYear, searchYears: 40) else {
            // Environment-dependent (ICU calendar data); nothing to assert
            // if no varying-length month is found within the search
            // window, rather than failing the suite over calendar data
            // this test doesn't control.
            return
        }

        // Search from whichever of the two years comes first, so the
        // window spans both the short and the long year.
        let searchStartYear = min(found.shortYear, found.longYear)
        var searchStartComponents = DateComponents()
        searchStartComponents.year = searchStartYear
        searchStartComponents.month = 1
        searchStartComponents.day = 1
        let searchStartDate = try #require(hijriCalendar.date(from: searchStartComponents))

        let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
            hijriDay: 30,
            hijriMonth: found.month,
            now: searchStartDate,
            limit: 10,
            maxHijriYearsAhead: 15,
            hijriCalendar: hijriCalendar
        )

        let occurrenceHijriYears = occurrences.map { hijriCalendar.component(.year, from: $0) }

        // The short year must never contribute an occurrence — no day-29
        // or next-month substitute silently standing in for the missing
        // day 30.
        #expect(!occurrenceHijriYears.contains(found.shortYear))

        // The long year (which genuinely has day 30) must still produce a
        // normal occurrence.
        #expect(occurrenceHijriYears.contains(found.longYear))

        // Every returned occurrence really is day 30 of the target month
        // — confirms no rolled-over date (e.g. day 1 of the next month)
        // ever slipped through.
        for date in occurrences {
            let comps = hijriCalendar.dateComponents([.day, .month], from: date)
            #expect(comps.day == 30)
            #expect(comps.month == found.month)
        }
    }

    // MARK: - Bounded search

    @Test func zeroMaxHijriYearsAheadSearchesNothing() async throws {
        let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
            hijriDay: 15,
            hijriMonth: 6,
            limit: 5,
            maxHijriYearsAhead: 0,
            hijriCalendar: hijriCalendar
        )
        #expect(occurrences.isEmpty)
    }

    @Test func limitCapsTheNumberOfReturnedOccurrences() async throws {
        let currentHijriYear = hijriCalendar.component(.year, from: Date())
        var anchorComponents = DateComponents()
        anchorComponents.year = currentHijriYear
        anchorComponents.month = 1
        anchorComponents.day = 1
        let now = try #require(hijriCalendar.date(from: anchorComponents))

        let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
            hijriDay: 1,
            hijriMonth: 1,
            now: now,
            limit: 1,
            maxHijriYearsAhead: 10,
            hijriCalendar: hijriCalendar
        )
        #expect(occurrences.count == 1)
    }

    // MARK: - nextOccurrence

    @Test func nextOccurrenceReturnsTheFirstUpcomingOccurrenceOnly() async throws {
        let currentHijriYear = hijriCalendar.component(.year, from: Date())
        var anchorComponents = DateComponents()
        anchorComponents.year = currentHijriYear
        anchorComponents.month = 3
        anchorComponents.day = 10
        let now = try #require(hijriCalendar.date(from: anchorComponents))

        let next = ZakatOccurrenceCalculator.nextOccurrence(hijriDay: 10, hijriMonth: 3, now: now, hijriCalendar: hijriCalendar)
        let all = ZakatOccurrenceCalculator.upcomingOccurrences(hijriDay: 10, hijriMonth: 3, now: now, limit: 1, hijriCalendar: hijriCalendar)

        #expect(next == all.first)
        #expect(next != nil)
    }

    // MARK: - matches(...) — used by the calendar grid/day sheet

    @Test func matchesAgreesWithUpcomingOccurrencesForEveryReturnedDate() async throws {
        let currentHijriYear = hijriCalendar.component(.year, from: Date())
        var anchorComponents = DateComponents()
        anchorComponents.year = currentHijriYear
        anchorComponents.month = 9
        anchorComponents.day = 5
        let now = try #require(hijriCalendar.date(from: anchorComponents))

        let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
            hijriDay: 5, hijriMonth: 9, now: now, limit: 3, hijriCalendar: hijriCalendar
        )

        for date in occurrences {
            #expect(ZakatOccurrenceCalculator.matches(hijriDay: 5, hijriMonth: 9, date: date, hijriCalendar: hijriCalendar))
        }

        // A day one day off must never match — no off-by-one leniency.
        let dayAfter = try #require(hijriCalendar.date(byAdding: .day, value: 1, to: occurrences[0]))
        #expect(!ZakatOccurrenceCalculator.matches(hijriDay: 5, hijriMonth: 9, date: dayAfter, hijriCalendar: hijriCalendar))
    }
}
