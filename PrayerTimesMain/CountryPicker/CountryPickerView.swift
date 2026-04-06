import SwiftUI

struct CountryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var searchText = ""

    private var filteredCountries: [CountryItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CountryList.all
        }

        return CountryList.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredCountries) { country in
            Button {
                selection = country.code
                dismiss()
            } label: {
                HStack {
                    Text(country.name)
                    Spacer()
                    Text(country.code)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Land")
        .searchable(text: $searchText, prompt: "Land suchen")
    }
}
