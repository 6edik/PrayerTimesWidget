import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers "alte Einstellungen ohne Koordinaten": settings saved before
/// `location` existed must still decode — with `location == nil` rather
/// than a guessed coordinate or a decode failure that would silently reset
/// the whole struct to its default (a different place than the user saved).
@MainActor
struct AutoPrayerSettingsMigrationTests {
    @Test func legacyJSONWithoutLocationDecodesWithNilLocation() async throws {
        // Exactly the shape saved by the app before this migration — no
        // "location" key at all.
        let legacyJSON = """
        {
            "address": "Aachen, DE",
            "method": 13,
            "adjustments": {
                "fajr": 0, "shuruk": 0, "dhuhr": 0, "asr": 0, "maghrib": 0, "isha": 0
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AutoPrayerSettings.self, from: legacyJSON)

        #expect(decoded.address == "Aachen, DE")
        #expect(decoded.location == nil)
        #expect(decoded.method == .ditib)
    }

    @Test func currentJSONWithLocationRoundTrips() async throws {
        let original = AutoPrayerSettings(
            address: "Aachen, Germany",
            location: PrayerLocation(
                name: "Aachen, Germany",
                coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836)
            ),
            method: .ditib,
            adjustments: .zero
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutoPrayerSettings.self, from: data)

        #expect(decoded == original)
        #expect(decoded.location?.coordinate.latitude == 50.7755)
    }

    @Test func neverSavedInstallGetsTheVerifiedGelsenkirchenCoordinate() async throws {
        // A never-configured install (nothing in UserDefaults yet) should
        // get address and location assembled together, consistently — the
        // one coordinate looked up by us (not guessed at runtime) from the
        // project's own DE_cities.json for Gelsenkirchen.
        let suiteName = "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let store = SharedPrayerSettingsStore(suiteName: suiteName)
        let fresh = store.loadAutoSettings()

        #expect(fresh.address == "Gelsenkirchen, DE")
        #expect(fresh.location?.coordinate.latitude == 51.517)
        #expect(fresh.location?.coordinate.longitude == 7.100)
    }

    @Test func bareStructDefaultHasNoLocationToAvoidMismatchedConstruction() async throws {
        // The plain zero-argument struct default intentionally leaves
        // `location` nil — see the doc comment on the property. Only
        // `SharedPrayerSettingsStore.loadAutoSettings()` assembles the real
        // "app default" (address + matching location) for a fresh install.
        #expect(AutoPrayerSettings().location == nil)
    }

    // MARK: - PrayerLocation.source backward compatibility

    @Test func legacyLocationJSONWithoutSourceDecodesAsConfirmedPlace() async throws {
        // Exactly the shape saved before `source` existed — no "source" key
        // at all. Must decode successfully (never fail and fall back to
        // the whole-settings default), defaulting to `.confirmedPlace`.
        let legacyLocationJSON = """
        {
            "name": "Aachen, DE",
            "coordinate": { "latitude": 50.7755, "longitude": 6.0836 }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PrayerLocation.self, from: legacyLocationJSON)

        #expect(decoded.source == .confirmedPlace)
        #expect(decoded.coordinate.latitude == 50.7755)
    }

    @Test func currentLocationSourceRoundTrips() async throws {
        let original = PrayerLocation(
            name: "Aktueller Standort",
            coordinate: GeoCoordinate(latitude: 52.52, longitude: 13.405),
            source: .currentLocation
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PrayerLocation.self, from: data)

        #expect(decoded == original)
        #expect(decoded.source == .currentLocation)
    }

    @Test func defaultGelsenkirchenLocationIsConfirmedPlace() async throws {
        #expect(PrayerLocation.defaultGelsenkirchen.source == .confirmedPlace)
    }
}
