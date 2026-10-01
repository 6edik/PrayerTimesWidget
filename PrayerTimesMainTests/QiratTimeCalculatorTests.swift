import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the Karāha correction: the "besonders problematische"
/// sunrise window now starts exactly at Shuruk (never Fajr) and ends only
/// approximately; the separate Ḥanafī after-Fajr voluntary-prayer
/// restriction stays a distinct, exact, non-"Karāha"-labeled window; the
/// late-Maghrib window is only ever an approximation anchored to Maghrib
/// (never to Asr), latitude-gated, user-adjustable, and never
/// double-applies the personal Maghrib adjustment.
@MainActor
struct QiratTimeCalculatorTests {

    // MARK: - QiratTimeCalculator (pure validity check)

    @Test func windowRequiresEndStrictlyAfterStart() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6, minute: 0))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 7, minute: 0))!

        #expect(QiratTimeCalculator.window(start: start, end: end) == QiratTimeCalculator.Window(start: start, end: end))
        #expect(QiratTimeCalculator.window(start: end, end: start) == nil)
        #expect(QiratTimeCalculator.window(start: start, end: start) == nil)
    }

    @Test func windowIsNilWhenEitherEndIsMissing() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let someDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6, minute: 0))!

        #expect(QiratTimeCalculator.window(start: nil, end: someDate) == nil)
        #expect(QiratTimeCalculator.window(start: someDate, end: nil) == nil)
    }

    // MARK: - QiratTimeResolver

    private func makeTimes(fajr: String, shuruk: String, asr: String, maghrib: String, timezone: String = "Europe/Berlin") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: shuruk,
            dhuhr: "12:00",
            asr: asr,
            maghrib: maghrib,
            isha: "20:00",
            readableDate: "--",
            readableDay: "--",
            hijriDate: "--",
            hijriDay: "--",
            timezone: timezone
        )
    }

    private func berlinDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let berlinLatitude = 52.52

    // MARK: - Sonnenaufgangs-Karāha: starts exactly at Shuruk, 20-minute rule

    @Test func shuruk0715StartsAt0715AndEndsAt0735WithThe20MinuteRule() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, sunriseKarahaOffsetMinutes: 20
        )

        let sunrise = try #require(windows.sunriseKaraha)
        #expect(sunrise.start == berlinDate(2026, 1, 2, 7, 15))
        #expect(sunrise.end == berlinDate(2026, 1, 2, 7, 35))
        #expect(sunrise.offsetMinutes == 20)
    }

    @Test func sunriseKarahaNeverStartsAtFajr() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        // Fajr is a full 90 minutes before Shuruk.
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, sunriseKarahaOffsetMinutes: 20
        )

        let sunrise = try #require(windows.sunriseKaraha)
        #expect(sunrise.start != berlinDate(2026, 1, 2, 5, 45))
        #expect(sunrise.start == berlinDate(2026, 1, 2, 7, 15))
    }

    // MARK: - The separate Ḥanafī after-Fajr restriction stays distinct

    @Test func afterFajrVoluntaryRestrictionIsExactAndSeparateFromSunriseKaraha() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        // Way outside the plausibility range for either approximation —
        // must not affect this exact, data-derived window.
        let windows = QiratTimeResolver.windows(base: base, times: times, adjustments: .zero, latitude: 70.0)

        #expect(windows.afterFajrVoluntaryRestriction?.start == berlinDate(2026, 1, 2, 5, 45))
        #expect(windows.afterFajrVoluntaryRestriction?.end == berlinDate(2026, 1, 2, 7, 15))
        #expect(windows.afterFajrVoluntaryRestriction?.timezoneIdentifier == "Europe/Berlin")
    }

    @Test func sunriseKarahaAndAfterFajrRestrictionAreNeverMergedIntoOneWindow() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, sunriseKarahaOffsetMinutes: 20
        )

        let sunrise = try #require(windows.sunriseKaraha)
        let afterFajr = try #require(windows.afterFajrVoluntaryRestriction)

        // Two genuinely distinct windows, not one pauschal "verboten" span.
        #expect(afterFajr.start == berlinDate(2026, 1, 2, 5, 45))
        #expect(afterFajr.end == berlinDate(2026, 1, 2, 7, 15))
        #expect(sunrise.start == berlinDate(2026, 1, 2, 7, 15))
        #expect(sunrise.end == berlinDate(2026, 1, 2, 7, 35))
    }

    // MARK: - Asr remains a valid, untouched window (never part of Karāha vor Maghrib)

    @Test func asrToMaghribIsNeverFlaggedAsAWholeAndAsrIsNotTheWindowStart() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        // Asr and Maghrib are three hours apart.
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, lateKerahetOffsetMinutes: 45
        )

        let approx = try #require(windows.lateMaghribKaraha)
        // The approximation starts 45 minutes before Maghrib — nowhere
        // near Asr (15:00) — never "Asr until Maghrib".
        #expect(approx.start == berlinDate(2026, 1, 2, 17, 15))
        #expect(approx.start != berlinDate(2026, 1, 2, 15, 0))
        #expect(approx.end == berlinDate(2026, 1, 2, 18, 0))
    }

    @Test func lateMaghribKarahaNeverStartsAtAsrRegardlessOfGapSize() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        // Asr much closer to Maghrib this time (55 minutes apart) — the
        // approximation must still be anchored to Maghrib, never jump to
        // starting exactly at Asr.
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "17:05", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, lateKerahetOffsetMinutes: 45
        )

        let approx = try #require(windows.lateMaghribKaraha)
        #expect(approx.start == berlinDate(2026, 1, 2, 17, 15))
    }

    // MARK: - Configurable offsets

    @Test func customLateMaghribOffsetMinutesIsRespected() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, lateKerahetOffsetMinutes: 30
        )

        #expect(windows.lateMaghribKaraha?.start == berlinDate(2026, 1, 2, 17, 30))
        #expect(windows.lateMaghribKaraha?.offsetMinutes == 30)
    }

    @Test func customSunriseOffsetMinutesIsRespected() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero, latitude: berlinLatitude, sunriseKarahaOffsetMinutes: 15
        )

        #expect(windows.sunriseKaraha?.end == berlinDate(2026, 1, 2, 7, 30))
        #expect(windows.sunriseKaraha?.offsetMinutes == 15)
    }

    // MARK: - Personal adjustments applied exactly once

    @Test func maghribAdjustmentShiftsLateMaghribKarahaExactlyOnce() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        var adjustments = PrayerAdjustments.zero
        adjustments.maghrib = 10

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: adjustments, latitude: berlinLatitude, lateKerahetOffsetMinutes: 45
        )

        // Maghrib becomes 18:10 (adjustment applied once); approximation
        // start is 45 min before *that* single adjusted instant, i.e.
        // 17:25 — not 17:15 (unadjusted) and not 17:35 (adjustment
        // counted twice).
        #expect(windows.lateMaghribKaraha?.end == berlinDate(2026, 1, 2, 18, 10))
        #expect(windows.lateMaghribKaraha?.start == berlinDate(2026, 1, 2, 17, 25))
    }

    @Test func shurukAdjustmentShiftsSunriseKarahaExactlyOnce() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        var adjustments = PrayerAdjustments.zero
        adjustments.shuruk = 5

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: adjustments, latitude: berlinLatitude, sunriseKarahaOffsetMinutes: 20
        )

        // Shuruk becomes 07:20 (adjustment applied once); end is 20 min
        // after *that* single adjusted instant, i.e. 07:40.
        #expect(windows.sunriseKaraha?.start == berlinDate(2026, 1, 2, 7, 20))
        #expect(windows.sunriseKaraha?.end == berlinDate(2026, 1, 2, 7, 40))
    }

    @Test func fajrAdjustmentShiftsOnlyTheAfterFajrRestrictionWindow() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        var adjustments = PrayerAdjustments.zero
        adjustments.fajr = 5

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: adjustments, latitude: berlinLatitude, sunriseKarahaOffsetMinutes: 20
        )

        #expect(windows.afterFajrVoluntaryRestriction?.start == berlinDate(2026, 1, 2, 5, 50))
        // Unaffected by the Fajr adjustment.
        #expect(windows.sunriseKaraha?.start == berlinDate(2026, 1, 2, 7, 15))
    }

    // MARK: - Latitude plausibility gate (applies to both approximations)

    @Test func bothApproximationsAreSuppressedAtHighLatitude() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(base: base, times: times, adjustments: .zero, latitude: 65.0)
        #expect(windows.sunriseKaraha == nil)
        #expect(windows.lateMaghribKaraha == nil)

        // afterFajrVoluntaryRestriction is exact data, so it's still
        // present regardless of latitude.
        #expect(windows.afterFajrVoluntaryRestriction != nil)
    }

    @Test func bothApproximationsAreSuppressedWithoutAKnownLatitude() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(base: base, times: times, adjustments: .zero, latitude: nil)
        #expect(windows.sunriseKaraha == nil)
        #expect(windows.lateMaghribKaraha == nil)
    }

    @Test func bothApproximationsArePresentAtTheModerateLatitudeBoundary() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero,
            latitude: QiratTimeResolver.maxPlausibleLatitudeForApproximation
        )
        #expect(windows.sunriseKaraha != nil)
        #expect(windows.lateMaghribKaraha != nil)

        let justBeyond = QiratTimeResolver.windows(
            base: base, times: times, adjustments: .zero,
            latitude: QiratTimeResolver.maxPlausibleLatitudeForApproximation + 0.1
        )
        #expect(justBeyond.sunriseKaraha == nil)
        #expect(justBeyond.lateMaghribKaraha == nil)
    }

    // MARK: - Malformed data

    @Test func malformedShurukProducesNilSunriseKarahaNotAGuess() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "not-a-time", asr: "15:00", maghrib: "18:00")

        let windows = QiratTimeResolver.windows(base: base, times: times, adjustments: .zero, latitude: berlinLatitude)

        #expect(windows.sunriseKaraha == nil)
        #expect(windows.afterFajrVoluntaryRestriction == nil)
        #expect(windows.lateMaghribKaraha != nil)
    }

    @Test func malformedMaghribProducesNilLateMaghribKarahaNotAGuess() async throws {
        let base = berlinDate(2026, 1, 2, 0, 0)
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "not-a-time")

        let windows = QiratTimeResolver.windows(base: base, times: times, adjustments: .zero, latitude: berlinLatitude)

        #expect(windows.lateMaghribKaraha == nil)
        #expect(windows.sunriseKaraha != nil)
    }

    // MARK: - "Today" convenience overload

    @Test func todaysConvenienceOverloadReturnsNoneWhenNothingCached() async throws {
        let suite = "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let store = SharedPrayerTimesStore(suiteName: suite)
        let settings = AutoPrayerSettings()

        let windows = QiratTimeResolver.windows(now: Date(), store: store, settings: settings)
        #expect(windows == .none)
    }

    /// `now`, kept aligned with whatever ISO-date key
    /// `SharedPrayerTimesStore` would itself compute for "today" (device
    /// `.current` timezone, same convention the store already uses) —
    /// this test is about the `now:store:settings:` overload plumbing
    /// configured latitude/offsets through correctly, not about the
    /// store's own device-timezone-keyed cache lookup (covered
    /// separately), so it must not depend on which timezone the test
    /// machine happens to run in.
    private func deviceLocalNoonTodayAndISOString() -> (now: Date, iso: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return (now, formatter.string(from: now))
    }

    @Test func todaysConvenienceOverloadUsesConfiguredLatitudeAndCustomOffsets() async throws {
        let suite = "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let store = SharedPrayerTimesStore(suiteName: suite)
        var settings = AutoPrayerSettings(
            address: "Berlin, DE",
            location: PrayerLocation(name: "Berlin, DE", coordinate: GeoCoordinate(latitude: berlinLatitude, longitude: 13.405)),
            method: .ditib,
            adjustments: .zero
        )
        settings.lateKerahetOffsetMinutesOverride = 20
        settings.sunriseKarahaOffsetMinutesOverride = 15

        let (now, iso) = deviceLocalNoonTodayAndISOString()
        let times = makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00")
        let cache = PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: iso, hijri: nil, times: times)]
        )
        store.replaceCache(with: cache)

        let windows = QiratTimeResolver.windows(now: now, store: store, settings: settings)
        let expected = QiratTimeResolver.windows(
            base: now, times: times, adjustments: .zero, latitude: berlinLatitude,
            lateKerahetOffsetMinutes: 20, sunriseKarahaOffsetMinutes: 15
        )

        #expect(windows.lateMaghribKaraha?.offsetMinutes == 20)
        #expect(windows.lateMaghribKaraha?.start == expected.lateMaghribKaraha?.start)
        #expect(windows.sunriseKaraha?.offsetMinutes == 15)
        #expect(windows.sunriseKaraha?.end == expected.sunriseKaraha?.end)
    }
}
