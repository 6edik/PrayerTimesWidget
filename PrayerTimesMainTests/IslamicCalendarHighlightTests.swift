import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the app's decision to keep *only* its curated `MajorIslamicHoliday`
/// days from AlAdhan's special-day feed: an ordinary entry like "Urs of …",
/// "Birth of …"/"Birthday …" (or any other AlAdhan-reported observance that
/// isn't one of the 8 curated cases) must never be persisted, never appear
/// in the day sheet, and never drive the calendar grid's orange highlight —
/// not even when it shares a date with a curated holiday.
///
/// `loadDays(...)` below writes directly to `SharedIslamicCalendarStore`,
/// bypassing any filter — exactly what an already-persisted cache from
/// before this filter existed looks like. Calling `viewModel.loadYear(for:
/// force: false)` afterwards exercises the cache-hit path, which now runs
/// through `IslamicHolidayClassifier.loadYearMigratingIfNeeded` — so these
/// tests double as the "old cache gets cleaned up, offline, on first touch"
/// migration coverage.
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
            personalCalendarViewModel: PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: prayerSuite)),
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

    /// Writes `days` directly into the store — unfiltered, simulating a
    /// cache written by an older app version — then loads that year into
    /// the view model via the cache-hit path (`force: false`), which is
    /// where the self-healing migration lives. No network call happens
    /// anywhere in this helper.
    private func loadDays(_ days: [IslamicSpecialDay], into viewModel: IslamicCalendarViewModel, calendarStore: SharedIslamicCalendarStore, referenceDate: Date) async {
        let year = deviceCalendar.component(.year, from: referenceDate)
        calendarStore.saveYear(year, days: days)
        await viewModel.loadYear(for: referenceDate)
    }

    // MARK: - 1. "Urs of …" only: excluded everywhere

    @Test func ursOnlyDayIsNotPersistedNotDisplayedNotHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        // hijriDay/month deliberately don't match any MajorIslamicHoliday key.
        let ursEntry = makeSpecialDay(title: "Urs of Khwaja Gharib Nawaz", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        await loadDays([ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        // Not shown in the day sheet / "Ereignisse dieses Tages":
        #expect(viewModel.allEventsForDay(date).isEmpty)
        // Not orange:
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
        // Not persisted either — the migration must have rewritten the
        // on-disk cache to no longer contain it.
        let year = deviceCalendar.component(.year, from: date)
        #expect(calendarStore.loadYear(year)?.isEmpty ?? true)
    }

    // MARK: - "Birth of …" / "Birthday …" only: same treatment

    @Test func birthOnlyDayIsNotPersistedNotDisplayedNotHighlighted() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let birthEntry = makeSpecialDay(title: "Birth of Imam Hussain", hijriDay: "3", hijriMonthNumber: 3, sortDate: date)
        await loadDays([birthEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).isEmpty)
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
        let year = deviceCalendar.component(.year, from: date)
        #expect(calendarStore.loadYear(year)?.isEmpty ?? true)
    }

    @Test func birthdayVariantSpellingIsAlsoExcluded() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let entry = makeSpecialDay(title: "Birthday of Sheikh Abdul Qadir", hijriDay: "11", hijriMonthNumber: 4, sortDate: date)
        await loadDays([entry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).isEmpty)
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
    }

    /// Guards against relying on English name fragments/prefixes: this
    /// title contains neither "Urs" nor "Birth", but its Hijri key still
    /// doesn't match any curated holiday, so it must be excluded exactly
    /// the same way.
    @Test func nonEnglishOrUnfamiliarTitleWithNonMatchingKeyIsAlsoExcluded() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let entry = makeSpecialDay(title: "Urs-e-Ghaus-e-Azam Celebration", hijriDay: "22", hijriMonthNumber: 6, sortDate: date)
        await loadDays([entry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        #expect(viewModel.allEventsForDay(date).isEmpty)
        #expect(viewModel.isHighlightedHoliday(for: date) == false)
    }

    // MARK: - 2. Selected holiday: still visible and highlighted

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

    // MARK: - 3. Relevant holiday + an unrelated "Urs of …" on a different day

    /// The common, realistic case: an "Urs of …" observance has its own,
    /// unrelated Hijri date — nowhere near one of the 8 curated holidays —
    /// so it's excluded while a genuine holiday elsewhere in the same
    /// batch survives untouched.
    @Test func curatedHolidayAndUnrelatedUrsOnADifferentDayOnlyHolidaySurvives() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let holidayDate = Date()
        let ursDate = deviceCalendar.date(byAdding: .day, value: 10, to: holidayDate)!

        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: holidayDate)
        let ursEntry = makeSpecialDay(title: "Urs of Someone", hijriDay: "6", hijriMonthNumber: 3, sortDate: ursDate)
        await loadDays([eidAlFitr, ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: holidayDate)

        #expect(viewModel.allEventsForDay(holidayDate).map(\.title) == ["Eid al-Fitr"])
        #expect(viewModel.isHighlightedHoliday(for: holidayDate) == true)
        #expect(viewModel.allEventsForDay(ursDate).isEmpty)
        #expect(viewModel.isHighlightedHoliday(for: ursDate) == false)
    }

    /// Documented, user-approved limitation: AlAdhan's data model attaches
    /// every named entry for a Gregorian day to that same day's single
    /// Hijri (day, month) — so if AlAdhan itself ever lists a second,
    /// differently-titled entry (e.g. a regional "Urs") under the *exact*
    /// same Hijri day/month as one of the 8 curated holidays, the
    /// hijriKey-only match (reused as-is from the existing Feiertage-
    /// übersicht/notification logic, never a title search) cannot tell
    /// them apart and both are treated as relevant. Confirmed acceptable:
    /// this mirrors the pre-existing overview/notification behavior
    /// exactly and only affects a genuine key collision, not the ordinary
    /// "unrelated Urs entry" case covered above.
    @Test func genuineHijriKeyCollisionKeepsBothEntriesByDesign() async throws {
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
        #expect(viewModel.isHighlightedHoliday(for: date) == true)
    }

    // MARK: - 4. Old cache with excluded events: gone after migration; offline

    @Test func oldCacheWithExcludedEventsIsCleanedAfterMigrationAndStaysCleanOffline() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)

        let date = Date()
        let year = deviceCalendar.component(.year, from: date)

        // Simulates a pre-update cache: two excluded entries, no filtering
        // applied (this is exactly what `saveYear` accepted before this
        // change, and still accepts if a caller doesn't filter — the store
        // itself is intentionally "dumb").
        let ursEntry = makeSpecialDay(title: "Urs of A", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        let birthEntry = makeSpecialDay(title: "Birth of B", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        calendarStore.saveYear(year, days: [ursEntry, birthEntry])
        #expect(calendarStore.loadYear(year)?.count == 2)

        // "App restart": a brand-new view model instance (nothing carried
        // over in memory), reading the same on-disk suite, offline —
        // `loadYear(for:)` with `force: false` never calls the network
        // service.
        let restartedViewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)
        await restartedViewModel.loadYear(for: date)

        #expect(restartedViewModel.allEventsForDay(date).isEmpty)
        #expect(calendarStore.loadYear(year)?.isEmpty == true)

        // A second, independent read (another simulated restart) sees the
        // already-migrated, still-empty state — stays clean.
        let secondRestartViewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)
        await secondRestartViewModel.loadYear(for: date)
        #expect(secondRestartViewModel.allEventsForDay(date).isEmpty)
    }

    @Test func oldCacheMixingExcludedAndRelevantMigratesToOnlyTheRelevantOnes() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)

        let date = Date()
        let year = deviceCalendar.component(.year, from: date)

        // Non-colliding Hijri key for the Urs entry — a real "Urs of …"
        // observance has its own, unrelated Hijri date; only a genuine
        // key *collision* (a separate, documented, accepted case) makes
        // the classifier unable to tell two same-keyed entries apart.
        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        let ursEntry = makeSpecialDay(title: "Urs of A", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        calendarStore.saveYear(year, days: [eidAlFitr, ursEntry])

        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)
        await viewModel.loadYear(for: date)

        #expect(viewModel.allEventsForDay(date).map(\.title) == ["Eid al-Fitr"])
        #expect(calendarStore.loadYear(year)?.count == 1)
    }

    // MARK: - 6. Unhighlighted (now: absent) event on a Monday: blue, not orange

    @Test func ursEventOnAMondayLeavesOnlyTheFastingIndicatorNotOrange() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let monday = firstJan1ThatIsAWeekday(2, searchingFrom: 2020)
        let ursEntry = makeSpecialDay(title: "Urs of Someone", hijriDay: "6", hijriMonthNumber: 3, sortDate: monday)
        await loadDays([ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: monday)

        // The event is gone entirely, and the day cell would render blue
        // (Sunnah fast day) rather than orange: the highlight is false,
        // while the independent fasting classifier still recognizes the
        // Monday (fasting logic is untouched by the event filter).
        #expect(viewModel.allEventsForDay(monday).isEmpty)
        #expect(viewModel.isHighlightedHoliday(for: monday) == false)
        let occasions = VoluntaryFastingClassifier.occasions(for: monday, gregorianCalendar: deviceCalendar, hijriCalendar: hijriCalendar)
        #expect(occasions.contains(.monday))
    }

    // MARK: - 7. Curated holiday that's also a fast day: combined state preserved

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
        // combined-state precondition (orange text + blue ring). Fasting
        // classification must never be persisted as/confused with an
        // AlAdhan special day.
        #expect(viewModel.isHighlightedHoliday(for: candidate) == true)
        #expect(occasions.contains(.monday) || occasions.contains(.thursday))
    }

    // MARK: - End-to-end through monthGridDays (what the Cell actually reads)

    @Test func monthGridDaysNeverExposeExcludedEvents() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let viewModel = makeViewModel(calendarSuite: suite1, prayerSuite: suite2)

        let date = Date()
        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        let ursEntry = makeSpecialDay(title: "Urs of Someone", hijriDay: "6", hijriMonthNumber: 3, sortDate: date)
        await loadDays([eidAlFitr, ursEntry], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        let gridDays = viewModel.monthGridDays(for: date, selectedDate: date)
        let item = try #require(gridDays.first { deviceCalendar.isDate($0.date, inSameDayAs: date) })

        #expect(item.allEventsForDay.map(\.title) == ["Eid al-Fitr"])
        #expect(item.isHighlightedHoliday == true)
    }

    // MARK: - Personal calendar entries combine with holiday/fasting highlights

    /// A personal entry on the same day as a curated holiday must not
    /// suppress (or be suppressed by) the orange highlight — both facts
    /// stay independently visible, exactly like the existing
    /// holiday+fasting combined-state guarantee above.
    @Test func personalEntryOnACuratedHolidayKeepsBothFlagsTrue() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let personalStore = PersonalCalendarStore(suiteName: suite2)
        let personalViewModel = PersonalCalendarViewModel(store: personalStore)
        let viewModel = IslamicCalendarViewModel(
            service: IslamicCalendarService(),
            prayerStore: SharedPrayerTimesStore(suiteName: suite2),
            calendarStore: calendarStore,
            personalCalendarViewModel: personalViewModel,
            settingsProvider: { AutoPrayerSettings() }
        )

        let date = Date()
        let eidAlFitr = makeSpecialDay(title: "Eid al-Fitr", hijriDay: "1", hijriMonthNumber: 10, sortDate: date)
        await loadDays([eidAlFitr], into: viewModel, calendarStore: calendarStore, referenceDate: date)

        personalViewModel.save(PersonalCalendarEntry(note: "Familienbesuch", isoDate: PersonalCalendarViewModel.isoDateString(from: date)))

        let gridDays = viewModel.monthGridDays(for: date, selectedDate: date)
        let item = try #require(gridDays.first { deviceCalendar.isDate($0.date, inSameDayAs: date) })

        #expect(item.isHighlightedHoliday == true)
        #expect(item.hasPersonalEntries == true)
    }

    /// A personal entry on a Sunnah-fasting day (Monday/Thursday/White
    /// Day) must not interfere with `VoluntaryFastingClassifier`'s
    /// classification — the two systems are fully independent (fasting
    /// depends only on the date, `hasPersonalEntries` only on the
    /// personal-entries store), so both can be true for the same day.
    @Test func personalEntryOnASunnahFastingDayDoesNotAffectFastingClassification() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName()
        defer { cleanup([suite1, suite2]) }
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite1)
        let personalStore = PersonalCalendarStore(suiteName: suite2)
        let personalViewModel = PersonalCalendarViewModel(store: personalStore)
        let viewModel = IslamicCalendarViewModel(
            service: IslamicCalendarService(),
            prayerStore: SharedPrayerTimesStore(suiteName: suite2),
            calendarStore: calendarStore,
            personalCalendarViewModel: personalViewModel,
            settingsProvider: { AutoPrayerSettings() }
        )

        let monday = firstJan1ThatIsAWeekday(2, searchingFrom: 2020)
        personalViewModel.save(PersonalCalendarEntry(note: "Sport", isoDate: PersonalCalendarViewModel.isoDateString(from: monday)))

        let occasions = VoluntaryFastingClassifier.occasions(for: monday, gregorianCalendar: deviceCalendar, hijriCalendar: hijriCalendar)
        #expect(occasions.contains(.monday))

        let gridDays = viewModel.monthGridDays(for: monday, selectedDate: monday)
        let item = try #require(gridDays.first { deviceCalendar.isDate($0.date, inSameDayAs: monday) })
        #expect(item.hasPersonalEntries == true)
        #expect(item.isHighlightedHoliday == false)
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
