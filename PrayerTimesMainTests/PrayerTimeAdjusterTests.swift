import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers N2/N8: minute adjustments must wrap correctly across midnight
/// without truncating, and must report which calendar day the adjusted
/// time actually lands on.
@MainActor
struct PrayerTimeAdjusterTests {

    @Test func noWrapWhenWithinSameDay() async throws {
        let result = PrayerTimeAdjuster.adjustTime("05:00", by: 10)
        #expect(result.value == "05:10")
        #expect(result.dayOffset == 0)
    }

    @Test func negativeAdjustmentWithinSameDay() async throws {
        let result = PrayerTimeAdjuster.adjustTime("05:05", by: -10)
        #expect(result.value == "04:55")
        #expect(result.dayOffset == 0)
    }

    @Test func ishaAdjustmentRollsIntoNextDay() async throws {
        // 23:50 + 20 minutes must become 00:10 on the *next* day, not get
        // clipped at 23:59 and not silently stay "today".
        let result = PrayerTimeAdjuster.adjustTime("23:50", by: 20)
        #expect(result.value == "00:10")
        #expect(result.dayOffset == 1)
    }

    @Test func exactMidnightBoundaryDoesNotRollOver() async throws {
        let result = PrayerTimeAdjuster.adjustTime("23:50", by: 10)
        #expect(result.value == "00:00")
        #expect(result.dayOffset == 1)
    }

    @Test func fajrAdjustmentRollsIntoPreviousDay() async throws {
        // 00:05 - 20 minutes must become 23:45 on the *previous* day.
        let result = PrayerTimeAdjuster.adjustTime("00:05", by: -20)
        #expect(result.value == "23:45")
        #expect(result.dayOffset == -1)
    }

    @Test func maximumPositiveAdjustmentStillWrapsOnce() async throws {
        // Adjustments are bounded to ±60 minutes in the UI, so a single wrap
        // is the worst case.
        let result = PrayerTimeAdjuster.adjustTime("23:30", by: 60)
        #expect(result.value == "00:30")
        #expect(result.dayOffset == 1)
    }

    @Test func maximumNegativeAdjustmentStillWrapsOnce() async throws {
        let result = PrayerTimeAdjuster.adjustTime("00:30", by: -60)
        #expect(result.value == "23:30")
        #expect(result.dayOffset == -1)
    }

    @Test func malformedInputIsReturnedUnchanged() async throws {
        let result = PrayerTimeAdjuster.adjustTime("not-a-time", by: 15)
        #expect(result.value == "not-a-time")
        #expect(result.dayOffset == 0)
    }

    @Test func dateForAdjustedAppliesDayOffset() async throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 12
        let base = calendar.date(from: components)!

        let rolledOver = PrayerTimeAdjuster.AdjustedTime(value: "00:10", dayOffset: 1)
        let date = PrayerTimeAdjuster.date(forAdjusted: rolledOver, base: base, calendar: calendar)

        let resultComponents = calendar.dateComponents([.day, .hour, .minute], from: date!)
        #expect(resultComponents.day == 16)
        #expect(resultComponents.hour == 0)
        #expect(resultComponents.minute == 10)
    }
}
