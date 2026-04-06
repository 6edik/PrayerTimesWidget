import Foundation
import CoreLocation

enum QiblaCalculator {
    static let kaaba = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    static func bearing(
        from user: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D = kaaba
    ) -> Double {
        let userLat = user.latitude.radians
        let userLon = user.longitude.radians
        let destLat = destination.latitude.radians
        let destLon = destination.longitude.radians

        let dLon = destLon - userLon

        let y = sin(dLon) * cos(destLat)
        let x = cos(userLat) * sin(destLat) - sin(userLat) * cos(destLat) * cos(dLon)

        let radians = atan2(y, x)
        let degrees = radians.degrees

        return normalized(degrees)
    }

    static func distance(
        from user: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D = kaaba
    ) -> Double {
        let start = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let end = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return start.distance(from: end) / 1000
    }

    static func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
