import Foundation

/// Single, shared normalization for address strings so that cache validation,
/// manual-query "same address" checks and the network layer all agree on
/// whether two address strings refer to the same place.
enum AddressNormalizer {
    nonisolated static func normalized(_ address: String) -> String {
        let collapsedWhitespace = address
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsedWhitespace
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
