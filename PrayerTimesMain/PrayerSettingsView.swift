import SwiftUI

struct PrayerSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let store = SharedPrayerSettingsStore()

    @State private var address: String = ""
    @State private var date: Date = Date()
    @State private var method: PrayerCalculationMethod = .diyanet

    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Ort") {
                    TextField("z. B. Gelsenkirchen, Germany", text: $address)
                }

                Section("Datum") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }

                Section("Methode") {
                    Picker("Berechnung", selection: $method) {
                        ForEach(PrayerCalculationMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        let settings = PrayerSettings(
                            address: address,
                            date: date,
                            method: method.rawValue
                        )
                        store.save(settings)
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let settings = store.load()
                address = settings.address
                date = settings.date
                method = PrayerCalculationMethod(rawValue: settings.method) ?? .diyanet
            }
        }
    }
}
