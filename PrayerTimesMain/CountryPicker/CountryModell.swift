import Foundation

struct CountryItem: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
    var displayName: String { "\(name) (\(code))" }
}

enum CountryList {
    static let all: [CountryItem] = {
        let locale = Locale(identifier: "de_DE")

        let codes: [String]
        if #available(iOS 16, *) {
            codes = Locale.Region.isoRegions
                .filter { $0.subRegions.isEmpty }
                .map(\.identifier)
        } else {
            codes = Locale.isoRegionCodes
        }

        return codes
            .compactMap { code in
                guard let name = locale.localizedString(forRegionCode: code) else {
                    return nil
                }
                return CountryItem(code: code, name: name)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }()
}
