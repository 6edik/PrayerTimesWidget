import Foundation
import CoreLocation
import MapKit

protocol ReverseGeocodingServiceType: AnyObject {
    func cancel()
    func resolveCityLabel(for location: CLLocation) async -> String
}

@MainActor
final class ReverseGeocodingService: ReverseGeocodingServiceType {
    private var request: MKReverseGeocodingRequest?

    func cancel() {
        request?.cancel()
        request = nil
    }

    func resolveCityLabel(for location: CLLocation) async -> String {
        guard let newRequest = MKReverseGeocodingRequest(location: location) else {
            return "Aktueller Standort"
        }

        request?.cancel()
        request = newRequest

        do {
            let mapItems = try await newRequest.mapItems
            request = nil

            let item = mapItems.first
            return item?.name ??
                   item?.address?.shortAddress ??
                   item?.address?.fullAddress ??
                   "Aktueller Standort"
        } catch {
            request = nil
            return "Aktueller Standort"
        }
    }
}
