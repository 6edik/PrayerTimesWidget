import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers N6/N1: Home screen, widget and calendar tab must all derive the
/// Hijri date the same way — `Calendar(identifier: .islamicUmmAlQura)`,
/// computed locally from the Gregorian date — instead of trusting the
/// AlAdhan API's own (possibly differently-adjusted) Hijri string.
@MainActor
struct HijriDateFormattingTests {
    private func gregorianDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func dayTextMatchesIndependentlyComputedUmmAlQuraDay() async throws {
        let date = gregorianDate(year: 2026, month: 3, day: 15)

        var reference = Calendar(identifier: .islamicUmmAlQura)
        reference.timeZone = .autoupdatingCurrent
        let expectedDay = reference.component(.day, from: date)

        #expect(HijriDateFormatting.dayText(for: date) == String(expectedDay))
    }

    @Test func dayAndMonthAgreeWithDayText() async throws {
        let date = gregorianDate(year: 2026, month: 9, day: 26)
        let (day, _) = HijriDateFormatting.dayAndMonth(for: date)

        #expect(String(day) == HijriDateFormatting.dayText(for: date))
    }

    @Test func monthNumberStaysWithinValidRange() async throws {
        let date = gregorianDate(year: 2026, month: 1, day: 1)
        let (_, month) = HijriDateFormatting.dayAndMonth(for: date)

        #expect(month >= 1 && month <= 12)
    }

    @Test func displayTextContainsTheDayNumber() async throws {
        let date = gregorianDate(year: 2026, month: 6, day: 10)
        let day = HijriDateFormatting.dayText(for: date)

        #expect(HijriDateFormatting.displayText(for: date).contains(day))
    }
}
