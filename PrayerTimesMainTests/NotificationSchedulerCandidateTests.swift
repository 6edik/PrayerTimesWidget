import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the notification spec's test list items that don't need a live
/// `UNUserNotificationCenter`: single prayer on/off, reminder-before vs.
/// at-start, minute/midnight adjustment, location/method change, missing
/// cache data, and holiday day-before/on-day.
@MainActor
struct NotificationSchedulerCandidateTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteNames: [String]) {
        for suite in suiteNames {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private func makeTimes(fajr: String = "05:00", isha: String = "20:00", timezone: String = "Europe/Berlin") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: "07:00",
            dhuhr: "12:00",
            asr: "15:00",
            maghrib: "18:00",
            isha: isha,
            readableDate: "27 Sep 2026",
            readableDay: "Sunday",
            hijriDate: "27-09-2026",
            hijriDay: "Sunday",
            timezone: timezone
        )
    }

    private func makeSettings(
        prayerTimesSuite: String,
        prayerSettingsSuite: String,
        calendarSuite: String
    ) -> (SharedPrayerTimesStore, SharedPrayerSettingsStore, SharedIslamicCalendarStore) {
        (
            SharedPrayerTimesStore(suiteName: prayerTimesSuite),
            SharedPrayerSettingsStore(suiteName: prayerSettingsSuite),
            SharedIslamicCalendarStore(suiteName: calendarSuite)
        )
    }

    // MARK: - Prayer candidates

    @Test func disabledPrayerProducesNoCandidates() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )

        let autoSettings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: .zero
        )
        settingsStore.saveAutoSettings(autoSettings)

        let cache = PrayerTimesCache(
            locationKey: LocationKey.key(address: autoSettings.address, location: autoSettings.location),
            methodKey: String(describing: autoSettings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: "2026-09-28", hijri: nil, times: makeTimes())]
        )
        timesStore.replaceCache(with: cache)

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        // Fajr disabled (default), everything else disabled too.
        let candidates = scheduler.prayerCandidates(settings: .zero)
        #expect(candidates.isEmpty)
    }

    @Test func enabledPrayerWithReminderProducesBothStartAndReminderCandidates() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )

        let autoSettings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: .zero
        )
        settingsStore.saveAutoSettings(autoSettings)

        // Far in the future so it's never filtered out as "past".
        let futureISO = isoString(daysFromNow: 3)
        let cache = PrayerTimesCache(
            locationKey: LocationKey.key(address: autoSettings.address, location: autoSettings.location),
            methodKey: String(describing: autoSettings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: futureISO, hijri: nil, times: makeTimes(fajr: "05:30"))]
        )
        timesStore.replaceCache(with: cache)

        var settings = NotificationSettings.zero
        settings.fajr = PrayerNotificationSetting(isEnabled: true, reminderLeadTime: .tenMinutes, sound: .standard)

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        let candidates = scheduler.prayerCandidates(settings: settings)
        let identifiers = Set(candidates.map(\.identifier))

        #expect(identifiers.contains("\(NotificationScheduler.prayerIdentifierPrefix)fajr.\(futureISO).start"))
        #expect(identifiers.contains("\(NotificationScheduler.prayerIdentifierPrefix)fajr.\(futureISO).reminder"))

        let start = candidates.first { $0.identifier.hasSuffix(".start") }!
        let reminder = candidates.first { $0.identifier.hasSuffix(".reminder") }!
        #expect(start.fireDate.timeIntervalSince(reminder.fireDate) == 10 * 60)
    }

    @Test func minuteAdjustmentShiftsTheScheduledTime() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )

        var adjustments = PrayerAdjustments.zero
        adjustments.fajr = 15

        let autoSettings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: adjustments
        )
        settingsStore.saveAutoSettings(autoSettings)

        let futureISO = isoString(daysFromNow: 3)
        timesStore.replaceCache(with: PrayerTimesCache(
            locationKey: LocationKey.key(address: autoSettings.address, location: autoSettings.location),
            methodKey: String(describing: autoSettings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: futureISO, hijri: nil, times: makeTimes(fajr: "05:00"))]
        ))

        var settings = NotificationSettings.zero
        settings.fajr = PrayerNotificationSetting(isEnabled: true, reminderLeadTime: .none, sound: .standard)

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        let candidate = scheduler.prayerCandidates(settings: settings).first!
        let expected = PrayerMomentResolver.resolve(
            isoDate: futureISO, rawTime: "05:00", adjustmentMinutes: 15, timezoneIdentifier: "Europe/Berlin"
        )!

        #expect(abs(candidate.fireDate.timeIntervalSince(expected)) < 1)
        // 05:15, not the raw 05:00.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let comps = berlin.dateComponents([.hour, .minute], from: candidate.fireDate)
        #expect(comps.hour == 5 && comps.minute == 15)
    }

    @Test func midnightCrossingAdjustmentIsReflectedInTheScheduledCandidate() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )

        var adjustments = PrayerAdjustments.zero
        adjustments.isha = 20

        let autoSettings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: adjustments
        )
        settingsStore.saveAutoSettings(autoSettings)

        let futureISO = isoString(daysFromNow: 3)
        timesStore.replaceCache(with: PrayerTimesCache(
            locationKey: LocationKey.key(address: autoSettings.address, location: autoSettings.location),
            methodKey: String(describing: autoSettings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: futureISO, hijri: nil, times: makeTimes(isha: "23:50"))]
        ))

        var settings = NotificationSettings.zero
        settings.isha = PrayerNotificationSetting(isEnabled: true, reminderLeadTime: .none, sound: .standard)

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        let candidate = scheduler.prayerCandidates(settings: settings).first!

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let comps = berlin.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)

        // Compare against the *next calendar day* after the cached ISO
        // date (via dateComponents, not manual day-number arithmetic,
        // since that breaks across month/year boundaries).
        let nextDay = berlin.date(byAdding: .day, value: 1, to: dateFromISO(futureISO)!)!
        let expected = berlin.dateComponents([.year, .month, .day], from: nextDay)

        #expect(comps.year == expected.year && comps.month == expected.month && comps.day == expected.day)
        #expect(comps.hour == 0 && comps.minute == 10)
    }

    @Test func mismatchedLocationProducesNoCandidatesFromStaleCache() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )

        let oldSettings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: .zero
        )
        timesStore.replaceCache(with: PrayerTimesCache(
            locationKey: LocationKey.key(address: oldSettings.address, location: oldSettings.location),
            methodKey: String(describing: oldSettings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: isoString(daysFromNow: 3), hijri: nil, times: makeTimes())]
        ))

        // Settings store now reflects a *different* (new) location — the
        // cache above must not be treated as valid for it.
        let newSettings = AutoPrayerSettings(
            address: "Munich, Germany",
            location: PrayerLocation(name: "Munich, Germany", coordinate: GeoCoordinate(latitude: 48.1372, longitude: 11.5755)),
            method: .ditib,
            adjustments: .zero
        )
        settingsStore.saveAutoSettings(newSettings)

        var settings = NotificationSettings.zero
        settings.fajr = PrayerNotificationSetting(isEnabled: true, reminderLeadTime: .none, sound: .standard)

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        #expect(scheduler.prayerCandidates(settings: settings).isEmpty)
    }

    @Test func noCachedDataProducesNoCandidates() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )

        settingsStore.saveAutoSettings(AutoPrayerSettings())

        var settings = NotificationSettings.zero
        settings.fajr = PrayerNotificationSetting(isEnabled: true, reminderLeadTime: .none, sound: .standard)

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        #expect(scheduler.prayerCandidates(settings: settings).isEmpty)
    }

    // MARK: - Holiday candidates

    @Test func holidayProducesOnDayAndDayBeforeCandidatesAtTheConfiguredTime() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )
        settingsStore.saveAutoSettings(AutoPrayerSettings())

        let now = Date()
        var device = Calendar(identifier: .gregorian)
        device.timeZone = .autoupdatingCurrent
        let year = device.component(.year, from: now)

        let holidayDate = device.date(byAdding: .day, value: 5, to: now)!
        let eidAlFitr = IslamicSpecialDay(
            title: "Eid al-Fitr",
            gregorianReadable: "Test",
            gregorianMonthName: "Test",
            gregorianYear: String(year),
            hijriDay: "1",
            hijriMonth: "Shawwal",
            hijriYear: "1447",
            hijriWeekday: "Test",
            sortDate: holidayDate,
            hijriMonthNumber: 10
        )

        // Seed both years the scheduler looks at so it never attempts a
        // real network fetch during this test.
        calendarStore.saveYear(year, days: [eidAlFitr])
        calendarStore.saveYear(year + 1, days: [])

        var settings = NotificationSettings.zero
        settings.setSetting(
            HolidayNotificationSetting(isEnabled: true, notifyDayBefore: true, notifyOnDay: true, hour: 9, minute: 0),
            for: .eidAlFitr
        )

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        let candidates = await scheduler.holidayCandidates(settings: settings, now: now)
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.identifier.hasSuffix(".onday") })
        #expect(candidates.contains { $0.identifier.hasSuffix(".before") })

        for candidate in candidates {
            let comps = device.dateComponents([.hour, .minute], from: candidate.fireDate)
            #expect(comps.hour == 9 && comps.minute == 0)
        }
    }

    /// Covers "Bereits geplante Benachrichtigungen für ausgeschlossene
    /// Ereignisse müssen entfernt werden": an "Urs of …" entry cached
    /// alongside a real, enabled holiday on the same date must never
    /// produce a notification candidate of its own, and must not affect
    /// the genuine holiday's candidates either.
    @Test func excludedEventNeverProducesAHolidayCandidateEvenCachedAlongsideAMatch() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )
        settingsStore.saveAutoSettings(AutoPrayerSettings())

        let now = Date()
        var device = Calendar(identifier: .gregorian)
        device.timeZone = .autoupdatingCurrent
        let year = device.component(.year, from: now)
        let holidayDate = device.date(byAdding: .day, value: 5, to: now)!

        let eidAlFitr = IslamicSpecialDay(
            title: "Eid al-Fitr", gregorianReadable: "Test", gregorianMonthName: "Test", gregorianYear: String(year),
            hijriDay: "1", hijriMonth: "Shawwal", hijriYear: "1447", hijriWeekday: "Test",
            sortDate: holidayDate, hijriMonthNumber: 10
        )
        // Non-colliding Hijri key: a real "Urs of …" observance has its own,
        // unrelated Hijri date. (A genuine key collision — AlAdhan tagging
        // two differently-titled entries with the *same* Hijri day/month —
        // is a separate, documented, user-accepted edge case where both
        // are treated as relevant, matching the pre-existing Feiertage-
        // übersicht/notification behavior; that's not what this test
        // covers.)
        let ursEntry = IslamicSpecialDay(
            title: "Urs of Someone", gregorianReadable: "Test", gregorianMonthName: "Test", gregorianYear: String(year),
            hijriDay: "6", hijriMonth: "Rabi al-awwal", hijriYear: "1447", hijriWeekday: "Test",
            sortDate: holidayDate, hijriMonthNumber: 3
        )

        // Simulates a cache written before the exclusion filter existed —
        // both entries present, unfiltered.
        calendarStore.saveYear(year, days: [eidAlFitr, ursEntry])
        calendarStore.saveYear(year + 1, days: [])

        var settings = NotificationSettings.zero
        settings.setSetting(
            HolidayNotificationSetting(isEnabled: true, notifyDayBefore: false, notifyOnDay: true, hour: 9, minute: 0),
            for: .eidAlFitr
        )

        let scheduler = NotificationScheduler(
            timesStore: timesStore, settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        let candidates = await scheduler.holidayCandidates(settings: settings, now: now)

        // Exactly one candidate (the real holiday's "on day" reminder) —
        // never a second one for "Urs of Someone", which has no
        // MajorIslamicHoliday case to be scheduled under in the first
        // place.
        #expect(candidates.count == 1)
        #expect(candidates.allSatisfy { $0.title == "Eid al-Fitr" })
        #expect(!candidates.contains { $0.title.contains("Urs") })

        // And the migration ran: the on-disk cache for this year no longer
        // contains the excluded entry.
        #expect(calendarStore.loadYear(year)?.count == 1)
    }

    @Test func disabledHolidayProducesNoCandidates() async throws {
        let suite1 = makeSuiteName(); let suite2 = makeSuiteName(); let suite3 = makeSuiteName()
        defer { cleanup([suite1, suite2, suite3]) }

        let (timesStore, settingsStore, calendarStore) = makeSettings(
            prayerTimesSuite: suite1, prayerSettingsSuite: suite2, calendarSuite: suite3
        )
        settingsStore.saveAutoSettings(AutoPrayerSettings())

        let now = Date()
        var device = Calendar(identifier: .gregorian)
        device.timeZone = .autoupdatingCurrent
        let year = device.component(.year, from: now)
        calendarStore.saveYear(year, days: [])
        calendarStore.saveYear(year + 1, days: [])

        let scheduler = NotificationScheduler(
            timesStore: timesStore,
            settingsStore: settingsStore,
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: calendarStore
        )

        let candidates = await scheduler.holidayCandidates(settings: .zero, now: now)
        #expect(candidates.isEmpty)
    }

    // MARK: - Helpers

    private func isoString(daysFromNow: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = calendar.date(byAdding: .day, value: daysFromNow, to: Date())!

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dateFromISO(_ iso: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }
}
