import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the split between "all AlAdhan events for a day" (unfiltered,
/// feeds the day sheet) and "is this day a highlighted holiday" (drives the
/// calendar grid's orange date number). Specifically guards against the bug
/// this was written to fix: an ordinary AlAdhan entry like "Urs of …" or
/// "Birth of …" must be visible in the day sheet but must never turn the
/// date number orange — only one of the app's curated `MajorIslamicHoliday`
/// cases (matched via `IslamicHolidayClassifier`, never a title search) may
/// do that. Also covers that the highlight is independent of, and
/// combinable with, the separate Monday/Thursday/White-Day fasting
/// indicator.
@MainActor
struct IslamicCalendarHighlightTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteNames: [String]) {
        for suite in suiteNames {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private func makeViewModel(calendarSuite: String, prayerSuite: String) -> IslamicCalendarViewModel {
        IslamicCalendarViewModel(
            service: IslamicCalendarService(),
            prayerStore: SharedPrayerTimesStore(suiteName: prayerSuite),
            calendarStore: SharedIslamicCalendarStore(suiteName: calendarSuite),
            settingsProvider: { AutoPrayerSettings() }
        )
    }

    private func makeSpecialDay(
        title: String,
        hijriDay: String,
        hijriMonthNumber: Int?,
        sortDate: Date
    ) -> IslamicSpecialDay {
        IslamicSpecialDay(
            title: title,
            gregorianReadable: "Test",
            gregorianMonthName: "Test",
            gregorianYear: "2026",
            hijriDay: hijriDay,
            hijriMonth: "Test Month",
            hijriYear: "1447",
            hijriWeekday: "Test",
            sortDate: sortDate,
            hijriMonthNumber: hijriMonthNumber
        )
    }

    private var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var hijriCalendar: Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    /// Seeds the calendar-year cache directly (no network call — `loadYear`
    /// finds this and returns immediately) and loads it into the view model.
    private func loadDays(_ days: [IslamicSpecialDay], into viewModel: IslamicCalendarViewModel, calendarStore: SharedIslamicCalendarStore, referenceDate: Date) async {
        let year = deviceCalendar.component(.year, from: referenceDate)
        calendarStore.saveYear(year, days: days)
        await viewModel.loadYear(for: referenceDate)
    }

    // MARK: - 1. "Urs of …" / "Birth of …": visible, never orange

    @Test func ursEntryIsVisibleInDaySheetButNotHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        // hijriDay/month deliberately don't match any MajorIslamicHoliday key.
        let ursEntry = makeSpecialDay(title: "Urs of Khwaja Gharib Nawaz", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        await loadDays([ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        let dayEvents = viewModel.allEventsForDay(date)
        #expect(dayEvents.count == 1)
        #expect(dayEvents.first?.title == "Urs of Khwaja Gharib Nawaz")
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
    }

    @Test func birthEntryIsVisibleInDaySheetButNotHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let birthEntry = makeSpecialDay(title: "Birth of Imam Hussain", hijriDay: "3", hijriMonthNumber: 3, sortDate: date)
        await loadDays([birthEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).contains { $0.title == "Birth of Imam Hussain" })
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
    }

    /// Explicit guard against the exact regression the spec warns about:
    /// a title that *contains* "Eid" but whose Hijri day/month don't match
    /// any curated holiday key must not be highlighted — proves the
    /// decision is a Hijri-key match, not a string search over the title.
    @Test func titleContainingEidButWrongHijriKeyIsNotHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        // "Eid" in the title, but day/month don't match eidAlFitr (1/10) or
        // eidAlAdha (10/12).
        let decoy = makeSpecialDay(title: "Eid Milad an-Nabi", hijriDay: "12", hijriMonthNumber: 3, sortDate: date)
        await loadDays([decoy], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).contains { $0.title == "Eid Milad an-Nabi" })
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
    }

    // MARK: - 2. Selected holiday: visible and highlighted

    @Test func curatedHolidayIsVisibleAndHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        await loadDays([eidAlFitr], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).contains { $0.title == "Eid al-Fitr" })
        #expect(viewModel.isHighlightedHoliday(for: date) == true)
    }

    // MARK: - 3. Unhighlighted event on a Monday: blue, not orange

    @Test func unhighlightedEventOnAMondayStaysBlueNotOrange() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let monday = firstJan1ThatIsAWeekday(2, searchingFrom: 2020)
        let ursEntry = makeSpecialDay(title: "Urs of Someone", hijriDay: "6", hijriMonthNumber: 3, sortDate: monday)
        await loadDays([ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: monday)

        // Confirms the Cell would render blue (Sunnah fast day) rather than
        // orange: the highlight is false, while the independent fasting
        // classifier does recognize the Monday.
        #expect(viewModel.isHighlightedHoliday(for: monday) == false)
        let occasions = VoluntaryFastingClassifier.occasions(for: monday, gregorianCalendar: deviceCalendar, hijriCalendar: hijriCalendar)
        #expect(occasions.contains(.monday))
    }

    // MARK: - 4. Curated holiday that's also a fast day: combined state

    @Test func curatedHolidayThatIsAlsoAFastDayProducesCombinedState() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        // Search for a real date where Eid al-Fitr (1 Shawwal) falls on a
        // Monday or Thursday, stepping a full Hijri year at a time.
        var comps = DateComponents(); comps.day = 1; comps.month = 10; comps.year = 1447
        var candidate = hijriCalendar.date(from: comps)!
        var occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: deviceCalendar, hijriCalendar: hijriCalendar)
        var guardCounter = 0
        while !(occasions.contains(.monday) || occasions.contains(.thursday)), guardCounter < 60 {
            candidate = hijriCalendar.date(byAdding: .year, value: 1, to: candidate)!
            occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: deviceCalendar, hijriCalendar: hijriCalendar)
            guardCounter += 1
        }
        #expect(guardCounter < 60)

        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: candidate)
        await loadDays([eidAlFitr], into: viewModel, calendarStore: calendarStore, referenceDate: candidate)

        // Both facts must hold at once — this is exactly the Cell's
        // combined-state precondition (orange text + blue ring).
        #expect(viewModel.isHighlightedHoliday(for: candidate) == true)
        #expect(occasions.contains(.monday) || occasions.contains(.thursday))
    }

    // MARK: - 5. Multiple events on the same day

    @Test func multipleEventsSameDayAllVisibleHighlightFromHolidayOnly() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        let ursEntry = makeSpecialDay(title: "Urs of Someone", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        await loadDays([eidAlFitr, ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        let dayEvents = viewModel.allEventsForDay(date)
        #expect(dayEvents.count == 2)
        #expect(dayEvents.contains { $0.title == "Eid al-Fitr" })
        #expect(dayEvents.contains { $0.title == "Urs of Someone" })
        // Highlight still true — driven by the presence of the curated
        // holiday, unaffected by the extra ordinary event.
        #expect(viewModel.isHighlightedHoliday(for: date) == true)
    }

    @Test func multipleOrdinaryEventsSameDayNoneHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let first = makeSpecialDay(title: "Urs of A", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        let second = makeSpecialDay(title: "Birth of B", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        await loadDays([first, second], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).count == 2)
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
    }

    // MARK: - End-to-end through monthGridDays (what the Cell actually reads)

    @Test func monthGridDaysWireAllEventsAndHighlightCorrectly() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        let ursEntry = makeSpecialDay(title: "Urs of Someone", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        await loadDays([eidAlFitr, ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        let gridDays = viewModel.monthGridDays(for: date, selectedDate: date)
        let item = try #require(gridDays.first { deviceCalendar.isDate($0.date, inSameDayAs: date) })

        #expect(item.allEventsForDay.count == 2)
        #expect(item.isHighlightedHoliday == true)
    }

    // MARK: - Helper

    private func firstJan1ThatIsAWeekday(_ weekday: Int, searchingFrom startingYear: Int) -> Date {
        var year = startingYear
        while true {
            var comps = DateComponents()
            comps.year = year
            comps.month = 1
            comps.day = 1
            let date = deviceCalendar.date(from: comps)!
            if deviceCalendar.component(.weekday, from: date) == weekday {
                return date
            }
            year += 1
        }
    }
}
