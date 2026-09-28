import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the local-only migration path for `AutoPrayerSettings` saved
/// before coordinates existed: an unambiguous city-list name match
/// backfills silently; anything else leaves `location` untouched and flags
/// that the user must re-confirm the place. Uses an injected fake city
/// list (via `LegacyLocationMigrator`'s `loadGermanCities` closure) so this
/// never depends on `Bundle.main` resolving the real `DE_cities.json`
/// inside the test process, and never makes a network request.
@MainActor
struct LegacyLocationMigratorTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeCityItem(name: String, state: String, district: String, lat: Double, lon: Double) throws -> CityItem {
        let json = """
        {
            "name": "\(name)",
            "state": "\(state)",
            "district": "\(district)",
            "area": "10",
            "population": "1000",
            "coords": { "lat": "\(lat)", "lon": "\(lon)" }
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(CityItem.self, from: json)
    }

    private func makeCities() throws -> [CityItem] {
        [
            try makeCityItem(name: "Gelsenkirchen", state: "NRW", district: "Gelsenkirchen", lat: 51.517, lon: 7.100),
            try makeCityItem(name: "Essen", state: "NRW", district: "Essen", lat: 51.45, lon: 7.01),
            try makeCityItem(name: "Essen", state: "Niedersachsen", district: "Cloppenburg", lat: 52.73, lon: 7.94)
        ]
    }

    private func makeTimes() -> PrayerTimes {
        PrayerTimes(
            fajr: "05:00", shuruk: "07:00", dhuhr: "12:00", asr: "15:00",
            maghrib: "18:00", isha: "20:00",
            readableDate: "1 Jan 2026", readableDay: "Thursday",
            hijriDate: "01-01-1447", hijriDay: "Thursday", timezone: "Europe/Berlin"
        )
    }

    @Test func uniqueCityNameBackfillsCoordinateAndClearsConfirmationFlag() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        settingsStore.saveAutoSettings(
            AutoPrayerSettings(address: "Gelsenkirchen, DE", location: nil, method: .ditib, adjustments: .zero)
        )
        // Simulate a prior flagged state to confirm it gets cleared once a
        // coordinate is actually backfilled.
        settingsStore.setNeedsLocationConfirmation(true)

        let cities = try makeCities()
        let migrator = LegacyLocationMigrator(settingsStore: settingsStore, timesStore: timesStore, loadGermanCities: { cities })

        await migrator.migrateIfNeeded()

        let migrated = settingsStore.loadAutoSettings()
        #expect(migrated.location?.coordinate.latitude == 51.517)
        #expect(migrated.location?.coordinate.longitude == 7.100)
        #expect(migrated.location?.source == .confirmedPlace)
        #expect(settingsStore.needsLocationConfirmation() == false)
    }

    @Test func ambiguousCityNameLeavesLocationNilAndFlagsConfirmation() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        // "Essen" exists twice in the bundled list under different
        // districts/states — never guess which one the user meant.
        let settings = AutoPrayerSettings(address: "Essen, DE", location: nil, method: .ditib, adjustments: .zero)
        settingsStore.saveAutoSettings(settings)
        timesStore.replaceCache(with: PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: "2026-01-01", hijri: nil, times: makeTimes())]
        ))

        let cities = try makeCities()
        let migrator = LegacyLocationMigrator(settingsStore: settingsStore, timesStore: timesStore, loadGermanCities: { cities })

        await migrator.migrateIfNeeded()

        let migrated = settingsStore.loadAutoSettings()
        #expect(migrated.location == nil)
        #expect(settingsStore.needsLocationConfirmation() == true)
        // The now-unreachable address-keyed cache is invalidated rather
        // than left lingering under the unconfirmed address.
        #expect(timesStore.snapshot().days.isEmpty)
    }

    @Test func nonGermanAddressSkipsLookupAndFlagsConfirmation() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        settingsStore.saveAutoSettings(
            AutoPrayerSettings(address: "Paris, FR", location: nil, method: .ditib, adjustments: .zero)
        )

        var lookupCallCount = 0
        let migrator = LegacyLocationMigrator(settingsStore: settingsStore, timesStore: timesStore, loadGermanCities: {
            lookupCallCount += 1
            return []
        })

        await migrator.migrateIfNeeded()

        #expect(lookupCallCount == 0)
        #expect(settingsStore.loadAutoSettings().location == nil)
        #expect(settingsStore.needsLocationConfirmation() == true)
    }

    @Test func alreadyConfirmedLocationIsANoOpAndClearsStaleConfirmationFlag() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        settingsStore.saveAutoSettings(AutoPrayerSettings(
            address: "Berlin, DE",
            location: PrayerLocation(name: "Berlin, DE", coordinate: GeoCoordinate(latitude: 52.52, longitude: 13.405)),
            method: .ditib,
            adjustments: .zero
        ))
        settingsStore.setNeedsLocationConfirmation(true)

        var lookupCallCount = 0
        let migrator = LegacyLocationMigrator(settingsStore: settingsStore, timesStore: timesStore, loadGermanCities: {
            lookupCallCount += 1
            return []
        })

        await migrator.migrateIfNeeded()

        #expect(lookupCallCount == 0)
        #expect(settingsStore.needsLocationConfirmation() == false)
    }

    @Test func sameUnresolvedAddressIsNotRecheckedOnASecondCall() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        settingsStore.saveAutoSettings(
            AutoPrayerSettings(address: "Essen, DE", location: nil, method: .ditib, adjustments: .zero)
        )

        var lookupCallCount = 0
        let cities = try makeCities()
        let migrator = LegacyLocationMigrator(settingsStore: settingsStore, timesStore: timesStore, loadGermanCities: {
            lookupCallCount += 1
            return cities
        })

        await migrator.migrateIfNeeded()
        #expect(lookupCallCount == 1)

        await migrator.migrateIfNeeded()
        // Same address, still unresolved: the second call must not repeat
        // the (already-decided) lookup.
        #expect(lookupCallCount == 1)
    }
}
