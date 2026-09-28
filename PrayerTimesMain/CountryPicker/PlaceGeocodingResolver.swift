import Foundation
import CoreLocation
import MapKit

/// One geocoded candidate place for a typed city/country pair — always
/// carries a concrete coordinate, never just a name, so a caller can turn it
/// straight into a `PrayerLocation` without any further guessing.
nonisolated struct GeocodedPlaceCandidate: Identifiable, Equatable {
    nonisolated var id: String { "\(displayName)-\(coordinate.roundedForCacheKey)" }
    let displayName: String
    let coordinate: GeoCoordinate
    let countryCode: String
}

/// Result of resolving a typed city name against a chosen country. Modeled
/// as distinct cases (rather than an optional/throws pair) so callers can't
/// accidentally collapse "multiple candidates" and "resolved" into the same
/// code path — every case must be handled explicitly before a coordinate
/// is ever attached to a saved location.
nonisolated enum PlaceResolutionOutcome: Equatable {
    /// Exactly one place in the requested country matched.
    case resolved(GeocodedPlaceCandidate)
    /// More than one place in the requested country matched — the caller
    /// must let the user pick, never take the first result silently.
    case multipleCandidates([GeocodedPlaceCandidate])
    /// The name matched somewhere, but never in the requested country —
    /// never silently substitute a different country's coordinate.
    case countryMismatch
    /// No match anywhere.
    case notFound
    case failed(String)
}

/// UI-facing state for an in-progress/failed place resolution — shared by
/// every screen that lets the user type a free-text city (settings, manual
/// query) so both stay in sync in behavior and wording.
nonisolated enum PlaceResolutionState: Equatable {
    case idle
    case resolving
    case failed(String)
}

/// Narrow seam around forward geocoding so views/view models depend on this
/// instead of MapKit/CoreLocation directly, and tests can substitute a fake.
protocol PlaceResolving: Sendable {
    nonisolated func resolve(city: String, countryCode: String, countryName: String) async -> PlaceResolutionOutcome
}

/// Resolves a typed city name to a coordinate, constrained to the country
/// the user already picked, using the iOS 26 `MKGeocodingRequest` API (the
/// project's deployment target is 27.0, so this is always available — no
/// pre-iOS-26 `CLGeocoder` fallback is reachable and none is kept). Never
/// returns a coordinate from a country other than the one requested — those
/// matches are reported via `.countryMismatch` instead of being silently
/// accepted.
///
/// Every member below is `nonisolated`, matching this module's convention
/// (see `PrayerTimesService`/`GeoCoordinate`/`PrayerLocation`) so this type
/// stays freely callable from non-`@MainActor` contexts, including plain
/// (non-`@MainActor`) test structs.
struct PlaceGeocodingResolver: PlaceResolving {
    nonisolated init() {}

    nonisolated func resolve(city: String, countryCode: String, countryName: String) async -> PlaceResolutionOutcome {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else { return .notFound }

        guard let request = MKGeocodingRequest(addressString: trimmedCity) else {
            return .failed("Ort konnte nicht aufgelöst werden.")
        }

        do {
            let mapItems = try await request.mapItems

            let allCandidates: [GeocodedPlaceCandidate] = mapItems.compactMap { item in
                candidate(
                    name: item.addressRepresentations?.cityName ?? item.name,
                    regionName: item.addressRepresentations?.regionName,
                    coordinate: item.location.coordinate
                )
            }

            return outcome(from: allCandidates, requestedCountryCode: countryCode)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// MapKit's iOS 26 geocoding surface only exposes a region *name* (not
    /// a reliable ISO code) on `MKAddressRepresentations`, so the country
    /// code is resolved the same way the rest of this app already matches
    /// a detected place's country name back to a `CountryItem` (see
    /// `PrayerLocationPickerViewModel`/`onReceive(locationHelper.$detectedPlace)`).
    nonisolated private func candidate(
        name: String?,
        regionName: String?,
        coordinate: CLLocationCoordinate2D?
    ) -> GeocodedPlaceCandidate? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let regionName, !regionName.isEmpty,
              let matchedCountryCode = countryCode(matchingRegionName: regionName),
              let coordinate else {
            return nil
        }

        let geoCoordinate = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard geoCoordinate.isPlausible else { return nil }

        let displayParts = [name, regionName].filter { !$0.isEmpty }
        let displayName = (displayParts + [matchedCountryCode.uppercased()]).joined(separator: ", ")

        return GeocodedPlaceCandidate(
            displayName: displayName,
            coordinate: geoCoordinate,
            countryCode: matchedCountryCode.uppercased()
        )
    }

    nonisolated private func countryCode(matchingRegionName regionName: String) -> String? {
        CountryList.all.first(where: {
            $0.name.compare(regionName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
            regionName.localizedCaseInsensitiveContains($0.name) ||
            $0.name.localizedCaseInsensitiveContains(regionName)
        })?.code
    }

    /// Hard country filter: candidates whose `countryCode` doesn't match
    /// the requested one are never returned as `.resolved`/`.multipleCandidates`
    /// — at most they turn an empty result into `.countryMismatch` instead
    /// of `.notFound`, so the caller can explain *why* nothing usable came
    /// back rather than just failing silently.
    ///
    /// Internal (not `private`) so `@testable import` can exercise the
    /// filtering/disambiguation logic directly with fake candidates,
    /// without depending on live network/MapKit results.
    nonisolated func outcome(
        from candidates: [GeocodedPlaceCandidate],
        requestedCountryCode: String
    ) -> PlaceResolutionOutcome {
        let requested = requestedCountryCode.uppercased()
        let matching = uniqued(candidates.filter { $0.countryCode == requested })

        switch matching.count {
        case 0:
            return candidates.isEmpty ? .notFound : .countryMismatch
        case 1:
            return .resolved(matching[0])
        default:
            return .multipleCandidates(matching)
        }
    }

    nonisolated private func uniqued(_ candidates: [GeocodedPlaceCandidate]) -> [GeocodedPlaceCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }
}
