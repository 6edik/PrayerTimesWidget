import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the "Gespeicherte Gebetszeiten" read-only cache inspector:
/// - empty cache produces a clean empty state, no invented days
/// - a single missing day inside a range is simply absent, never a placeholder
/// - matching vs. mismatching location/method are both detected and labeled
///   from the cache's own stored metadata, never the current settings' label
/// - raw vs. personally-adjusted display values differ exactly as expected
/// - loading works entirely from local UserDefaults (no network dependency)
/// - the view model never writes to the cache it reads
@MainActor
struct CachedPrayerTimesViewModelTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeViewModel(suiteName: String) -> CachedPrayerTimesViewModel {
        CachedPrayerTimesViewModel(
            timesStore: SharedPrayerTimesStore(suiteName: suiteName),
            settingsStore: SharedPrayerSettingsStore(suiteName: suiteName)
        )
    }

    private func makeTimes(fajr: String = "05:00") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: "07:00",
            dhuhr: "12:00",
            asr: "15:00",
            maghrib: "18:00",
            isha: "20:00",
            readableDate: "1 Jan 2026",
            readableDay: "Thursday",
            hijriDate: "01-01-1447",
            hijriDay: "Thursday",
            timezone: "Europe/Berlin"
        )
    }

    private func isoString(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func makeCache(for settings: AutoPrayerSettings, days: [PrayerDay], fetchedAt: Date = Date()) -> PrayerTimesCache {
        PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: fetchedAt,
            days: days
        )
    }

    // MARK: - Empty cache

    @Test func emptyCacheProducesEmptyStateWithNoInventedMetadata() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let viewModel = makeViewModel(suiteName: suite)

        viewModel.load()

        #expect(viewModel.hasCachedData == false)
        #expect(viewModel.days.isEmpty)
        #expect(viewModel.cacheLocationDisplay == "--")
        #expect(viewModel.cacheMethodDisplay == "--")
        #expect(viewModel.fetchedAt == nil)
        #expect(viewModel.noticeMessage == nil)
    }

    // MARK: - Single missing day

    @Test func singleMissingDayInARangeIsSimplyAbsentNotAPlaceholder() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let settings = settingsStore.loadAutoSettings()

        // Three consecutive days, but day 2 (Jan 2) is deliberately missing —
        // simulating a partial fetch or a gap in coverage.
        let days = [
            PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes()),
            PrayerDay(isoDate: isoString(2026, 1, 3), hijri: nil, times: makeTimes())
        ]
        store.replaceCache(with: makeCache(for: settings, days: days))

        viewModel.load()

        #expect(viewModel.days.count == 2)
        let isoDates = Set(viewModel.days.map(\.isoDate))
        #expect(isoDates.contains(isoString(2026, 1, 1)))
        #expect(isoDates.contains(isoString(2026, 1, 3)))
        #expect(!isoDates.contains(isoString(2026, 1, 2)))
    }

    // MARK: - Matching vs. mismatching location/method

    @Test func matchingLocationAndMethodShowNoMismatchAndUseCurrentSettingsLabel() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        settingsStore.saveAutoSettings(settings)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes())]
        ))

        viewModel.load(referenceDate: dateFromISO(isoString(2026, 1, 1))!)

        #expect(viewModel.hasMismatch == false)
        #expect(viewModel.cacheLocationDisplay == "Berlin, DE")
        #expect(viewModel.cacheMethodDisplay == PrayerCalculationMethod.ditib.title)
        #expect(viewModel.noticeMessage == nil)
    }

    @Test func mismatchingLocationIsDetectedAndNeverLabeledAsTheNewCity() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let oldSettings = AutoPrayerSettings(address: "Essen, DE", method: .ditib, adjustments: .zero)
        let newSettings = AutoPrayerSettings(address: "Munich, DE", method: .ditib, adjustments: .zero)

        store.replaceCache(with: makeCache(
            for: oldSettings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes())]
        ))
        settingsStore.saveAutoSettings(newSettings)

        viewModel.load()

        #expect(viewModel.locationMismatch == true)
        #expect(viewModel.hasMismatch == true)
        // Must reflect the cache's own (old) address, never the newly
        // configured city's name.
        #expect(viewModel.cacheLocationDisplay.localizedCaseInsensitiveContains("essen"))
        #expect(!viewModel.cacheLocationDisplay.localizedCaseInsensitiveContains("munich"))
        #expect(viewModel.noticeMessage != nil)
    }

    @Test func mismatchingMethodIsDetectedIndependentlyOfLocation() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let sameAddress = "Berlin, DE"
        let oldSettings = AutoPrayerSettings(address: sameAddress, method: .ditib, adjustments: .zero)
        let newSettings = AutoPrayerSettings(address: sameAddress, method: .muslimWorldLeague, adjustments: .zero)

        store.replaceCache(with: makeCache(
            for: oldSettings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes())]
        ))
        settingsStore.saveAutoSettings(newSettings)

        viewModel.load()

        #expect(viewModel.locationMismatch == false)
        #expect(viewModel.methodMismatch == true)
        #expect(viewModel.cacheMethodDisplay == PrayerCalculationMethod.ditib.title)
        #expect(viewModel.noticeMessage != nil)
    }

    // MARK: - Raw vs. adjusted display

    @Test func rawTimesIgnoreAdjustmentsWhileDefaultDisplayAppliesThem() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let adjustments = PrayerAdjustments(fajr: 5, shuruk: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: 0)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)
        settingsStore.saveAutoSettings(settings)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes(fajr: "05:00"))]
        ))

        viewModel.load()
        let entry = try #require(viewModel.days.first)

        let raw = viewModel.displayTimes(for: entry, showRaw: true)
        let adjusted = viewModel.displayTimes(for: entry, showRaw: false)

        #expect(raw.fajr == "05:00")
        #expect(adjusted.fajr == "05:05")
    }

    @Test func midnightWrappingAdjustmentReportsDayOffsetUsingSharedAdjuster() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        // Isha at 23:50 + 20 minutes rolls into the next calendar day, same
        // as PrayerTimeAdjuster's own documented behavior.
        let adjustments = PrayerAdjustments(fajr: 0, shuruk: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: 20)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)
        settingsStore.saveAutoSettings(settings)

        var times = makeTimes()
        times = PrayerTimes(
            fajr: times.fajr, shuruk: times.shuruk, dhuhr: times.dhuhr, asr: times.asr,
            maghrib: times.maghrib, isha: "23:50",
            readableDate: times.readableDate, readableDay: times.readableDay,
            hijriDate: times.hijriDate, hijriDay: times.hijriDay, timezone: times.timezone
        )

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: times)]
        ))

        viewModel.load()
        let entry = try #require(viewModel.days.first)

        let adjusted = viewModel.displayTimes(for: entry, showRaw: false)
        let offsets = viewModel.dayOffsets(for: entry)

        #expect(adjusted.isha == "00:10")
        #expect(offsets.isha == 1)
    }

    // MARK: - Offline usage

    @Test func loadWorksFullyOfflineFromLocalUserDefaultsOnly() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        settingsStore.saveAutoSettings(settings)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [
                PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes()),
                PrayerDay(isoDate: isoString(2026, 1, 2), hijri: nil, times: makeTimes())
            ]
        ))

        // `load()` is synchronous and touches only the two local stores
        // above (both backed by a throwaway UserDefaults suite) — there is
        // no service/network dependency it could fail to reach, so this
        // deterministically exercises the same code path that would run
        // with no internet connection at all.
        viewModel.load()

        #expect(viewModel.hasCachedData == true)
        #expect(viewModel.days.count == 2)
    }

    // MARK: - No cache writes

    @Test func loadingAndTogglingDisplayModeNeverWritesToTheCache() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let viewModel = makeViewModel(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        settingsStore.saveAutoSettings(settings)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes())]
        ))

        let defaults = UserDefaults(suiteName: suite)
        let beforeData = defaults?.data(forKey: "prayer_times_cache_v3")

        viewModel.load()
        let entry = try #require(viewModel.days.first)
        _ = viewModel.displayTimes(for: entry, showRaw: true)
        _ = viewModel.displayTimes(for: entry, showRaw: false)
        _ = viewModel.dayOffsets(for: entry)
        viewModel.load()
        viewModel.load()

        let afterData = defaults?.data(forKey: "prayer_times_cache_v3")

        #expect(beforeData != nil)
        #expect(afterData == beforeData)
        #expect(store.cacheDayCount(settings: settings) == 1)
    }

    private func dateFromISO(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }
}
