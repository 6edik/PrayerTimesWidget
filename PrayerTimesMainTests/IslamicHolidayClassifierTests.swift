import Testing
import Foundation
@testable import PrayerTimesMain

@MainActor
struct IslamicHolidayClassifierTests {
    private var hijriCalendar: Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private func makeSpecialDay(
        hijriDay: String,
        hijriMonthNumber: Int?,
        sortDate: Date = Date()
    ) -> IslamicSpecialDay {
        IslamicSpecialDay(
            title: "Test",
            gregorianReadable: "1 Jan 2026",
            gregorianMonthName: "January",
            gregorianYear: "2026",
            hijriDay: hijriDay,
            hijriMonth: "Test Month",
            hijriYear: "1447",
            hijriWeekday: "Monday",
            sortDate: sortDate,
            hijriMonthNumber: hijriMonthNumber
        )
    }

    @Test func recognizesEidAlFitrViaAlAdhansOwnHijriFields() async throws {
        let day = makeSpecialDay(hijriDay: "1", hijriMonthNumber: 10)
        #expect(IslamicHolidayClassifier.isMajorHoliday(day, hijriCalendar: hijriCalendar))
        #expect(IslamicHolidayClassifier.majorHoliday(for: day, hijriCalendar: hijriCalendar) == .eidAlFitr)
    }

    @Test func nonHolidayDayIsNotClassifiedAsMajor() async throws {
        let day = makeSpecialDay(hijriDay: "15", hijriMonthNumber: 3)
        #expect(!IslamicHolidayClassifier.isMajorHoliday(day, hijriCalendar: hijriCalendar))
    }

    @Test func allEightHolidaysAreRecognizedByTheirAlAdhanFields() async throws {
        for holiday in MajorIslamicHoliday.allCases {
            let day = makeSpecialDay(hijriDay: String(holiday.hijriKey.day), hijriMonthNumber: holiday.hijriKey.month)
            #expect(
                IslamicHolidayClassifier.majorHoliday(for: day, hijriCalendar: hijriCalendar) == holiday,
                "Expected \(holiday) to round-trip through its own hijriKey"
            )
        }
    }

    @Test func fallsBackToRecomputingFromSortDateWhenMonthNumberIsMissing() async throws {
        // Legacy cache entries (pre-hijriMonthNumber) — the fallback must
        // still produce *some* key rather than crashing/returning nil for
        // every entry.
        let day = makeSpecialDay(hijriDay: "1", hijriMonthNumber: nil, sortDate: Date())
        let key = IslamicHolidayClassifier.hijriHolidayKey(for: day, hijriCalendar: hijriCalendar)
        #expect(key != nil)
    }

    @Test func majorHolidayKeysHasExactlyEightEntries() async throws {
        // One entry per MajorIslamicHoliday case, no duplicates/collisions.
        #expect(IslamicHolidayClassifier.majorHolidayKeys.count == MajorIslamicHoliday.allCases.count)
    }
}
