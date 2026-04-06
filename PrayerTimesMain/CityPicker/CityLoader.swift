import Foundation

enum CityLoader {
    static func loadGermanCities() async throws -> [CityItem] {
        guard let url = Bundle.main.url(forResource: "DE_cities", withExtension: "json") else {
            throw NSError(
                domain: "CityLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "DE_cities.json nicht gefunden"]
            )
        }

        return try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([CityItem].self, from: data)

            return items.sorted { lhs, rhs in
                if lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame {
                    return (lhs.population ?? 0) > (rhs.population ?? 0)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }.value
    }
}
