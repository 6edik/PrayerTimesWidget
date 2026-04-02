import SwiftUI

struct ManualQueryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManualPrayerViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Manuelle Abfrage") {
                    TextField("Ort", text: $viewModel.query.address)

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
                            await viewModel.runQuery()
                        }
                    }

                    Button("Auto-Werte übernehmen") {
                        viewModel.resetToAutoDefaults()
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
            .navigationTitle("Manuelle Abfrage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
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
}
