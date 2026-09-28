import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the core guarantee behind this app's coordinate-only requirement:
/// `PrayerTimesService` refuses to make any request — single-day or
/// calendar — without a plausible coordinate, rather than falling back to
/// an address-based AlAdhan endpoint. These guards run before any network
/// call, so they're deterministic without a live connection.
struct PrayerTimesServiceRequiresCoordinateTests {
    @Test func singleDayFetchThrowsMissingCoordinateWithoutLocation() async throws {
        let service = PrayerTimesService()
        let settings = PrayerSettings(address: "Irgendwo", location: nil, date: Date(), method: .ditib)

        do {
            _ = try await service.fetchPrayerTimesForSingleDayUncached(settings: settings)
            Issue.record("Expected PrayerTimesServiceError.missingCoordinate")
        } catch PrayerTimesServiceError.missingCoordinate {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func singleDayFetchThrowsMissingCoordinateForImplausibleCoordinate() async throws {
        let service = PrayerTimesService()
        // (0, 0) is deliberately treated as "not a real place" by
        // `GeoCoordinate.isPlausible`.
        let location = PrayerLocation(name: "Null Island", coordinate: GeoCoordinate(latitude: 0, longitude: 0))
        let settings = PrayerSettings(address: "Null Island", location: location, date: Date(), method: .ditib)

        do {
            _ = try await service.fetchPrayerTimesForSingleDayUncached(settings: settings)
            Issue.record("Expected PrayerTimesServiceError.missingCoordinate")
        } catch PrayerTimesServiceError.missingCoordinate {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func calendarCacheFetchThrowsMissingCoordinateWithoutLocation() async throws {
        let service = PrayerTimesService()
        let settings = PrayerSettings(address: "Irgendwo", location: nil, date: Date(), method: .ditib)

        do {
            _ = try await service.fetchPrayerTimesCache(settings: settings)
            Issue.record("Expected PrayerTimesServiceError.missingCoordinate")
        } catch PrayerTimesServiceError.missingCoordinate {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
