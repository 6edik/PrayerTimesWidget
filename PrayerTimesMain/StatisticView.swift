import SwiftUI

struct StatisticsView: View {
    private let statsStore = RefreshStatsStore()
    private let settingsStore = SharedPrayerSettingsStore()

    @State private var stats = RefreshStats.empty
    @State private var settings = PrayerSettings(
        address: "--",
        date: Date(),
        method: PrayerCalculationMethod.diyanet.rawValue
    )

    var body: some View {
        NavigationStack {
            Form {
                Section("Aktualisierung") {
                    statRow("Letzter Versuch", formatted(stats.lastAttemptAt))
                    statRow("Letzter Erfolg", formatted(stats.lastSuccessAt))
                    statRow("Letzter Fehler", formatted(stats.lastFailureAt))
                    statRow("Nächste Planung", formatted(stats.nextPlannedRefreshAt))
                    statRow("Letzte Quelle", stats.lastSource ?? "--")
                    statRow("Letzter Fehlertext", stats.lastError ?? "--")
                }

                Section("Quellen-Zähler") {
                    statRow("Appstart", "\(stats.appStartRefreshCount)")
                    statRow("Manuell", "\(stats.manualRefreshCount)")
                    statRow("Hintergrund", "\(stats.backgroundRefreshCount)")
                    statRow("App Active", "\(stats.appActiveRefreshCount)")
                    statRow("Widget Timeline", "\(stats.widgetTimelineRefreshCount)")
                }

                Section("Gesamtzähler") {
                    statRow("Erfolgreiche Abrufe", "\(stats.successfulFetchCount)")
                    statRow("Fehlgeschlagene Abrufe", "\(stats.failedFetchCount)")
                    statRow("Widget Reloads", "\(stats.widgetReloadCount)")
                    statRow("Timeline Builds", "\(stats.timelineBuildCount)")
                }

                Section("Aktuelle Einstellungen") {
                    statRow("Ort", settings.address)
                    statRow("Datum", formatted(settings.date))
                    statRow(
                        "Methode",
                        PrayerCalculationMethod(rawValue: settings.method)?.title ?? "Unbekannt"
                    )
                }

                Section("Hinweis") {
                    Text("Background-Refresh und Widget-Updates werden von iOS geplant und nicht sekundengenau garantiert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Statistik")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aktualisieren") {
                        reload()
                    }
                }
            }
            .task {
                reload()
            }
        }
    }

    @ViewBuilder
    private func statRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "--" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func reload() {
        stats = statsStore.load()
        settings = settingsStore.load()
    }
}

#Preview {
    StatisticsView()
}
