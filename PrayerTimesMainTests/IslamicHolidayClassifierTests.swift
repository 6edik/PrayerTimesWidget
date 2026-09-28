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

    // MARK: - filterRelevant

    @Test func filterRelevantDropsUrsAndBirthEntries() async throws {
        let urs = makeSpecialDay(hijriDay: "6", hijriMonthNumber: 3)
        let birth = makeSpecialDay(hijriDay: "11", hijriMonthNumber: 4)
        let filtered = IslamicHolidayClassifier.filterRelevant([urs, birth], hijriCalendar: hijriCalendar)
        #expect(filtered.isEmpty)
    }

    @Test func filterRelevantKeepsCuratedHolidaysOnly() async throws {
        let eidAlFitr = makeSpecialDay(hijriDay: "1", hijriMonthNumber: 10)
        let urs = makeSpecialDay(hijriDay: "6", hijriMonthNumber: 3)
        let filtered = IslamicHolidayClassifier.filterRelevant([eidAlFitr, urs], hijriCalendar: hijriCalendar)
        #expect(filtered.count == 1)
        #expect(filtered.first?.hijriDay == "1")
    }

    @Test func filterRelevantPreservesAllCuratedHolidaysWhenSeveralPresent() async throws {
        let allHolidayDays = MajorIslamicHoliday.allCases.map {
            makeSpecialDay(hijriDay: String($0.hijriKey.day), hijriMonthNumber: $0.hijriKey.month)
        }
        let filtered = IslamicHolidayClassifier.filterRelevant(allHolidayDays, hijriCalendar: hijriCalendar)
        #expect(filtered.count == allHolidayDays.count)
    }

    // MARK: - loadYearMigratingIfNeeded

    private func makeStoreSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    @Test func loadYearMigratingIfNeededReturnsNilWhenNothingCached() async throws {
        let suite = makeStoreSuiteName()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SharedIslamicCalendarStore(suiteName: suite)

        #expect(IslamicHolidayClassifier.loadYearMigratingIfNeeded(2026, store: store, hijriCalendar: hijriCalendar) == nil)
    }

    @Test func loadYearMigratingIfNeededCleansUpAndRePersistsStaleData() async throws {
        let suite = makeStoreSuiteName()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SharedIslamicCalendarStore(suiteName: suite)

        // Simulates a cache written before the filter existed — the store
        // itself is "dumb" and accepts whatever it's given.
        let eidAlFitr = makeSpecialDay(hijriDay: "1", hijriMonthNumber: 10)
        let urs = makeSpecialDay(hijriDay: "1", hijriMonthNumber: 10)
        store.saveYear(2026, days: [eidAlFitr, urs])
        #expect(store.loadYear(2026)?.count == 2)

        let migrated = IslamicHolidayClassifier.loadYearMigratingIfNeeded(2026, store: store, hijriCalendar: hijriCalendar)
        #expect(migrated?.count == 1)

        // The on-disk copy itself was rewritten — a later, independent read
        // (e.g. a fresh app launch) sees the cleaned-up version directly,
        // without needing to migrate again.
        #expect(store.loadYear(2026)?.count == 1)
    }

    @Test func loadYearMigratingIfNeededIsANoOpWhenAlreadyClean() async throws {
        let suite = makeStoreSuiteName()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SharedIslamicCalendarStore(suiteName: suite)

        let eidAlFitr = makeSpecialDay(hijriDay: "1", hijriMonthNumber: 10)
        store.saveYear(2026, days: [eidAlFitr])

        let result = IslamicHolidayClassifier.loadYearMigratingIfNeeded(2026, store: store, hijriCalendar: hijriCalendar)
        #expect(result?.count == 1)
        #expect(store.loadYear(2026)?.count == 1)
    }
}
