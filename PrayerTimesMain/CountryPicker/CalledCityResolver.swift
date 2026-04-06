import Foundation
import CoreLocation
import MapKit

struct CalledCityResolver {
    nonisolated init() {}

    func resolve(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            let mapItems = try await request.mapItems
            guard let item = mapItems.first else { return nil }

            let cityCandidates: [String?] = [
                item.addressRepresentations?.cityName,
                item.name,
                firstAddressPart(from: item)
            ]

            let city = cityCandidates.compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }.first

            return city
        } catch {
            return nil
        }
    }

    private func firstAddressPart(from item: MKMapItem) -> String? {
        if let shortAddress = item.address?.shortAddress {
            return shortAddress
                .split(separator: ",")
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        if let fullAddress = item.address?.fullAddress {
            return fullAddress
                .split(separator: ",")
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        return nil
    }
}
