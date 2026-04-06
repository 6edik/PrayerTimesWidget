import Foundation
import SwiftUI
import Combine

@MainActor
final class CityPickerViewModel: ObservableObject {
    @Published var allCities: [CityItem] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    var filteredCities: [CityItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allCities }

        return allCities.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.admin1?.localizedCaseInsensitiveContains(query) == true ||
            $0.admin2?.localizedCaseInsensitiveContains(query) == true
        }
    }

    func loadIfNeeded() async {
        guard allCities.isEmpty, !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            allCities = try await CityLoader.loadGermanCities()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
