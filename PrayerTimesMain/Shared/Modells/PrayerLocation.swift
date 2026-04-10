import Foundation

/// A geographic coordinate pair, kept separate from `CLLocationCoordinate2D`
/// so it can be `Codable`/`Equatable` without pulling in CoreLocation here.
struct GeoCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    /// Basic sanity check — rejects obviously broken values (e.g. 0,0 from
    /// an uninitialized struct, or out-of-range numbers) before they're ever
    /// sent to AlAdhan or written to settings.
    nonisolated var isPlausible: Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        // (0, 0) is "Null Island" in the Atlantic — never a real prayer
        // location in this app, so it's a reliable signal of an
        // uninitialized/failed coordinate rather than an actual place.
        if latitude == 0, longitude == 0 { return false }
        return true
    }

    /// Rounded to ~11m precision — enough to treat "the same place" as
    /// equal for cache-key purposes while collapsing GPS jitter between
    /// requests for the same spot.
    nonisolated var roundedForCacheKey: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

/// A location the user has actually confirmed — either picked from the
/// bundled city list or resolved from a live GPS fix. `name` is always the
/// app's own display text (city list entry or reverse-geocoded label),
/// never anything read from AlAdhan's response — AlAdhan is not a reliable
/// source of place names, only of prayer-time calculations for a given
/// coordinate.
struct PrayerLocation: Codable, Equatable {
    var name: String
    var coordinate: GeoCoordinate

    /// Gelsenkirchen's coordinate from the project's own `DE_cities.json`
    /// (looked up once, verified — not derived from the name at runtime).
    /// Used only as the app's shipped default location.
    nonisolated static let defaultGelsenkirchen = PrayerLocation(
        name: "Gelsenkirchen, DE",
        coordinate: GeoCoordinate(latitude: 51.517, longitude: 7.100)
    )
}

/// Single place that decides the App-Group cache key for a set of prayer
/// settings. Coordinate-confirmed locations key on their (rounded)
/// coordinate — never on the display name, since the bundled city list
/// alone contains 22 duplicate names (e.g. two different "Essen"s), so a
/// name-based key could serve one city's cached times under another's
/// name. Settings without a confirmed location (legacy data, free-text
/// addresses) fall back to the normalized address string, exactly as
/// before.
enum LocationKey {
    nonisolated static func key(address: String, location: PrayerLocation?) -> String {
        if let location, location.coordinate.isPlausible {
            return "coord:\(location.coordinate.roundedForCacheKey)"
        }
        return "addr:\(AddressNormalizer.normalized(address))"
    }
}
