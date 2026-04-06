import Foundation
import CoreLocation

enum HeadingReference: String {
    case trueNorth
    case magneticNorth

    var label: String {
        switch self {
        case .trueNorth:
            return "Geografisch"
        case .magneticNorth:
            return "Magnetisch"
        }
    }
}

struct QiblaState {
    var qiblaBearing: Double = 0
    var distanceToKaabaKm: Double = 0

    var userHeading: Double = 0
    var headingAccuracy: Double = -1
    var headingReference: HeadingReference = .trueNorth

    var cityLabel: String = "Standort wird ermittelt…"
    var coordinateLabel: String = "—"

    var authorizationDenied = false
    var isHeadingAvailable = CLLocationManager.headingAvailable()
    var errorMessage: String?

    var bearingText: String {
        "\(Int(qiblaBearing.rounded()))°"
    }

    var userHeadingText: String {
        "\(Int(userHeading.rounded()))°"
    }

    var accuracyText: String {
        guard headingAccuracy >= 0 else { return "—" }
        return "±\(Int(headingAccuracy.rounded()))°"
    }
}
