import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the coordinate line shown directly under a confirmed location's
/// name: German comma decimals, correct N/S/O/W direction letters, and the
/// right label ("Stadtkoordinaten" vs. "Aktueller Standort") for the
/// location's `source`.
struct LocationDisplayFormatterTests {
    @Test func confirmedPlaceUsesStadtkoordinatenLabel() async throws {
        let location = PrayerLocation(
            name: "Gelsenkirchen, DE",
            coordinate: GeoCoordinate(latitude: 51.517, longitude: 7.100),
            source: .confirmedPlace
        )

        let line = LocationDisplayFormatter.line(for: location)

        #expect(line == "Stadtkoordinaten: 51,5170° N · 7,1000° O")
    }

    @Test func currentLocationUsesAktuellerStandortLabel() async throws {
        let location = PrayerLocation(
            name: "Aktueller Standort",
            coordinate: GeoCoordinate(latitude: 51.517, longitude: 7.100),
            source: .currentLocation
        )

        let line = LocationDisplayFormatter.line(for: location)

        #expect(line.hasPrefix("Aktueller Standort: "))
        #expect(!line.hasPrefix("Stadtkoordinaten"))
    }

    @Test func negativeLatitudeAndLongitudeUseSouthAndWest() async throws {
        // Buenos Aires-ish coordinate: south of the equator, west of
        // Greenwich — both directions must flip from the German default.
        let coordinate = GeoCoordinate(latitude: -34.6037, longitude: -58.3816)
        let text = LocationDisplayFormatter.coordinateText(for: coordinate)

        #expect(text.contains("S"))
        #expect(text.contains("W"))
        #expect(!text.contains("-"))
    }

    @Test func usesGermanCommaDecimalSeparator() async throws {
        let coordinate = GeoCoordinate(latitude: 48.1234, longitude: 11.5678)
        let text = LocationDisplayFormatter.coordinateText(for: coordinate)

        #expect(text.contains("48,1234"))
        #expect(text.contains("11,5678"))
        #expect(!text.contains("."))
    }
}
