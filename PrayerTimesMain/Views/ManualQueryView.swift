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

    // Coordinate for `selectedCityFromPicker`, set only by CityPickerView's
    // own selection — never guessed from the name.
    @State private var pickerCoordinate: GeoCoordinate?
    // Coordinate for `manualCity`, set only when it currently reflects a
    // live GPS fix (cleared as soon as the text is hand-edited).
    @State private var manualCoordinate: GeoCoordinate?

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

    private var effectiveLocation: PrayerLocation? {
        effectiveCoordinate.map { PrayerLocation(name: effectiveAddress, coordinate: $0) }
    }

    var body: some View {
        NavigationStack {
            AppPageHeader(title: "Gebetszeiten Suche")
                .fontDesign(nil)
            Form {
                Section() {
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
                    
                    HStack{
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
                        .frame(maxWidth: .infinity, alignment: .leading)

                        
                        if let error = locationHelper.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        
                        Button("Zeiten laden") {
                            Task {
                                await viewModel.runQuery(address: effectiveAddress, location: effectiveLocation)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(
                            effectiveCity.isEmpty ||
                            selectedCountryCode.isEmpty ||
                            viewModel.isLoading
                        )
                    }
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

                            HStack{
                                Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(result.displayTimes.hijriDate)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .foregroundStyle(.secondary)

                            HStack{
                                Text(result.method.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(result.displayTimes.timezone)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .foregroundStyle(.secondary)

                            if result.hasAppliedAdjustments {
                                Label("Persönliche Justierung angewendet", systemImage: "slider.horizontal.3")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Divider()

                            row("Fajr", result.displayTimes.fajr)
                            row("Shuruk", result.displayTimes.shuruk)
                            row("Dhuhr", result.displayTimes.dhuhr)
                            row("Asr", result.displayTimes.asr)
                            row("Maghrib", result.displayTimes.maghrib)
                            row("Isha", result.displayTimes.isha)
                        }
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

                        if cityInputMode == .picker {
                            pickerCoordinate = viewModel.query.location?.coordinate
                            manualCoordinate = nil
                        } else {
                            manualCoordinate = viewModel.query.location?.coordinate
                            pickerCoordinate = nil
                        }
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

                // Restore whichever coordinate slot matches the mode we
                // just resolved into, so a previously coordinate-confirmed
                // location isn't silently downgraded to address-only.
                if cityInputMode == .picker {
                    pickerCoordinate = viewModel.query.location?.coordinate
                } else {
                    manualCoordinate = viewModel.query.location?.coordinate
                }
            }
            .onChange(of: selectedCountryCode) { oldValue, newValue in
                guard oldValue != newValue else { return }

                if !isGermanySelected && cityInputMode == .picker {
                    cityInputMode = .manual
                }

                if !oldValue.isEmpty, oldValue != newValue, !isApplyingCurrentLocation {
                    selectedCityFromPicker = ""
                    pickerCoordinate = nil
                }
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
