import Foundation
import CoreLocation

protocol QiblaLocationServiceDelegate: AnyObject {
    func qiblaLocationServiceDidChangeAuthorization()
    func qiblaLocationServiceDidUpdateLocation(_ location: CLLocation)
    func qiblaLocationServiceDidUpdateHeading(_ heading: CLHeading)
    func qiblaLocationServiceDidFail(with error: Error)
}

@MainActor
final class QiblaLocationService: NSObject {
    weak var delegate: QiblaLocationServiceDelegate?

    private let manager = CLLocationManager()

    override init() {
        super.init()

        manager.delegate = self
        // "Best" can make the one-shot requestLocation() wait noticeably
        // longer for a GPS-grade fix. Qibla bearing barely changes over a
        // few hundred meters, so a much faster WiFi/cell-assisted fix is
        // plenty accurate here.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // kCLHeadingFilterNone delivers a heading update on every tiny
        // sensor fluctuation (tens of times per second), which was driving
        // a full SwiftUI re-render of the whole Qibla page each time and
        // making the UI feel janky. 1° is imperceptible for a compass but
        // cuts the update rate drastically.
        manager.headingFilter = 1
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        manager.allowsBackgroundLocationUpdates = false
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isHeadingAvailable: Bool {
        CLLocationManager.headingAvailable()
    }

    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stopHeadingUpdates() {
        manager.stopUpdatingHeading()
    }

    func stopAllUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}

extension QiblaLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            delegate?.qiblaLocationServiceDidChangeAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            delegate?.qiblaLocationServiceDidUpdateLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }

        Task { @MainActor in
            delegate?.qiblaLocationServiceDidUpdateHeading(newHeading)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            delegate?.qiblaLocationServiceDidFail(with: error)
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
