import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers Block 3 (Letztes Drittel der Nacht): the pure calculator, and the
/// resolver's before/after-Maghrib day selection, missing-day handling, and
/// DST correctness.
@MainActor
struct LastThirdOfNightCalculatorTests {

    // MARK: - LastThirdOfNightCalculator

    @Test func computesStartAsFajrMinusOneThirdOfNightDuration() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let maghrib = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 18, minute: 0))!
        // 12-hour night -> last third is 4 hours.
        let fajr = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 6, minute: 0))!

        let window = LastThirdOfNightCalculator.window(maghrib: maghrib, followingFajr: fajr)
        let expectedStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 2, minute: 0))!

        #expect(window?.start == expectedStart)
        #expect(window?.end == fajr)
    }

    @Test func returnsNilWhenFajrIsNotAfterMaghrib() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let maghrib = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 18, minute: 0))!
        let earlierFajr = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6, minute: 0))!

        #expect(LastThirdOfNightCalculator.window(maghrib: maghrib, followingFajr: earlierFajr) == nil)
        #expect(LastThirdOfNightCalculator.window(maghrib: maghrib, followingFajr: maghrib) == nil)
    }

    // MARK: - LastThirdOfNightResolver

    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeTimes(maghrib: String, fajr: String, timezone: String = "Europe/Berlin") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: "07:00",
            dhuhr: "12:00",
            asr: "15:00",
            maghrib: maghrib,
            isha: "20:00",
            readableDate: "--",
            readableDay: "--",
            hijriDate: "--",
            hijriDay: "--",
            timezone: timezone
        )
    }

    private func dateFromISO(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func isoString(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func makeCache(for settings: AutoPrayerSettings, days: [PrayerDay]) -> PrayerTimesCache {
        PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: days
        )
    }

    /// Local noon (device timezone) on the given device-local calendar day
    /// — a safe "now" that's unambiguously before that day's own evening
    /// Maghrib, regardless of what timezone the test machine runs in.
    private func localNoon(isoDate: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dateFromISO(isoDate))!
    }

    /// Local 22:00 (device timezone) — unambiguously after that day's own
    /// evening Maghrib.
    private func localEvening(isoDate: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(bySettingHour: 22, minute: 0, second: 0, of: dateFromISO(isoDate))!
    }

    @Test func beforeTodaysMaghribUsesYesterdaysMaghribAndTodaysFajr() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        let yesterday = isoString(2026, 1, 1)
        let today = isoString(2026, 1, 2)
        let tomorrow = isoString(2026, 1, 3)

        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: yesterday, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: today, hijri: nil, times: makeTimes(maghrib: "18:05", fajr: "06:01")),
            PrayerDay(isoDate: tomorrow, hijri: nil, times: makeTimes(maghrib: "18:10", fajr: "06:02"))
        ]))

        let now = localNoon(isoDate: today)
        let result = LastThirdOfNightResolver.window(now: now, store: store, settings: settings)

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let expectedMaghrib = berlin.date(bySettingHour: 18, minute: 0, second: 0, of: dateFromISO(yesterday))!
        // Today's own cached Fajr is "06:01", not "06:00".
        let expectedFajr = berlin.date(bySettingHour: 6, minute: 1, second: 0, of: dateFromISO(today))!
        let expectedWindow = LastThirdOfNightCalculator.window(maghrib: expectedMaghrib, followingFajr: expectedFajr)

        #expect(result?.start == expectedWindow?.start)
        #expect(result?.end == expectedWindow?.end)
        #expect(result?.timezoneIdentifier == "Europe/Berlin")
    }

    @Test func afterTodaysMaghribUsesTodaysMaghribAndTomorrowsFajr() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        let yesterday = isoString(2026, 1, 1)
        let today = isoString(2026, 1, 2)
        let tomorrow = isoString(2026, 1, 3)

        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: yesterday, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: today, hijri: nil, times: makeTimes(maghrib: "18:05", fajr: "06:01")),
            PrayerDay(isoDate: tomorrow, hijri: nil, times: makeTimes(maghrib: "18:10", fajr: "06:02"))
        ]))

        let now = localEvening(isoDate: today)
        let result = LastThirdOfNightResolver.window(now: now, store: store, settings: settings)

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let expectedMaghrib = berlin.date(bySettingHour: 18, minute: 5, second: 0, of: dateFromISO(today))!
        let expectedFajr = berlin.date(bySettingHour: 6, minute: 2, second: 0, of: dateFromISO(tomorrow))!
        let expectedWindow = LastThirdOfNightCalculator.window(maghrib: expectedMaghrib, followingFajr: expectedFajr)

        #expect(result?.start == expectedWindow?.start)
        #expect(result?.end == expectedWindow?.end)
    }

    @Test func missingPreviousDayReturnsNilBeforeMaghrib() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        let today = isoString(2026, 1, 2)
        let tomorrow = isoString(2026, 1, 3)

        // No "yesterday" cached at all.
        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: today, hijri: nil, times: makeTimes(maghrib: "18:05", fajr: "06:01")),
            PrayerDay(isoDate: tomorrow, hijri: nil, times: makeTimes(maghrib: "18:10", fajr: "06:02"))
        ]))

        let now = localNoon(isoDate: today)
        #expect(LastThirdOfNightResolver.window(now: now, store: store, settings: settings) == nil)
    }

    @Test func missingNextDayReturnsNilAfterMaghrib() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        let yesterday = isoString(2026, 1, 1)
        let today = isoString(2026, 1, 2)

        // No "tomorrow" cached at all.
        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: yesterday, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: today, hijri: nil, times: makeTimes(maghrib: "18:05", fajr: "06:01"))
        ]))

        let now = localEvening(isoDate: today)
        #expect(LastThirdOfNightResolver.window(now: now, store: store, settings: settings) == nil)
    }

    @Test func personalMaghribAndFajrAdjustmentsShiftBothEnds() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        var adjustments = PrayerAdjustments.zero
        adjustments.maghrib = 10
        adjustments.fajr = -5
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)

        let yesterday = isoString(2026, 1, 1)
        let today = isoString(2026, 1, 2)
        let tomorrow = isoString(2026, 1, 3)

        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: yesterday, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: today, hijri: nil, times: makeTimes(maghrib: "18:05", fajr: "06:01")),
            PrayerDay(isoDate: tomorrow, hijri: nil, times: makeTimes(maghrib: "18:10", fajr: "06:02"))
        ]))

        let now = localNoon(isoDate: today)
        let result = LastThirdOfNightResolver.window(now: now, store: store, settings: settings)

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Yesterday's Maghrib 18:00 +10min = 18:10; today's Fajr 06:01 -5min = 05:56.
        let expectedMaghrib = berlin.date(bySettingHour: 18, minute: 10, second: 0, of: dateFromISO(yesterday))!
        let expectedFajr = berlin.date(bySettingHour: 5, minute: 56, second: 0, of: dateFromISO(today))!
        let expectedWindow = LastThirdOfNightCalculator.window(maghrib: expectedMaghrib, followingFajr: expectedFajr)

        #expect(result?.start == expectedWindow?.start)
        #expect(result?.end == expectedFajr)
    }

    @Test func nightAcrossSpringForwardUsesRealElapsedDurationNotNaiveWallClock() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        // Europe/Berlin springs forward on 2026-03-29 (clocks jump
        // 02:00 -> 03:00): the night from the 28th's 18:00 Maghrib to the
        // 29th's 05:00 Fajr is only 10 real hours, not the naive 11 wall
        // hours a component-based calculation would assume.
        let day1 = isoString(2026, 3, 28)
        let day2 = isoString(2026, 3, 29)
        let day3 = isoString(2026, 3, 30)

        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: day1, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "05:00")),
            PrayerDay(isoDate: day2, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "05:00")),
            PrayerDay(isoDate: day3, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "05:00"))
        ]))

        let now = localNoon(isoDate: day2)
        let result = try #require(LastThirdOfNightResolver.window(now: now, store: store, settings: settings))

        let nightDuration = result.end.timeIntervalSince(result.start) * 3
        #expect(abs(nightDuration - 10 * 3600) < 1)
    }

    @Test func nightAcrossFallBackUsesRealElapsedDurationNotNaiveWallClock() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        // Europe/Berlin falls back on 2026-10-25 (clocks repeat 02:00-03:00
        // CEST as 02:00-03:00 CET): the night from the 24th's 18:00
        // Maghrib to the 25th's 06:00 Fajr is 13 real hours, not the naive
        // 12 wall hours.
        let day1 = isoString(2026, 10, 24)
        let day2 = isoString(2026, 10, 25)
        let day3 = isoString(2026, 10, 26)

        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: day1, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: day2, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: day3, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00"))
        ]))

        let now = localNoon(isoDate: day2)
        let result = try #require(LastThirdOfNightResolver.window(now: now, store: store, settings: settings))

        let nightDuration = result.end.timeIntervalSince(result.start) * 3
        #expect(abs(nightDuration - 13 * 3600) < 1)
    }

    // MARK: - End must exactly equal today's actually-displayed Fajr

    @Test func endOfLastThirdExactlyMatchesTodaysDisplayedFajr() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        var adjustments = PrayerAdjustments.zero
        adjustments.fajr = 7
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)

        let yesterday = isoString(2026, 1, 1)
        let today = isoString(2026, 1, 2)

        let todaysRaw = makeTimes(maghrib: "18:05", fajr: "06:01")
        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: yesterday, hijri: nil, times: makeTimes(maghrib: "18:00", fajr: "06:00")),
            PrayerDay(isoDate: today, hijri: nil, times: todaysRaw)
        ]))

        let now = localNoon(isoDate: today)
        let result = try #require(LastThirdOfNightResolver.window(now: now, store: store, settings: settings))

        // Exactly what the Home screen/widget would display for today's
        // Fajr: the raw cached time with the personal adjustment applied
        // — never a separately re-derived value that could silently drift
        // from what's actually on screen.
        let displayedFajrString = todaysRaw.applyingAdjustments(adjustments).fajr
        #expect(displayedFajrString == "06:08")

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let parts = displayedFajrString.split(separator: ":")
        let displayedFajrDate = berlin.date(bySettingHour: Int(parts[0])!, minute: Int(parts[1])!, second: 0, of: dateFromISO(today))!

        #expect(result.end == displayedFajrDate)
    }

    // MARK: - Device timezone never leaks into the location's own clock time

    @Test func locationTimezoneGovernsResultRegardlessOfAmbientDeviceTimezone() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings(address: "Tokyo, JP", method: .ditib, adjustments: .zero)

        let yesterday = isoString(2026, 1, 1)
        let today = isoString(2026, 1, 2)
        let tomorrow = isoString(2026, 1, 3)

        // Identical clock times on all three cached days: the huge
        // absolute offset between Tokyo and whatever the test machine's
        // own ambient timezone happens to be can shift which of the
        // before/after-Maghrib branches actually fires (that's the whole
        // "ortsfremde Gerätezeitzone" point), so this keeps the expected
        // *clock time* stable regardless of which branch runs.
        let times = makeTimes(maghrib: "17:05", fajr: "05:31", timezone: "Asia/Tokyo")
        store.replaceCache(with: makeCache(for: settings, days: [
            PrayerDay(isoDate: yesterday, hijri: nil, times: times),
            PrayerDay(isoDate: today, hijri: nil, times: times),
            PrayerDay(isoDate: tomorrow, hijri: nil, times: times)
        ]))

        // `now` is device-local noon "today" — the test machine's own real
        // ambient timezone need not be anything like Tokyo. The result
        // must still reflect the *location's* own Tokyo clock time
        // exactly, never the device's.
        let now = localNoon(isoDate: today)
        let result = try #require(LastThirdOfNightResolver.window(now: now, store: store, settings: settings))

        #expect(result.timezoneIdentifier == "Asia/Tokyo")

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let endComponents = tokyo.dateComponents([.hour, .minute], from: result.end)
        #expect(endComponents.hour == 5)
        #expect(endComponents.minute == 31)
    }
}
