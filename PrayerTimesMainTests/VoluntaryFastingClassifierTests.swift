import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `VoluntaryFastingClassifier` in isolation: Monday/Thursday/White-Day
/// detection, the day-before/day-after boundaries of the White Days window,
/// combined occasions on the same date, and the religious-exclusion rule
/// (Ramadan, both Eids, the three days of Tashriq) — including the
/// specifically tricky case of 13 Dhu'l-Hijjah, which is simultaneously a
/// White Day *and* a Tashriq day and must be excluded.
@MainActor
struct VoluntaryFastingClassifierTests {
    private var hijriCalendar: Calendar {
        HijriDateFormatting.calendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Builds the real Gregorian `Date` corresponding to a given Hijri
    /// (day, month, year) — self-consistent with the same
    /// `Calendar(identifier: .islamicUmmAlQura)` source the app uses
    /// everywhere else, so these tests never need to hardcode a
    /// real-world Gregorian/Hijri correspondence from memory.
    private func hijriDate(day: Int, month: Int, year: Int) -> Date {
        var comps = DateComponents()
        comps.day = day
        comps.month = month
        comps.year = year
        return hijriCalendar.date(from: comps)!
    }

    // MARK: - Weekday occasions

    @Test func mondayIsDetected() async throws {
        // Jan 1, 2024 is a known Monday; found programmatically below
        // rather than trusted from memory, so a wrong assumption here
        // would fail loudly instead of silently validating the wrong day.
        let monday = firstJan1ThatIsAWeekday(2, searchingFrom: 2020)
        let occasions = VoluntaryFastingClassifier.occasions(
            for: monday, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar
        )
        #expect(occasions.contains(.monday))
        #expect(!occasions.contains(.thursday))
    }

    @Test func thursdayIsDetected() async throws {
        let thursday = firstJan1ThatIsAWeekday(5, searchingFrom: 2020)
        let occasions = VoluntaryFastingClassifier.occasions(
            for: thursday, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar
        )
        #expect(occasions.contains(.thursday))
        #expect(!occasions.contains(.monday))
    }

    @Test func otherWeekdaysMatchNeitherMondayNorThursday() async throws {
        let tuesday = firstJan1ThatIsAWeekday(3, searchingFrom: 2020)
        let occasions = VoluntaryFastingClassifier.occasions(
            for: tuesday, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar
        )
        #expect(!occasions.contains(.monday))
        #expect(!occasions.contains(.thursday))
    }

    // MARK: - White Days

    @Test func hijri13IsAWhiteDay() async throws {
        // Rabi' al-awwal (month 3) has no exclusion, keeping this test
        // focused purely on the White-Day boundary.
        let date = hijriDate(day: 13, month: 3, year: 1447)
        #expect(VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar).contains(.whiteDay))
    }

    @Test func hijri14IsAWhiteDay() async throws {
        let date = hijriDate(day: 14, month: 3, year: 1447)
        #expect(VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar).contains(.whiteDay))
    }

    @Test func hijri15IsAWhiteDay() async throws {
        let date = hijriDate(day: 15, month: 3, year: 1447)
        #expect(VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar).contains(.whiteDay))
    }

    @Test func hijri12IsNotYetAWhiteDay() async throws {
        let date = hijriDate(day: 12, month: 3, year: 1447)
        #expect(!VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar).contains(.whiteDay))
    }

    @Test func hijri16IsNoLongerAWhiteDay() async throws {
        let date = hijriDate(day: 16, month: 3, year: 1447)
        #expect(!VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar).contains(.whiteDay))
    }

    // MARK: - Combined occasions

    @Test func aDateCanBeBothAWeekdayOccasionAndAWhiteDay() async throws {
        // Search forward from a White Day for one that also happens to be
        // a Monday or Thursday, rather than assuming a specific year does
        // this — guarantees the test is checking a real combined date.
        var candidate = hijriDate(day: 13, month: 3, year: 1447)
        var occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar)

        var guardCounter = 0
        while !(occasions.contains(.monday) || occasions.contains(.thursday)), guardCounter < 60 {
            // Advance by one full Hijri year (still landing on a White Day
            // of the same Hijri month/day, different Gregorian weekday).
            candidate = hijriCalendar.date(byAdding: .year, value: 1, to: candidate)!
            occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar)
            guardCounter += 1
        }

        #expect(occasions.contains(.whiteDay))
        #expect(occasions.contains(.monday) || occasions.contains(.thursday))
    }

    // MARK: - Religious exclusions

    @Test func everyDayOfRamadanIsExcluded() async throws {
        for day in [1, 15, 29] {
            let date = hijriDate(day: day, month: 9, year: 1447)
            #expect(VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
        }
    }

    @Test func eidAlFitrIsExcluded() async throws {
        let date = hijriDate(day: 1, month: 10, year: 1447)
        #expect(VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
    }

    @Test func dayAfterEidAlFitrIsNotExcluded() async throws {
        let date = hijriDate(day: 2, month: 10, year: 1447)
        #expect(!VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
    }

    @Test func eidAlAdhaIsExcluded() async throws {
        let date = hijriDate(day: 10, month: 12, year: 1447)
        #expect(VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
    }

    @Test func allThreeTashriqDaysAreExcluded() async throws {
        for day in [11, 12, 13] {
            let date = hijriDate(day: day, month: 12, year: 1447)
            #expect(VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
        }
    }

    /// The tricky case explicitly called out in the classifier's doc
    /// comment: 13 Dhu'l-Hijjah is simultaneously a White Day *and* the
    /// last Tashriq day — the exclusion must win.
    @Test func thirteenthOfDhulHijjahIsExcludedDespiteBeingAWhiteDay() async throws {
        let date = hijriDate(day: 13, month: 12, year: 1447)
        let occasions = VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar)

        #expect(occasions.contains(.whiteDay))
        #expect(VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
    }

    @Test func fourteenthOfDhulHijjahIsAWhiteDayAndNotExcluded() async throws {
        // One day after the last Tashriq day — still a White Day, no
        // longer excluded. Guards against an off-by-one that would
        // suppress every White Day in Dhu'l-Hijjah, not just the Tashriq
        // overlap.
        let date = hijriDate(day: 14, month: 12, year: 1447)
        let occasions = VoluntaryFastingClassifier.occasions(for: date, gregorianCalendar: gregorianCalendar, hijriCalendar: hijriCalendar)

        #expect(occasions.contains(.whiteDay))
        #expect(!VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
    }

    @Test func ordinaryDayIsNotExcluded() async throws {
        let date = hijriDate(day: 20, month: 3, year: 1447)
        #expect(!VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: date, hijriCalendar: hijriCalendar))
    }

    // MARK: - Display label

    @Test func displayLabelForSingleOccasion() async throws {
        #expect(VoluntaryFastingOccasions.monday.displayLabel == "Montag")
    }

    @Test func displayLabelForTwoOccasions() async throws {
        let occasions: VoluntaryFastingOccasions = [.monday, .whiteDay]
        #expect(occasions.displayLabel == "Montag und Weißer Tag")
    }

    // MARK: - Helper

    /// Searches forward year by year for the first `year >= startingYear`
    /// whose January 1st falls on `weekday` (Foundation's convention:
    /// Sunday = 1 ... Saturday = 7). Self-verifying — never assumes a
    /// specific year's calendar from memory.
    private func firstJan1ThatIsAWeekday(_ weekday: Int, searchingFrom startingYear: Int) -> Date {
        var year = startingYear
        while true {
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            let date = gregorianCalendar.date(from: comps)!
            if gregorianCalendar.component(.weekday, from: date) == weekday {
                return date
            }
            year += 1
        }
    }
}
