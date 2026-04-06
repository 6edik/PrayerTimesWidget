import Foundation
import CoreLocation
import Combine

@MainActor
final class QiblaViewModel: NSObject, ObservableObject {
    @Published var state = QiblaState()

    let needleAnimator = QiblaNeedleAnimator()

    private let locationService: QiblaLocationService
    private let reverseGeocodingService: ReverseGeocodingServiceType

    private var lastGeocodedLocation: CLLocation?
    private var lastResolvedLocation: CLLocation?
    private var lastLocationRequestDate: Date?
    private var isGeocoding = false
    private var isRunning = false

    private let locationRefreshInterval: TimeInterval = 180
    private let requestDebounceInterval: TimeInterval = 8
    private let acceptableLocationAccuracy: CLLocationAccuracy = 300

    override init() {
        self.locationService = QiblaLocationService()
        self.reverseGeocodingService = ReverseGeocodingService()
        super.init()
        self.locationService.delegate = self
    }

    var canUseLiveLocation: Bool {
        isAuthorized
    }

    func start() {
        state.isHeadingAvailable = locationService.isHeadingAvailable

        guard !isRunning else {
            if shouldRequestFreshLocation() {
                requestFreshLocation()
            }
            return
        }

        isRunning = true
        state.errorMessage = nil

        if locationService.isHeadingAvailable {
            locationService.startHeadingUpdates()
        } else {
            state.errorMessage = "Auf diesem Gerät ist kein Kompass verfügbar."
        }

        if shouldRequestFreshLocation() {
            requestFreshLocation()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        needleAnimator.stop()
        locationService.stopAllUpdates()
        reverseGeocodingService.cancel()
    }

    func activateLocationAccess() {
        state.errorMessage = nil

        switch locationService.authorizationStatus {
        case .notDetermined:
            locationService.requestAuthorizationIfNeeded()

        case .authorizedWhenInUse, .authorizedAlways:
            requestFreshLocation(force: true)

        case .denied, .restricted:
            state.authorizationDenied = true
            state.errorMessage = "Standortzugriff wurde nicht erlaubt."

        @unknown default:
            break
        }
    }

    func refreshCurrentLocation() {
        requestFreshLocation(force: true)
    }

    func recalibrate() {
        state.errorMessage = nil
        reverseGeocodingService.cancel()
        needleAnimator.reset(to: state.userHeading)

        if locationService.isHeadingAvailable {
            locationService.startHeadingUpdates()
        }

        requestFreshLocation(force: true)
    }

    private var isAuthorized: Bool {
        let status = locationService.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func shouldRequestFreshLocation() -> Bool {
        guard isAuthorized else { return false }

        if let lastRequest = lastLocationRequestDate,
           Date().timeIntervalSince(lastRequest) < requestDebounceInterval {
            return false
        }

        guard let lastResolvedLocation else {
            return true
        }

        let age = Date().timeIntervalSince(lastResolvedLocation.timestamp)
        let accuracy = lastResolvedLocation.horizontalAccuracy

        if accuracy < 0 {
            return true
        }

        return age > locationRefreshInterval || accuracy > acceptableLocationAccuracy
    }

    private func requestFreshLocation(force: Bool = false) {
        guard isAuthorized else { return }

        if !force, !shouldRequestFreshLocation() {
            return
        }

        lastLocationRequestDate = Date()
        locationService.requestLocation()
    }

    private func handleAuthorizationChange() {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            state.authorizationDenied = false

            if isRunning {
                requestFreshLocation(force: true)
            }

        case .denied, .restricted:
            state.authorizationDenied = true
            state.errorMessage = "Standortzugriff wurde nicht erlaubt."

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }

    private func updateQibla(from location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }
        guard location.horizontalAccuracy <= 150 else { return }

        lastResolvedLocation = location

        state.qiblaBearing = QiblaCalculator.bearing(from: location.coordinate)
        state.distanceToKaabaKm = QiblaCalculator.distance(from: location.coordinate)
        state.coordinateLabel = Self.coordinateText(for: location.coordinate)

        guard shouldRefreshCityLabel(for: location) else { return }

        Task {
            await updateCityLabel(for: location)
        }
    }

    private func shouldRefreshCityLabel(for location: CLLocation) -> Bool {
        guard !isGeocoding else { return false }

        guard let lastGeocodedLocation else {
            return true
        }

        return location.distance(from: lastGeocodedLocation) >= 250
    }

    private func updateCityLabel(for location: CLLocation) async {
        guard !isGeocoding else { return }

        isGeocoding = true
        defer { isGeocoding = false }

        let label = await reverseGeocodingService.resolveCityLabel(for: location)
        state.cityLabel = label
        lastGeocodedLocation = location
    }

    private func updateHeading(_ newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }

        let rawHeading: CLLocationDirection

        if newHeading.trueHeading >= 0 {
            rawHeading = newHeading.trueHeading
            state.headingReference = .trueNorth
        } else {
            rawHeading = newHeading.magneticHeading
            state.headingReference = .magneticNorth
        }

        let normalized = QiblaCalculator.normalized(rawHeading)
        state.userHeading = normalized
        state.headingAccuracy = newHeading.headingAccuracy
        needleAnimator.setTargetHeading(normalized)
    }

    private static func coordinateText(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.4f", coordinate.latitude)
        let longitude = String(format: "%.4f", coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
}

extension QiblaViewModel: QiblaLocationServiceDelegate {
    func qiblaLocationServiceDidChangeAuthorization() {
        handleAuthorizationChange()
    }

    func qiblaLocationServiceDidUpdateLocation(_ location: CLLocation) {
        updateQibla(from: location)
    }

    func qiblaLocationServiceDidUpdateHeading(_ heading: CLHeading) {
        updateHeading(heading)
    }

    func qiblaLocationServiceDidFail(with error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }

        state.errorMessage = error.localizedDescription
    }
}
