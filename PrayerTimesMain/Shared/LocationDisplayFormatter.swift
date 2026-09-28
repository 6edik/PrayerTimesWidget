import Foundation

/// Single, shared formatting for the coordinate line shown directly under a
/// confirmed location's display name — so Home, the settings screen and the
/// cached-times inspector all render exactly the coordinate pair that was
/// actually sent to AlAdhan, never a placeholder or a stale value left over
/// from a previous place.
enum LocationDisplayFormatter {
    nonisolated static func line(for location: PrayerLocation) -> String {
        let prefix = location.source == .currentLocation ? "Aktueller Standort" : "Stadtkoordinaten"
        return "\(prefix): \(coordinateText(for: location.coordinate))"
    }

    /// "51,5170° N · 7,1000° O" — German comma decimal separator, four
    /// decimal places (matching `GeoCoordinate.roundedForCacheKey`'s
    /// precision), N/S and O/W chosen from the coordinate's own sign.
    nonisolated static func coordinateText(for coordinate: GeoCoordinate) -> String {
        let latDirection = coordinate.latitude >= 0 ? "N" : "S"
        let lonDirection = coordinate.longitude >= 0 ? "O" : "W"

        let latText = germanDecimal(abs(coordinate.latitude))
        let lonText = germanDecimal(abs(coordinate.longitude))

        return "\(latText)° \(latDirection) · \(lonText)° \(lonDirection)"
    }

    private nonisolated static func germanDecimal(_ value: Double) -> String {
        String(format: "%.4f", value).replacingOccurrences(of: ".", with: ",")
    }
}
