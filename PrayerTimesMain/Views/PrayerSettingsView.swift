import SwiftUI
import CoreLocation
import Combine

struct PrayerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceViewModel
    @StateObject private var viewModel = AutoPrayerViewModel()
    @StateObject private var locationHelper = PrayerLocationPickerViewModel()

    let onSaved: () -> Void

    @State private var selectedCityFromPicker = ""
    @State private var manualCity = ""
    @State private var selectedCountryCode = ""
    @State private var method: PrayerCalculationMethod = .ditib
    @State private var cityInputMode: CityInputMode = .manual

    // Coordinate for `selectedCityFromPicker`, set only by CityPickerView's
    // own selection — never guessed from the name.
    @State private var pickerCoordinate: GeoCoordinate?
    // Coordinate for `manualCity`, set only when it currently reflects a
    // live GPS fix (cleared as soon as the text is hand-edited).
    @State private var manualCoordinate: GeoCoordinate?

    @State private var fajrAdjustment = 0
    @State private var shurukAdjustment = 0
    @State private var dhuhrAdjustment = 0
    @State private var asrAdjustment = 0
    @State private var maghribAdjustment = 0
    @State private var ishaAdjustment = 0

    @State private var didLoadInitialValues = false
    @State private var isApplyingCurrentLocation = false
    
    @State private var showClearCacheDialog = false

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

    /// The coordinate for `effectiveCity`, if one is actually confirmed —
    /// from the city list or a live GPS fix. `nil` for hand-typed text, so
    /// the request falls back to the existing address-based endpoint
    /// instead of a guessed coordinate.
    private var effectiveCoordinate: GeoCoordinate? {
        switch cityInputMode {
        case .picker:
            return pickerCoordinate
        case .manual:
            return manualCoordinate
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
                Section("Darstellung") {
                    Toggle("Dunkelmodus", isOn: $appearance.isDarkModeEnabled)
                }

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
                            CityPickerView(selection: $selectedCityFromPicker, selectedCoordinate: $pickerCoordinate)
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
                    
                    Button(role: .destructive) {
                        showClearCacheDialog = true
                    } label: {
                        Label("Gesamten Cache löschen", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.top, 8)
                    .confirmationDialog(
                        "Gesamten Cache löschen?",
                        isPresented: $showClearCacheDialog,
                        titleVisibility: .visible
                    ) {
                        Button("Cache löschen", role: .destructive) {
                            CacheResetService.clearAllCaches()
                        }

                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text("Dadurch werden alle gespeicherten Gebetszeiten- und Kalenderdaten entfernt.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground").ignoresSafeArea())
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

                        let location = effectiveCoordinate.map {
                            PrayerLocation(name: address, coordinate: $0)
                        }

                        viewModel.saveSettings(
                            address: address,
                            location: location,
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

                // Restore whichever coordinate slot matches the mode we
                // just resolved into, so a previously coordinate-confirmed
                // location isn't silently downgraded to address-only.
                if cityInputMode == .picker {
                    pickerCoordinate = viewModel.autoSettings.location?.coordinate
                } else {
                    manualCoordinate = viewModel.autoSettings.location?.coordinate
                }
            }
            .onChange(of: selectedCountryCode) { oldValue, newValue in
                guard oldValue != newValue else { return }

                if !isGermanySelected && cityInputMode == .picker {
                    cityInputMode = .manual
                }

                guard !oldValue.isEmpty, !isApplyingCurrentLocation else { return }

                selectedCityFromPicker = ""
                pickerCoordinate = nil
            }
            .onChange(of: manualCity) { _, _ in
                guard !isApplyingCurrentLocation else { return }
                manualCoordinate = nil
            }
            .onReceive(locationHelper.$detectedPlace) { place in
                guard isApplyingCurrentLocation, let place else { return }

                manualCity = place.city
                manualCoordinate = place.coordinate
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

#Preview("Light") {
    PrayerSettingsView(onSaved: {})
        .environmentObject(AppearanceViewModel())
}

#Preview("Dark") {
    let appearance = AppearanceViewModel()
    appearance.isDarkModeEnabled = true
    return PrayerSettingsView(onSaved: {})
        .environmentObject(appearance)
        .preferredColorScheme(.dark)
}
