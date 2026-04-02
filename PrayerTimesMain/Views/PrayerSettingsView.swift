import SwiftUI

struct PrayerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AutoPrayerViewModel()

    let onSaved: () -> Void

    @State private var address = ""
    @State private var method: PrayerCalculationMethod = .ditib

    var body: some View {
        NavigationStack {
            Form {
                Section("Automatische Daten") {
                    TextField("Ort", text: $address)

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
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        viewModel.saveSettings(
                            address: address,
                            method: method
                        )

                        onSaved()
                        dismiss()
                    }
                }
            }
            .task {
                viewModel.reloadLocalState()
                address = viewModel.autoSettings.address
                method = viewModel.autoSettings.method
            }
        }
    }
}
