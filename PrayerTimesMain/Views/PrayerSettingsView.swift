import SwiftUI
import CoreLocation
import Combine

struct PrayerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AutoPrayerViewModel()
    @StateObject private var locationHelper = PrayerLocationPickerViewModel()

    let onSaved: () -> Void

    @State private var selectedCityFromPicker = ""
    @State private var manualCity = ""
    @State private var selectedCountryCode = ""
    @State private var method: PrayerCalculationMethod = .ditib
    @State private var cityInputMode: CityInputMode = .manual

    @State private var didLoadInitialValues = false
    @State private var isApplyingCurrentLocation = false

    private var isGermanySelected: Bool {
        selectedCountryCode.uppercased() == "DE"
    }

    private var effectiveCity: String {
        switch cityInputMode {
        case .picker:
            return selectedCityFromPicker.trimmingCharacters(in: .whitespacesAndNewlines)
        case .manual:
            return manualCity.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var availableCityInputModes: [CityInputMode] {
        isGermanySelected ? CityInputMode.allCases : [.manual]
    }

    var body: some View {
        NavigationStack {
                AppPageHeader(title: "Einstellungen")
                    .fontDesign(nil)
            Form {
                Section("Standort") {
                    Button {
                        isApplyingCurrentLocation = true
                        locationHelper.requestCurrentPlace()
                    } label: {
                        Label("Aktuellen Standort verwenden", systemImage: "location.fill")
                    }

                    if let error = locationHelper.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    NavigationLink {
                        CountryPickerView(selection: $selectedCountryCode)
                    } label: {
                        HStack {
                            Text("Land")
                            Spacer()
                            Text(countryDisplayName(for: selectedCountryCode) ?? "Auswählen")
                                .foregroundStyle(selectedCountryCode.isEmpty ? .secondary : .primary)
                        }
                    }

                    Picker("Stadt-Eingabe", selection: $cityInputMode) {
                        ForEach(availableCityInputModes) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if cityInputMode == .picker && isGermanySelected {
                        NavigationLink {
                            CityPickerView(selection: $selectedCityFromPicker)
                        } label: {
                            HStack {
                                Text("Stadt")
                                Spacer()
                                Text(selectedCityFromPicker.isEmpty ? "Aus Liste wählen" : selectedCityFromPicker)
                                    .foregroundStyle(selectedCityFromPicker.isEmpty ? .secondary : .primary)
                            }
                        }
                    }

                    if cityInputMode == .manual || !isGermanySelected {
                        TextField("Stadt manuell eingeben", text: $manualCity)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }

                Section("Automatische Daten") {
                    Picker("Methode", selection: $method) {
                        ForEach(PrayerCalculationMethod.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }

                Section("Hinweis") {
                    Text("Diese Einstellungen gelten für tägliche API-Abfrage, Cache und Widget.")
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        let normalizedCity = effectiveCity
                        let countryName = countryNameOnly(for: selectedCountryCode) ?? ""
                        let address = [normalizedCity, countryName]
                            .filter { !$0.isEmpty }
                            .joined(separator: ", ")

                        viewModel.saveSettings(
                            address: address,
                            method: method
                        )

                        onSaved()
                        dismiss()
                    }
                    .disabled(
                        effectiveCity.isEmpty ||
                        selectedCountryCode.isEmpty
                    )
                }
            }
            .onAppear {
                guard !didLoadInitialValues else { return }
                didLoadInitialValues = true

                viewModel.reloadLocalState()
                method = viewModel.autoSettings.method

                let parts = viewModel.autoSettings.address
                    .split(separator: ",", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                if let first = parts.first {
                    manualCity = first
                    selectedCityFromPicker = first
                }

                if parts.count > 1 {
                    let savedCountry = parts[1]

                    if let exactCodeMatch = CountryList.all.first(where: {
                        $0.code.compare(savedCountry, options: [.caseInsensitive]) == .orderedSame
                    }) {
                        selectedCountryCode = exactCodeMatch.code
                    } else if let nameMatch = CountryList.all.first(where: {
                        $0.name.compare(savedCountry, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    }) {
                        selectedCountryCode = nameMatch.code
                    }
                }

                if isGermanySelected {
                    cityInputMode = selectedCityFromPicker.isEmpty ? .manual : .picker
                } else {
                    cityInputMode = .manual
                }
            }
            .onChange(of: selectedCountryCode) { oldValue, newValue in
                guard oldValue != newValue else { return }

                if !isGermanySelected && cityInputMode == .picker {
                    cityInputMode = .manual
                }

                guard !oldValue.isEmpty, !isApplyingCurrentLocation else { return }

                if oldValue != newValue {
                    selectedCityFromPicker = ""
                }
            }
            .onReceive(locationHelper.$detectedPlace) { place in
                guard isApplyingCurrentLocation, let place else { return }

                manualCity = place.city
                selectedCityFromPicker = place.city
                cityInputMode = .manual

                if let match = CountryList.all.first(where: {
                    $0.name.compare(place.countryName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                    place.countryName.localizedCaseInsensitiveContains($0.name) ||
                    $0.name.localizedCaseInsensitiveContains(place.countryName)
                }) {
                    selectedCountryCode = match.code
                } else {
                    selectedCountryCode = ""
                }

                isApplyingCurrentLocation = false
            }
        }
    }

    private func countryDisplayName(for code: String) -> String? {
        CountryList.all.first(where: { $0.code == code })?.displayName
    }

    private func countryNameOnly(for code: String) -> String? {
        CountryList.all.first(where: { $0.code == code })?.name
    }
}
