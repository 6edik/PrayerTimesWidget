import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `NotificationScheduler.fastingCandidates`: Monday/Thursday reminders
/// anchored to the *previous* day's Maghrib, all three White Days, combining
/// Monday+White-Day into a single notification, month/year boundary crossing,
/// a non-Berlin location timezone, minute-adjustment-driven duration changes,
/// missing/invalid prayer-time data producing no invented duration, religious
/// exclusion (Ramadan/Eid/Tashriq), disabled toggles, a missing eve (no fire
/// time to anchor to), and a location change never serving the old city's
/// times.
@MainActor
struct NotificationSchedulerFastingTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteNames: [String]) {
        for suite in suiteNames {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private func makeScheduler(
        timesStore: SharedPrayerTimesStore,
        settingsStore: SharedPrayerSettingsStore,
        calendarStore: SharedIslamicCalendarStore
    ) -> NotificationScheduler {
        NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )
    }

    private func makeTimes(fajr: String, maghrib: String, timezone: String = "Europe/Berlin") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr, shuruk: "07:00", dhuhr: "12:00", asr: "15:00",
            maghrib: maghrib, isha: "20:00",
            readableDate: "Test", readableDay: "Test",
            hijriDate: "Test", hijriDay: "Test",
            timezone: timezone
        )
    }

    private func isoString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func hijriCalendar(timeZone: TimeZone) -> Calendar {
        HijriDateFormatting.calendar(timeZone: timeZone)
    }

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Next occurrence of `weekday` (Foundation convention: Sun=1...Sat=7)
    /// on/after `date` whose Hijri classification is *not* one of the
    /// excluded religious days — searching in whole-week jumps so the
    /// found date is guaranteed to still be the same weekday.
    private func nextSafeWeekday(_ weekday: Int, onOrAfter date: Date, timeZone: TimeZone) -> Date {
        let gregorian = gregorianCalendar(timeZone: timeZone)
        let hijri = hijriCalendar(timeZone: timeZone)

        var comps = DateComponents()
        comps.weekday = weekday
        var candidate = gregorian.nextDate(after: date.addingTimeInterval(-1), matching: comps, matchingPolicy: .nextTime)!

        while VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: candidate, hijriCalendar: hijri) {
            candidate = gregorian.date(byAdding: .day, value: 7, to: candidate)!
        }
        return candidate
    }

    private func makeAutoSettings(
        address: String = "Berlin, DE",
        coordinate: GeoCoordinate = GeoCoordinate(latitude: 52.52, longitude: 13.405),
        adjustments: PrayerAdjustments = .zero
    ) -> AutoPrayerSettings {
        AutoPrayerSettings(
            address: address,
            location: PrayerLocation(name: address, coordinate: coordinate),
            method: .ditib,
            adjustments: adjustments
        )
    }

    private func makeCache(for settings: AutoPrayerSettings, days: [PrayerDay]) -> PrayerTimesCache {
        PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: days
        )
    }

    private func enableAllFasting(minutesAfterMaghrib: Int = 10) -> NotificationSettings {
        var settings = NotificationSettings.zero
        settings.voluntaryFasting = VoluntaryFastingNotificationSetting(
            monday: true, thursday: true, whiteDays: true,
            minutesAfterMaghrib: minutesAfterMaghrib, sound: .standard
        )
        return settings
    }

    // MARK: - Monday anchored to Sunday's Maghrib

    @Test func mondayReminderIsScheduledAfterSundaysMaghribNotMondaysOwn() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let sunday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: monday)!

        let mondayISO = isoString(monday, timeZone: berlin)
        let sundayISO = isoString(sunday, timeZone: berlin)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: sundayISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: mondayISO, hijri: nil, times: makeTimes(fajr: "04:30", maghrib: "20:30"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        let candidate = try #require(candidates.first { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(mondayISO)" })

        let expectedFire = PrayerMomentResolver.resolve(
            isoDate: sundayISO, rawTime: "18:00", adjustmentMinutes: 0, timezoneIdentifier: "Europe/Berlin"
        )!.addingTimeInterval(10 * 60)

        #expect(abs(candidate.fireDate.timeIntervalSince(expectedFire)) < 1)
        #expect(candidate.body.contains("Montag"))
        // Fajr 04:30 -> Maghrib 20:30 = 16 Std. exactly — but no clock
        // times in the body, only the occasion and the duration.
        #expect(candidate.body.contains("Fastendauer: ca. 16 Std."))
        #expect(!candidate.body.contains("Fajr"))
        #expect(!candidate.body.contains("Maghrib"))
    }

    @Test func thursdayReminderIsScheduledAfterWednesdaysMaghrib() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        let thursday = nextSafeWeekday(5, onOrAfter: Date(), timeZone: berlin)
        let wednesday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: thursday)!

        let thursdayISO = isoString(thursday, timeZone: berlin)
        let wednesdayISO = isoString(wednesday, timeZone: berlin)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: wednesdayISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:15")),
            PrayerDay(isoDate: thursdayISO, hijri: nil, times: makeTimes(fajr: "04:45", maghrib: "20:15"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        let candidate = try #require(candidates.first { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(thursdayISO)" })

        let expectedFire = PrayerMomentResolver.resolve(
            isoDate: wednesdayISO, rawTime: "18:15", adjustmentMinutes: 0, timezoneIdentifier: "Europe/Berlin"
        )!.addingTimeInterval(10 * 60)

        #expect(abs(candidate.fireDate.timeIntervalSince(expectedFire)) < 1)
        #expect(candidate.body.contains("Donnerstag"))
    }

    // MARK: - White Days

    @Test func allThreeWhiteDaysProduceReminders() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let hijri = hijriCalendar(timeZone: berlin)
        let gregorian = gregorianCalendar(timeZone: berlin)
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        // Rabi' al-awwal (month 3): no exclusion window nearby.
        var comps = DateComponents(); comps.day = 13; comps.month = 3; comps.year = 1447
        let day13 = hijri.date(from: comps)!
        let day14 = gregorian.date(byAdding: .day, value: 1, to: day13)!
        let day15 = gregorian.date(byAdding: .day, value: 1, to: day14)!
        let eveOf13 = gregorian.date(byAdding: .day, value: -1, to: day13)!

        var days: [PrayerDay] = []
        for (date, fajr, maghrib) in [
            (eveOf13, "05:10", "18:10"),
            (day13, "05:00", "18:00"),
            (day14, "05:00", "18:00"),
            (day15, "05:00", "18:00")
        ] {
            days.append(PrayerDay(isoDate: isoString(date, timeZone: berlin), hijri: nil, times: makeTimes(fajr: fajr, maghrib: maghrib)))
        }
        timesStore.replaceCache(with: makeCache(for: autoSettings, days: days))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        for date in [day13, day14, day15] {
            let iso = isoString(date, timeZone: berlin)
            #expect(candidates.contains { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(iso)" && $0.body.contains("Weißer Tag") })
        }
    }

    // MARK: - Combined occasion: exactly one notification

    @Test func mondayThatIsAlsoAWhiteDayProducesExactlyOneCandidate() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let hijri = hijriCalendar(timeZone: berlin)
        let gregorian = gregorianCalendar(timeZone: berlin)
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        // Search for a White Day (month 3, day 13) that also lands on a
        // Monday or Thursday, by stepping a full Hijri year at a time.
        var comps = DateComponents(); comps.day = 13; comps.month = 3; comps.year = 1447
        var candidate = hijri.date(from: comps)!
        var occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: gregorian, hijriCalendar: hijri)
        var guardCounter = 0
        while !(occasions.contains(.monday) || occasions.contains(.thursday)), guardCounter < 60 {
            candidate = hijri.date(byAdding: .year, value: 1, to: candidate)!
            occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: gregorian, hijriCalendar: hijri)
            guardCounter += 1
        }
        #expect(guardCounter < 60)

        let eve = gregorian.date(byAdding: .day, value: -1, to: candidate)!
        let iso = isoString(candidate, timeZone: berlin)
        let eveISO = isoString(eve, timeZone: berlin)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: eveISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        let matchingCandidates = candidates.filter { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(iso)" }
        #expect(matchingCandidates.count == 1)

        let body = matchingCandidates[0].body
        #expect(body.contains("Weißer Tag"))
        #expect(body.contains(occasions.contains(.monday) ? "Montag" : "Donnerstag"))
    }

    // MARK: - Month/year boundary

    @Test func mondayReminderWorksAcrossAYearBoundary() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let gregorian = gregorianCalendar(timeZone: berlin)
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        // Find a year whose January 1st is a Monday, so the eve (Dec 31 of
        // the previous year) crosses both the month and the year boundary.
        var year = 2020
        var jan1: Date
        while true {
            var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
            jan1 = gregorian.date(from: comps)!
            if gregorian.component(.weekday, from: jan1) == 2 { break }
            year += 1
        }
        let dec31 = gregorian.date(byAdding: .day, value: -1, to: jan1)!

        let jan1ISO = isoString(jan1, timeZone: berlin)
        let dec31ISO = isoString(dec31, timeZone: berlin)
        #expect(dec31ISO.hasSuffix("12-31"))
        #expect(jan1ISO.hasSuffix("01-01"))

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: dec31ISO, hijri: nil, times: makeTimes(fajr: "07:30", maghrib: "16:20")),
            PrayerDay(isoDate: jan1ISO, hijri: nil, times: makeTimes(fajr: "07:31", maghrib: "16:21"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        let candidate = try #require(candidates.first { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(jan1ISO)" })
        let expectedFire = PrayerMomentResolver.resolve(
            isoDate: dec31ISO, rawTime: "16:20", adjustmentMinutes: 0, timezoneIdentifier: "Europe/Berlin"
        )!.addingTimeInterval(10 * 60)

        #expect(abs(candidate.fireDate.timeIntervalSince(expectedFire)) < 1)
    }

    // MARK: - Different location timezone

    @Test func nonBerlinLocationTimezoneIsUsedForClassificationAndFireTime() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let autoSettings = makeAutoSettings(address: "Tokyo, JP")
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: tokyo)
        let sunday = gregorianCalendar(timeZone: tokyo).date(byAdding: .day, value: -1, to: monday)!

        let mondayISO = isoString(monday, timeZone: tokyo)
        let sundayISO = isoString(sunday, timeZone: tokyo)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: sundayISO, hijri: nil, times: makeTimes(fajr: "04:50", maghrib: "17:40", timezone: "Asia/Tokyo")),
            PrayerDay(isoDate: mondayISO, hijri: nil, times: makeTimes(fajr: "04:51", maghrib: "17:41", timezone: "Asia/Tokyo"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        let candidate = try #require(candidates.first { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(mondayISO)" })
        let expectedFire = PrayerMomentResolver.resolve(
            isoDate: sundayISO, rawTime: "17:40", adjustmentMinutes: 0, timezoneIdentifier: "Asia/Tokyo"
        )!.addingTimeInterval(10 * 60)

        #expect(abs(candidate.fireDate.timeIntervalSince(expectedFire)) < 1)
    }

    // MARK: - Adjustment changes the displayed duration

    @Test func fajrAndMaghribAdjustmentChangeTheDisplayedDuration() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        var adjustments = PrayerAdjustments.zero
        adjustments.fajr = -10 // Fajr 10 minutes earlier
        adjustments.maghrib = 10 // Maghrib 10 minutes later
        let autoSettings = makeAutoSettings(adjustments: adjustments)
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let sunday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: monday)!
        let mondayISO = isoString(monday, timeZone: berlin)
        let sundayISO = isoString(sunday, timeZone: berlin)

        // Raw: Fajr 04:30, Maghrib 20:00 -> raw duration 15h30m.
        // Adjusted: Fajr 04:20, Maghrib 20:10 -> adjusted duration 15h50m.
        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: sundayISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: mondayISO, hijri: nil, times: makeTimes(fajr: "04:30", maghrib: "20:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidate = try #require(
            scheduler.fastingCandidates(settings: enableAllFasting())
                .first { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(mondayISO)" }
        )

        #expect(candidate.body.contains("Fastendauer: ca. 15 Std. 50 Min."))
        #expect(!candidate.body.contains("Fajr"))
        #expect(!candidate.body.contains("Maghrib"))
    }

    // MARK: - Missing/invalid prayer times: no invented duration

    @Test func malformedFastingDayTimeProducesReminderWithoutInventedDuration() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let sunday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: monday)!
        let mondayISO = isoString(monday, timeZone: berlin)
        let sundayISO = isoString(sunday, timeZone: berlin)

        // Eve's Maghrib is valid (so a fire time exists), but the fasting
        // day's own Fajr is corrupted/unparseable.
        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: sundayISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: mondayISO, hijri: nil, times: makeTimes(fajr: "not-a-time", maghrib: "20:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidate = try #require(
            scheduler.fastingCandidates(settings: enableAllFasting())
                .first { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(mondayISO)" }
        )

        // Reminder still scheduled (correct fire time from the eve)...
        let expectedFire = PrayerMomentResolver.resolve(
            isoDate: sundayISO, rawTime: "18:00", adjustmentMinutes: 0, timezoneIdentifier: "Europe/Berlin"
        )!.addingTimeInterval(10 * 60)
        #expect(abs(candidate.fireDate.timeIntervalSince(expectedFire)) < 1)

        // ...but with no invented duration or broken clock-time text.
        #expect(candidate.body == "Morgen ist Montag.")
        #expect(!candidate.body.contains("Std."))
        #expect(!candidate.body.contains("not-a-time"))
    }

    // MARK: - Religious exclusion

    @Test func mondayDuringRamadanProducesNoCandidate() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let hijri = hijriCalendar(timeZone: berlin)
        let gregorian = gregorianCalendar(timeZone: berlin)
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        // Find a Ramadan day that's a Monday or Thursday.
        var comps = DateComponents(); comps.day = 10; comps.month = 9; comps.year = 1447
        var candidate = hijri.date(from: comps)!
        var occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: gregorian, hijriCalendar: hijri)
        var guardCounter = 0
        while !(occasions.contains(.monday) || occasions.contains(.thursday)), guardCounter < 40 {
            comps.day! += 1
            if comps.day! > 29 { comps.day = 1; comps.year! += 1 }
            candidate = hijri.date(from: comps)!
            occasions = VoluntaryFastingClassifier.occasions(for: candidate, gregorianCalendar: gregorian, hijriCalendar: hijri)
            guardCounter += 1
        }
        #expect(guardCounter < 40)

        let eve = gregorian.date(byAdding: .day, value: -1, to: candidate)!
        let iso = isoString(candidate, timeZone: berlin)
        let eveISO = isoString(eve, timeZone: berlin)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: eveISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        #expect(!candidates.contains { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(iso)" })
    }

    @Test func eidAlAdhaProducesNoCandidateEvenIfEnabled() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let hijri = hijriCalendar(timeZone: berlin)
        let gregorian = gregorianCalendar(timeZone: berlin)
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        var comps = DateComponents(); comps.day = 10; comps.month = 12; comps.year = 1447
        let eidAlAdha = hijri.date(from: comps)!
        let eve = gregorian.date(byAdding: .day, value: -1, to: eidAlAdha)!
        let iso = isoString(eidAlAdha, timeZone: berlin)
        let eveISO = isoString(eve, timeZone: berlin)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: eveISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        #expect(!candidates.contains { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(iso)" })
    }

    @Test func tashriqWhiteDayProducesNoCandidate() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let hijri = hijriCalendar(timeZone: berlin)
        let gregorian = gregorianCalendar(timeZone: berlin)
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        // 13 Dhu'l-Hijjah: a White Day that is also the last Tashriq day.
        var comps = DateComponents(); comps.day = 13; comps.month = 12; comps.year = 1447
        let day = hijri.date(from: comps)!
        let eve = gregorian.date(byAdding: .day, value: -1, to: day)!
        let iso = isoString(day, timeZone: berlin)
        let eveISO = isoString(eve, timeZone: berlin)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: eveISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        #expect(!candidates.contains { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(iso)" })
    }

    // MARK: - Disabled toggles

    @Test func disabledTogglesProduceNoCandidates() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let sunday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: monday)!

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: isoString(sunday, timeZone: berlin), hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: isoString(monday, timeZone: berlin), hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)

        // All three toggles off (the default `.zero`).
        #expect(scheduler.fastingCandidates(settings: .zero).isEmpty)

        // Only Thursday enabled — a Monday must still produce nothing.
        var thursdayOnly = NotificationSettings.zero
        thursdayOnly.voluntaryFasting = VoluntaryFastingNotificationSetting(monday: false, thursday: true, whiteDays: false)
        #expect(scheduler.fastingCandidates(settings: thursdayOnly).isEmpty)
    }

    // MARK: - Missing eve: no fire time to anchor to

    @Test func missingEveCacheProducesNoCandidate() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let mondayISO = isoString(monday, timeZone: berlin)

        // Only the fasting day itself is cached — its eve (Sunday) is not.
        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: mondayISO, hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        #expect(!candidates.contains { $0.identifier == "\(NotificationScheduler.fastingIdentifierPrefix)\(mondayISO)" })
    }

    // MARK: - Location change: never the old city's times

    @Test func locationChangeProducesNoCandidateFromTheOldCitysCache() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        // Distinct coordinates (not the helper's shared default) so the
        // two settings genuinely produce different LocationKeys — the
        // point of this test is a real location change, which a shared
        // fixed coordinate would silently defeat.
        let oldSettings = makeAutoSettings(address: "Essen, DE", coordinate: GeoCoordinate(latitude: 51.4508, longitude: 7.0131))

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let sunday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: monday)!

        timesStore.replaceCache(with: makeCache(for: oldSettings, days: [
            PrayerDay(isoDate: isoString(sunday, timeZone: berlin), hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: isoString(monday, timeZone: berlin), hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        // Settings now reflect a *different* (new) city — the old cache
        // above must not be treated as valid for it.
        let newSettings = makeAutoSettings(address: "Munich, DE", coordinate: GeoCoordinate(latitude: 48.1351, longitude: 11.5820))
        settingsStore.saveAutoSettings(newSettings)

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        #expect(scheduler.fastingCandidates(settings: enableAllFasting()).isEmpty)
    }

    // MARK: - Stable identifier

    @Test func fastingCandidateIdentifierUsesTheStableFastingPrefix() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let timesStore = SharedPrayerTimesStore(suiteName: suite1)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite2)
        let calendarStore = SharedIslamicCalendarStore(suiteName: suite3)

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let autoSettings = makeAutoSettings()
        settingsStore.saveAutoSettings(autoSettings)

        let monday = nextSafeWeekday(2, onOrAfter: Date(), timeZone: berlin)
        let sunday = gregorianCalendar(timeZone: berlin).date(byAdding: .day, value: -1, to: monday)!

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: isoString(sunday, timeZone: berlin), hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00")),
            PrayerDay(isoDate: isoString(monday, timeZone: berlin), hijri: nil, times: makeTimes(fajr: "05:00", maghrib: "18:00"))
        ]))

        let scheduler = makeScheduler(timesStore: timesStore, settingsStore: settingsStore, calendarStore: calendarStore)
        let candidates = scheduler.fastingCandidates(settings: enableAllFasting())

        #expect(!candidates.isEmpty)
        for candidate in candidates {
            #expect(candidate.identifier.hasPrefix(NotificationScheduler.fastingIdentifierPrefix))
        }
    }
}
