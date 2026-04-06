import SwiftUI

struct CityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    @StateObject private var viewModel = CityPickerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Deutsche Städte werden geladen …")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)

                        Text("Fehler beim Laden")
                            .font(.headline)

                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                } else if viewModel.filteredCities.isEmpty {
                    ContentUnavailableView(
                        "Keine Städte gefunden",
                        systemImage: "magnifyingglass",
                        description: Text("Suche nach deutscher Stadt.")
                    )
                } else {
                    List(viewModel.filteredCities) { city in
                        Button {
                            selection = city.name
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(city.name)
                                    .foregroundStyle(.primary)
                                    .fontDesign(.rounded)

                                if !city.subtitle.isEmpty {
                                    Text(city.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Stadt wählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Stadt suchen (DE)")
            .task {
                await viewModel.loadIfNeeded()
            }
        }
    }
}
