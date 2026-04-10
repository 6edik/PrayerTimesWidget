import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the coordinate migration's core, dependency-free logic:
/// coordinate plausibility and the location-based cache key that decides
/// whether two settings refer to "the same place".
@MainActor
struct PrayerLocationTests {
    // MARK: - GeoCoordinate.isPlausible (covers "fehlerhafte oder fehlende Koordinaten")

    @Test func validCoordinateIsPlausible() async throws {
        let coordinate = GeoCoordinate(latitude: 51.517, longitude: 7.100)
        #expect(coordinate.isPlausible)
    }

    @Test func zeroZeroIsNotPlausible() async throws {
        // Null Island — the reliable signature of an uninitialized/failed
        // coordinate, never a real prayer location in this app.
        let coordinate = GeoCoordinate(latitude: 0, longitude: 0)
        #expect(!coordinate.isPlausible)
    }

    @Test func outOfRangeLatitudeIsNotPlausible() async throws {
        let coordinate = GeoCoordinate(latitude: 120, longitude: 7.1)
        #expect(!coordinate.isPlausible)
    }

    @Test func outOfRangeLongitudeIsNotPlausible() async throws {
        let coordinate = GeoCoordinate(latitude: 51.5, longitude: 200)
        #expect(!coordinate.isPlausible)
    }

    @Test func nanCoordinateIsNotPlausible() async throws {
        let coordinate = GeoCoordinate(latitude: .nan, longitude: 7.1)
        #expect(!coordinate.isPlausible)
    }

    // MARK: - LocationKey

    @Test func coordinateConfirmedLocationUsesCoordinateKey() async throws {
        let location = PrayerLocation(name: "Aachen, Germany", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836))
        let key = LocationKey.key(address: "Aachen, Germany", location: location)
        #expect(key.hasPrefix("coord:"))
    }

    @Test func missingLocationFallsBackToAddressKey() async throws {
        let key = LocationKey.key(address: "Aachen, Germany", location: nil)
        #expect(key == "addr:aachen, germany")
    }

    @Test func implausibleCoordinateFallsBackToAddressKey() async throws {
        // Covers "fehlerhafte oder fehlende Koordinaten": a broken
        // coordinate must not silently produce a bogus coordinate key.
        let location = PrayerLocation(name: "Broken", coordinate: GeoCoordinate(latitude: 0, longitude: 0))
        let key = LocationKey.key(address: "Broken, DE", location: location)
        #expect(key == "addr:broken, de")
    }

    @Test func twoDifferentCoordinatesProduceDifferentKeys() async throws {
        // The two different "Essen"s in the bundled city list — same name,
        // different places. Their keys must never collide.
        let essenRuhr = PrayerLocation(name: "Essen, Germany", coordinate: GeoCoordinate(latitude: 51.4508, longitude: 7.0131))
        let essenOldenburg = PrayerLocation(name: "Essen, Germany", coordinate: GeoCoordinate(latitude: 52.7167, longitude: 8.4667))

        let key1 = LocationKey.key(address: essenRuhr.name, location: essenRuhr)
        let key2 = LocationKey.key(address: essenOldenburg.name, location: essenOldenburg)

        #expect(key1 != key2)
    }

    @Test func tinyGPSJitterStillProducesTheSameKey() async throws {
        let a = PrayerLocation(name: "Berlin, Germany", coordinate: GeoCoordinate(latitude: 52.52001, longitude: 13.40501))
        let b = PrayerLocation(name: "Berlin, Germany", coordinate: GeoCoordinate(latitude: 52.52002, longitude: 13.40498))

        let key1 = LocationKey.key(address: a.name, location: a)
        let key2 = LocationKey.key(address: b.name, location: b)

        #expect(key1 == key2)
    }
}
