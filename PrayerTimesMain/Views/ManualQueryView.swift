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
    // own selection — never guessed from the name. Always a confirmed city.
    @State private var pickerCoordinate: GeoCoordinate?
    // Coordinate for `manualCity`, set only by a live GPS fix or an
    // explicitly confirmed geocoding result — cleared as soon as the text
    // is hand-edited, so a stale coordinate never gets attached to a
    // different place.
    @State private var manualCoordinate: GeoCoordinate?
    @State private var manualCoordinateSource: LocationSource = .confirmedPlace

    private let placeResolver: PlaceResolving = PlaceGeocodingResolver()
    @State private var placeResolutionState: PlaceResolutionState = .idle
    @State private var candidatesForDisambiguation: [GeocodedPlaceCandidate] = []
    @State private var showCandidateSheet = false

    @State private var isApplyingCurrentLocation = false
    @State private var didLoadInitialValues = false

    /// The TextField's actual binding: clearing the coordinate on edit is
    /// wired here — directly into the one place a person can hand-type
    /// `manualCity` — instead of an `.onChange(of: manualCity)` modifier.
    /// `.onChange` fires once per SwiftUI update pass using the state as
    /// it stands *after* the whole enclosing closure (e.g. `onAppear`'s or
    /// the "Auto-Werte" button's bulk restore) has already finished, so a
    /// timing flag reset at the end of that same closure is already back
    /// to its resting value by the time `.onChange` would run — it can't
    /// reliably distinguish "the text just got restored" from "the person
    /// edited it". Routing the clear through this binding instead means
    /// only an actual keystroke (through this exact `Binding`) ever
    /// triggers it; every restore path sets the plain `@State` directly
    /// and never touches this setter at all.
    private var manualCityBinding: Binding<String> {
        Binding(
            get: { manualCity },
            set: { newValue in
                manualCity = newValue
                manualCoordinate = nil
                manualCoordinateSource = .confirmedPlace
                placeResolutionState = .idle
                candidatesForDisambiguation = []
            }
        )
    }

    /// Same reasoning as `manualCityBinding`, for the country picker: only
    /// an actual selection through `CountryPickerView` (the sole UI control
    /// that mutates this) clears the previously-confirmed coordinate.
    /// Restore paths set `selectedCountryCode` directly and bypass this.
    private var countryCodeBinding: Binding<String> {
        Binding(
            get: { selectedCountryCode },
            set: { newValue in
                let oldValue = selectedCountryCode
                selectedCountryCode = newValue
                guard oldValue != newValue else { return }

                if !isGermanySelected && cityInputMode == .picker {
                    cityInputMode = .manual
                }

                guard !oldValue.isEmpty, !isApplyingCurrentLocation else { return }

                selectedCityFromPicker = ""
                pickerCoordinate = nil
                manualCoordinate = nil
                manualCoordinateSource = .confirmedPlace
                placeResolutionState = .idle
                candidatesForDisambiguation = []
            }
        )
    }

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
    /// from the city list, a live GPS fix, or an explicitly confirmed
    /// geocoding result. `nil` for hand-typed text that hasn't been
    /// resolved yet, so running the query stays disabled instead of falling
    /// back to a guessed coordinate.
    private var effectiveCoordinate: GeoCoordinate? {
        switch cityInputMode {
        case .picker:
            return pickerCoordinate
        case .manual:
            return manualCoordinate
        }
    }

    private var effectiveSource: LocationSource {
        switch cityInputMode {
        case .picker:
            return .confirmedPlace
        case .manual:
            return manualCoordinateSource
        }
    }

    private var effectiveLocation: PrayerLocation? {
        effectiveCoordinate.map { PrayerLocation(name: effectiveAddress, coordinate: $0, source: effectiveSource) }
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
                        CountryPickerView(selection: countryCodeBinding)
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
                        TextField("Stadt manuell eingeben", text: manualCityBinding)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    
                    Picker("Stadt-Eingabe", selection: $cityInputMode) {
                        ForEach(availableCityInputModes) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if cityInputMode == .manual,
                       manualCoordinate == nil,
                       !effectiveCity.isEmpty,
                       !selectedCountryCode.isEmpty {
                        Button {
                            Task { await resolvePlace() }
                        } label: {
                            if placeResolutionState == .resolving {
                                ProgressView()
                            } else {
                                Label("Ort bestätigen", systemImage: "checkmark.circle")
                            }
                        }
                        .disabled(placeResolutionState == .resolving)
                    }

                    if case .failed(let message) = placeResolutionState {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let coordinate = effectiveCoordinate {
                        Text(LocationDisplayFormatter.line(
                            for: PrayerLocation(name: effectiveCity, coordinate: coordinate, source: effectiveSource)
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    
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
                            effectiveCoordinate == nil ||
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
                            row(
                                PrayerDisplayNaming.dhuhrLabel(date: result.date, timezoneIdentifier: result.displayTimes.timezone),
                                result.displayTimes.dhuhr
                            )
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
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground").ignoresSafeArea())
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

                        placeResolutionState = .idle
                        candidatesForDisambiguation = []

                        if cityInputMode == .picker {
                            pickerCoordinate = viewModel.query.location?.coordinate
                            manualCoordinate = nil
                        } else {
                            manualCoordinate = viewModel.query.location?.coordinate
                            manualCoordinateSource = viewModel.query.location?.source ?? .confirmedPlace
                            pickerCoordinate = nil
                        }
                    } label: {
                        Label("Auto-Werte", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .sheet(isPresented: $showCandidateSheet) {
                PlaceCandidatePickerSheet(candidates: candidatesForDisambiguation) { candidate in
                    manualCoordinate = candidate.coordinate
                    manualCoordinateSource = .confirmedPlace
                    placeResolutionState = .idle
                    showCandidateSheet = false
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
                    manualCoordinateSource = viewModel.query.location?.source ?? .confirmedPlace
                }
            }
            .onReceive(locationHelper.$detectedPlace) { place in
                guard isApplyingCurrentLocation, let place else { return }

                manualCity = place.city
                manualCoordinate = place.coordinate
                manualCoordinateSource = .currentLocation
                placeResolutionState = .idle
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

    @MainActor
    private func resolvePlace() async {
        placeResolutionState = .resolving
        let city = effectiveCity
        let countryName = countryNameOnly(for: selectedCountryCode) ?? ""

        let outcome = await placeResolver.resolve(city: city, countryCode: selectedCountryCode, countryName: countryName)

        switch outcome {
        case .resolved(let candidate):
            manualCoordinate = candidate.coordinate
            manualCoordinateSource = .confirmedPlace
            placeResolutionState = .idle
        case .multipleCandidates(let candidates):
            candidatesForDisambiguation = candidates
            showCandidateSheet = true
            placeResolutionState = .idle
        case .countryMismatch:
            placeResolutionState = .failed("Für „\(city)“ wurde kein Treffer in \(countryName.isEmpty ? selectedCountryCode : countryName) gefunden. Der Ort scheint in einem anderen Land zu liegen.")
        case .notFound:
            placeResolutionState = .failed("Ort konnte nicht gefunden werden. Bitte Angaben prüfen oder Stadt aus der Liste wählen.")
        case .failed(let message):
            placeResolutionState = .failed(message)
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
