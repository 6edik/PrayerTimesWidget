import SwiftUI
import CoreLocation
import Combine

struct ManualQueryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManualPrayerViewModel()
    @StateObject private var locationHelper = PrayerLocationPickerViewModel()

    @State private var selectedCityFromPicker = ""
    @State private var manualCity = ""
    @State private var selectedCountryCode = ""
    @State private var cityInputMode: CityInputMode = .manual

    @State private var isApplyingCurrentLocation = false
    @State private var didLoadInitialValues = false

    private var isGermanySelected: Bool {
        selectedCountryCode.uppercased() == "DE"
    }

    private var availableCityInputModes: [CityInputMode] {
        isGermanySelected ? CityInputMode.allCases : [.manual]
    }

    private var effectiveCity: String {
        switch cityInputMode {
        case .picker:
            return selectedCityFromPicker.trimmingCharacters(in: .whitespacesAndNewlines)
        case .manual:
            return manualCity.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var effectiveAddress: String {
        let city = effectiveCity
        let countryName = countryNameOnly(for: selectedCountryCode) ?? ""

        return [city, countryName]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            AppPageHeader(title: "Gebetszeiten Suche")
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

                Section("Manuelle Abfrage") {
                    Picker("Methode", selection: $viewModel.query.method) {
                        ForEach(PrayerCalculationMethod.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    DatePicker(
                        "Datum",
                        selection: $viewModel.query.date,
                        displayedComponents: .date
                    )
                }

                Section {
                    Button("Zeiten laden") {
                        Task {
                            await viewModel.runQuery(address: effectiveAddress)
                        }
                    }
                    .disabled(
                        effectiveCity.isEmpty ||
                        selectedCountryCode.isEmpty ||
                        viewModel.isLoading
                    )
                }

                if viewModel.isLoading {
                    Section {
                        ProgressView("Lade Gebetszeiten …")
                    }
                }

                if let result = viewModel.result {
                    Section("Ergebnis") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(result.address)
                                .font(.headline)

                            Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)

                            Text(result.method.title)
                                .foregroundStyle(.secondary)

                            Divider()

                            row("Fajr", result.times.fajr)
                            row("Shuruk", result.times.shuruk)
                            row("Dhuhr", result.times.dhuhr)
                            row("Asr", result.times.asr)
                            row("Maghrib", result.times.maghrib)
                            row("Isha", result.times.isha)
                        }
                    }

                    Section("Info") {
                        Text(result.times.readableDate)
                        Text(result.times.hijriDate)
                        Text(result.times.timezone)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Fehler") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.resetToAutoDefaults()

                        let parts = viewModel.query.address
                            .split(separator: ",", maxSplits: 1)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                        if let first = parts.first {
                            manualCity = first
                            selectedCityFromPicker = first
                        } else {
                            manualCity = ""
                            selectedCityFromPicker = ""
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
                            } else {
                                selectedCountryCode = ""
                            }
                        } else {
                            selectedCountryCode = ""
                        }

                        cityInputMode = isGermanySelected && !selectedCityFromPicker.isEmpty ? .picker : .manual
                    } label: {
                        Label("Auto-Werte", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .onAppear {
                guard !didLoadInitialValues else { return }
                didLoadInitialValues = true

                let parts = viewModel.query.address
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

                if !oldValue.isEmpty, oldValue != newValue, !isApplyingCurrentLocation {
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

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    private func countryDisplayName(for code: String) -> String? {
        CountryList.all.first(where: { $0.code == code })?.displayName
    }

    private func countryNameOnly(for code: String) -> String? {
        CountryList.all.first(where: { $0.code == code })?.name
    }
}
