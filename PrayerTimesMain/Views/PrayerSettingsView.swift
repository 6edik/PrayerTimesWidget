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

    @State private var fajrAdjustment = 0
    @State private var shurukAdjustment = 0
    @State private var dhuhrAdjustment = 0
    @State private var asrAdjustment = 0
    @State private var maghribAdjustment = 0
    @State private var ishaAdjustment = 0

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

    private var adjustments: PrayerAdjustments {
        PrayerAdjustments(
            fajr: fajrAdjustment,
            shuruk: shurukAdjustment,
            dhuhr: dhuhrAdjustment,
            asr: asrAdjustment,
            maghrib: maghribAdjustment,
            isha: ishaAdjustment
        )
    }

    var body: some View {
        NavigationStack {
            AppPageHeader(title: "Zeitparameter")
                .fontDesign(nil)

            Form {
                Section("Gebetsprofil") {
                    Picker("Methode", selection: $method) {
                        ForEach(PrayerCalculationMethod.allCases) { item in
                            Text(item.title).tag(item)
                        }
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

                    Picker("Stadt-Eingabe", selection: $cityInputMode) {
                        ForEach(availableCityInputModes) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        isApplyingCurrentLocation = true
                        locationHelper.requestCurrentPlace()
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .accessibilityLabel("Aktuellen Standort verwenden")

                    if let error = locationHelper.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Justierung") {
                    adjustmentRow(title: "Fajr", value: $fajrAdjustment)
                    adjustmentRow(title: "Shuruk", value: $shurukAdjustment)
                    adjustmentRow(title: "Dhuhr", value: $dhuhrAdjustment)
                    adjustmentRow(title: "Asr", value: $asrAdjustment)
                    adjustmentRow(title: "Maghrib", value: $maghribAdjustment)
                    adjustmentRow(title: "Isha", value: $ishaAdjustment)
                }

                Section("Hinweis") {
                    Text("Die API-Werte bleiben im Cache unverändert. Die Minuten-Justierung wird erst bei der Anzeige in App und Widget angewendet.")
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
                            method: method,
                            adjustments: adjustments
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

                let savedAdjustments = viewModel.autoSettings.adjustments
                fajrAdjustment = savedAdjustments.fajr
                shurukAdjustment = savedAdjustments.shuruk
                dhuhrAdjustment = savedAdjustments.dhuhr
                asrAdjustment = savedAdjustments.asr
                maghribAdjustment = savedAdjustments.maghrib
                ishaAdjustment = savedAdjustments.isha

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

                selectedCityFromPicker = ""
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

    @ViewBuilder
    private func adjustmentRow(title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: -60...60, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedOffset(value.wrappedValue))
                    .foregroundStyle(value.wrappedValue == 0 ? .secondary : .primary)
                    .monospacedDigit()
            }
        }
    }

    private func formattedOffset(_ value: Int) -> String {
        if value == 0 { return "0 Min." }
        return value > 0 ? "+\(value) Min." : "\(value) Min."
    }

    private func countryDisplayName(for code: String) -> String? {
        CountryList.all.first(where: { $0.code == code })?.displayName
    }

    private func countryNameOnly(for code: String) -> String? {
        CountryList.all.first(where: { $0.code == code })?.name
    }
}
