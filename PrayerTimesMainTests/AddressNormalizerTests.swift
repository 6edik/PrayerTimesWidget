import Testing
@testable import PrayerTimesMain

/// Covers N10: cache validation, the manual-query "same address" check and
/// the network layer must all agree on whether two address strings refer to
/// the same place.
@MainActor
struct AddressNormalizerTests {
    @Test func collapsesWhitespaceAndLowercases() async throws {
        #expect(AddressNormalizer.normalized("  Berlin,   Germany ") == AddressNormalizer.normalized("berlin, germany"))
    }

    @Test func foldsDiacritics() async throws {
        #expect(AddressNormalizer.normalized("Köln, Deutschland") == AddressNormalizer.normalized("koln, deutschland"))
    }

    @Test func differentPlacesStayDifferent() async throws {
        #expect(AddressNormalizer.normalized("Berlin, DE") != AddressNormalizer.normalized("Munich, DE"))
    }
}
