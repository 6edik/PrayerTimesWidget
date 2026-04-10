import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers N1 (no empty-cache window on replace), N5 (bulk decode instead of
/// once per day), the cache-validation half of N12 (stale data from a
/// previous location must not be served under new settings), and the
/// coordinate-cache-key migration (city-list/GPS locations key on
/// coordinate, App and widget share one cache). Each test uses its own
/// throwaway App Group suite so it never touches the developer's real
/// cached prayer times.
@MainActor
struct SharedPrayerTimesStoreTests {
    private func makeStore(suiteName: String) -> SharedPrayerTimesStore {
        SharedPrayerTimesStore(suiteName: suiteName)
    }

    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
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

    private func makeCache(for settings: AutoPrayerSettings, days: [PrayerDay]) -> PrayerTimesCache {
        PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: days
        )
    }

    @Test func loadReturnsNilWhenNoCacheExists() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings()
        #expect(store.load(for: Date(), settings: settings) == nil)
    }

    @Test func replaceCacheThenLoadReturnsTheNewData() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let iso = isoString(2026, 1, 1)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))

        #expect(store.cacheDayCount(settings: settings) == 1)
        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: settings)?.times.fajr == "05:00")
    }

    @Test func cacheForOldAddressIsNotServedUnderNewSettings() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let oldSettings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let newSettings = AutoPrayerSettings(address: "Munich, DE", method: .ditib, adjustments: .zero)
        let iso = isoString(2026, 1, 1)

        store.replaceCache(with: makeCache(
            for: oldSettings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))

        // Cache still matches the address it was written for.
        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: oldSettings) != nil)

        // But must not leak through under the new (different) address —
        // this is what prevents the old location's times from appearing
        // under the new address label (N12).
        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: newSettings) == nil)
        #expect(store.cacheDayCount(settings: newSettings) == 0)
    }

    // MARK: - Coordinate migration

    /// Covers "Stadt aus der Liste mit gültigen Koordinaten".
    @Test func cityWithCoordinateIsServedByLocationKeyNotAddressText() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: .zero
        )
        let iso = isoString(2026, 1, 1)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))

        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: settings) != nil)
    }

    /// Covers "Ortswechsel ohne Internet": switching to a different
    /// coordinate-confirmed location, with no fresh fetch, must not serve
    /// the previous location's cached data even though both used the
    /// coordinate-based key scheme.
    @Test func switchingCoordinateLocationOfflineDoesNotServeThePreviousCity() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let essen = AutoPrayerSettings(
            address: "Essen, Germany",
            location: PrayerLocation(name: "Essen, Germany", coordinate: GeoCoordinate(latitude: 51.4508, longitude: 7.0131)),
            method: .ditib,
            adjustments: .zero
        )
        let munich = AutoPrayerSettings(
            address: "Munich, Germany",
            location: PrayerLocation(name: "Munich, Germany", coordinate: GeoCoordinate(latitude: 48.1372, longitude: 11.5755)),
            method: .ditib,
            adjustments: .zero
        )
        let iso = isoString(2026, 1, 1)

        store.replaceCache(with: makeCache(
            for: essen,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))

        // No network call happened for Munich — the switch alone (no new
        // cache write) must already stop serving Essen's cached day.
        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: munich) == nil)
        #expect(store.cacheDayCount(settings: munich) == 0)
    }

    /// Covers "fehlerhafte oder fehlende Koordinaten": a broken coordinate
    /// must fall back to the address-based key rather than produce a bogus
    /// coordinate key that could accidentally collide with something else.
    @Test func implausibleCoordinateFallsBackToAddressBasedCacheKey() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let brokenLocation = AutoPrayerSettings(
            address: "Broken, DE",
            location: PrayerLocation(name: "Broken, DE", coordinate: GeoCoordinate(latitude: 0, longitude: 0)),
            method: .ditib,
            adjustments: .zero
        )
        let addressOnly = AutoPrayerSettings(address: "Broken, DE", method: .ditib, adjustments: .zero)
        let iso = isoString(2026, 1, 1)

        store.replaceCache(with: makeCache(
            for: brokenLocation,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))

        // Both settings resolve to the same address-based key, since the
        // "location" on the first one isn't plausible.
        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: addressOnly) != nil)
    }

    /// Covers "alte Einstellungen ohne Koordinaten": a legacy address-only
    /// AutoPrayerSettings (location == nil, as after decoding pre-migration
    /// JSON) must still validate against its own address-based cache.
    @Test func legacySettingsWithoutLocationStillMatchTheirOwnCache() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let legacySettings = AutoPrayerSettings(address: "Aachen, DE", method: .ditib, adjustments: .zero)
        #expect(legacySettings.location == nil)

        let iso = isoString(2026, 1, 1)
        store.replaceCache(with: makeCache(
            for: legacySettings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))

        #expect(store.loadPrayerDay(for: dateFromISO(iso)!, settings: legacySettings) != nil)
    }

    /// Covers "alten Cache nach der Umstellung": data written under the
    /// pre-migration storage key must not resurface just because the
    /// schema/key scheme changed — the store only ever reads its own
    /// current key.
    @Test func dataUnderThePreviousStorageKeyIsNotPickedUp() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)

        // Simulate a v2-era cache blob (old field name) sitting under the
        // old key — the store must never read this by accident.
        let legacyJSON = """
        {"addressKey":"berlin, de","methodKey":"ditib","fetchedAt":0,"days":[]}
        """.data(using: .utf8)!
        UserDefaults(suiteName: suite)?.set(legacyJSON, forKey: "prayer_times_cache_v2")

        #expect(store.cacheDayCount(settings: settings) == 0)
    }

    /// Covers "App und Widget mit demselben ausgewählten Ort": two
    /// independent `SharedPrayerTimesStore` instances pointed at the same
    /// suite (exactly how the main app and the widget extension share the
    /// real App Group in production) must see the same data for the same
    /// settings.
    @Test func appAndWidgetInstancesShareTheSameCacheForTheSameLocation() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }

        let appStore = makeStore(suiteName: suite)
        let widgetStore = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)),
            method: .ditib,
            adjustments: .zero
        )
        let iso = isoString(2026, 1, 1)

        appStore.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "05:12"))]
        ))

        let fromWidget = widgetStore.loadPrayerDay(for: dateFromISO(iso)!, settings: settings)
        #expect(fromWidget?.times.fajr == "05:12")
    }

    @Test func loadAllDaysMatchesIndividualLookups() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let isos = [isoString(2026, 1, 1), isoString(2026, 1, 2), isoString(2026, 1, 3)]

        store.replaceCache(with: makeCache(
            for: settings,
            days: isos.map { PrayerDay(isoDate: $0, hijri: nil, times: makeTimes()) }
        ))

        let bulk = store.loadAllDays(settings: settings)
        #expect(bulk.count == 3)

        for iso in isos {
            #expect(bulk[iso]?.isoDate == store.loadPrayerDay(for: dateFromISO(iso)!, settings: settings)?.isoDate)
        }
    }

    @Test func clearRemovesCachedData() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = makeStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let iso = isoString(2026, 1, 1)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes())]
        ))
        #expect(store.cacheDayCount(settings: settings) == 1)

        store.clear()
        #expect(store.cacheDayCount(settings: settings) == 0)
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
