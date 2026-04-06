import Foundation
import CoreLocation
import MapKit
import Combine

@MainActor
final class PrayerLocationPickerViewModel: NSObject, ObservableObject {
    struct DetectedPlace: Equatable {
        let city: String
        let countryName: String
    }

    @Published var detectedPlace: DetectedPlace?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentPlace() {
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()

        case .denied, .restricted:
            errorMessage = "Standortzugriff wurde nicht erlaubt."

        @unknown default:
            break
        }
    }

    private func resolvePlace(from location: CLLocation) async {
        do {
            if #available(iOS 26, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    errorMessage = "Ort konnte nicht ermittelt werden."
                    return
                }

                let mapItems = try await request.mapItems
                guard let item = mapItems.first else {
                    errorMessage = "Ort konnte nicht ermittelt werden."
                    return
                }

                let city = resolvedCity(from: item)
                let countryName = resolvedCountry(from: item)

                guard !city.isEmpty, !countryName.isEmpty else {
                    errorMessage = "Stadt oder Land konnten nicht vollständig ermittelt werden."
                    return
                }

                detectedPlace = DetectedPlace(
                    city: normalized(city),
                    countryName: normalized(countryName)
                )
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else {
                    errorMessage = "Ort konnte nicht ermittelt werden."
                    return
                }

                let city =
                    placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? placemark.name
                    ?? ""

                let countryName =
                    placemark.country
                    ?? placemark.isoCountryCode
                    ?? ""

                guard !city.isEmpty, !countryName.isEmpty else {
                    errorMessage = "Stadt oder Land konnten nicht vollständig ermittelt werden."
                    return
                }

                detectedPlace = DetectedPlace(
                    city: normalized(city),
                    countryName: normalized(countryName)
                )
            }
        } catch {
            errorMessage = "Standort konnte nicht aufgelöst werden."
        }
    }

    @available(iOS 26, *)
    private func resolvedCity(from item: MKMapItem) -> String {
        if let value = item.addressRepresentations?.cityName, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        if let value = item.name, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        if let short = item.address?.shortAddress, !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let firstPart = short
                .split(separator: ",")
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let firstPart, !firstPart.isEmpty {
                return firstPart
            }
        }

        if let full = item.address?.fullAddress, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let firstPart = full
                .split(separator: ",")
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let firstPart, !firstPart.isEmpty {
                return firstPart
            }
        }

        return ""
    }

    @available(iOS 26, *)
    private func resolvedCountry(from item: MKMapItem) -> String {
        if let value = item.addressRepresentations?.regionName, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        if let short = item.address?.shortAddress, !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lastPart = short
                .split(separator: ",")
                .last
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let lastPart, !lastPart.isEmpty {
                return lastPart
            }
        }

        if let full = item.address?.fullAddress, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lastPart = full
                .split(separator: ",")
                .last
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let lastPart, !lastPart.isEmpty {
                return lastPart
            }
        }

        return ""
    }

    private func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension PrayerLocationPickerViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.errorMessage = "Standortzugriff wurde nicht erlaubt."
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            await resolvePlace(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}
