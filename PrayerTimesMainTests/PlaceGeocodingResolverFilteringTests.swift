import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the country-filtering/disambiguation logic inside
/// `PlaceGeocodingResolver` using fake candidates — no live network/MapKit
/// call, so this is deterministic. Exercises exactly the scenarios the spec
/// calls out: two same-named places in different countries must never be
/// silently merged, and a country the user didn't select must never be
/// substituted in.
struct PlaceGeocodingResolverFilteringTests {
    private func candidate(_ name: String, country: String, lat: Double, lon: Double) -> GeocodedPlaceCandidate {
        GeocodedPlaceCandidate(
            displayName: "\(name), \(country)",
            coordinate: GeoCoordinate(latitude: lat, longitude: lon),
            countryCode: country
        )
    }

    @Test func sameNameInDifferentCountriesKeepsOnlyTheRequestedCountry() async throws {
        // "Springfield" exists in both the US and (hypothetically) here in
        // country "XX" — only the requested country's match should ever be
        // returned as resolved.
        let candidates = [
            candidate("Springfield", country: "US", lat: 39.78, lon: -89.65),
            candidate("Springfield", country: "XX", lat: 10.0, lon: 10.0)
        ]

        let resolver = PlaceGeocodingResolver()
        let outcome = resolver.outcome(from: candidates, requestedCountryCode: "XX")

        guard case .resolved(let resolved) = outcome else {
            Issue.record("Expected a resolved candidate, got \(outcome)")
            return
        }
        #expect(resolved.countryCode == "XX")
        #expect(resolved.coordinate.latitude == 10.0)
    }

    @Test func matchOnlyInAnotherCountryReportsCountryMismatchNotFound() async throws {
        let candidates = [
            candidate("Springfield", country: "US", lat: 39.78, lon: -89.65)
        ]

        let resolver = PlaceGeocodingResolver()
        let outcome = resolver.outcome(from: candidates, requestedCountryCode: "DE")

        #expect(outcome == .countryMismatch)
    }

    @Test func noCandidatesAtAllReportsNotFound() async throws {
        let resolver = PlaceGeocodingResolver()
        let outcome = resolver.outcome(from: [], requestedCountryCode: "DE")

        #expect(outcome == .notFound)
    }

    @Test func multipleMatchesWithinTheSameRequestedCountryRequireDisambiguation() async throws {
        // Two different places with the same name, both in the requested
        // country (e.g. two German towns both called "Essen") — never take
        // the first one silently.
        let candidates = [
            candidate("Essen", country: "DE", lat: 51.45, lon: 7.01),
            candidate("Essen", country: "DE", lat: 51.28, lon: 6.97)
        ]

        let resolver = PlaceGeocodingResolver()
        let outcome = resolver.outcome(from: candidates, requestedCountryCode: "DE")

        guard case .multipleCandidates(let options) = outcome else {
            Issue.record("Expected multipleCandidates, got \(outcome)")
            return
        }
        #expect(options.count == 2)
    }

    @Test func exactDuplicateCandidatesAreDeduplicated() async throws {
        let duplicate = candidate("Essen", country: "DE", lat: 51.45, lon: 7.01)
        let resolver = PlaceGeocodingResolver()
        let outcome = resolver.outcome(from: [duplicate, duplicate], requestedCountryCode: "DE")

        #expect(outcome == .resolved(duplicate))
    }

    @Test func countryFilterIsCaseInsensitive() async throws {
        let candidates = [candidate("Essen", country: "DE", lat: 51.45, lon: 7.01)]
        let resolver = PlaceGeocodingResolver()
        let outcome = resolver.outcome(from: candidates, requestedCountryCode: "de")

        guard case .resolved = outcome else {
            Issue.record("Expected a resolved candidate, got \(outcome)")
            return
        }
    }
}
