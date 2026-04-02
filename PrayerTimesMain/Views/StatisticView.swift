import SwiftUI

struct StatisticsView: View {
    private let statsStore = RefreshStatsStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let prayerStore = SharedPrayerTimesStore()

    @State private var stats = RefreshStats.empty
    @State private var settings = PrayerSettings(
        address: "--",
        date: Date(),
        method: PrayerCalculationMethod.ditib
    )

    @State private var autoSettings = AutoPrayerSettings(
        address: "--",
        method: .ditib
    )

    @State private var cacheRange = "--"
    @State private var cacheDayCount = 0
    @State private var cacheFetchedAt: Date?
    @State private var remainingCoverageDays: Int?

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

                Section("Cache") {
                    statRow("Zeitraum", cacheRange)
                    statRow("Gespeicherte Tage", "\(cacheDayCount)")
                    statRow("Letzter Cache-Fetch", formatted(cacheFetchedAt))
                    statRow("Resttage ab heute", remainingCoverageText())
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
                    statRow("Methode", settings.method.title)
                }

                Section("Hinweis") {
                    Text("Sobald nur noch 2 Tage Abdeckung übrig sind, sollte die App den Wochen-Cache erneut laden.")
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

    private func remainingCoverageText() -> String {
        guard let remainingCoverageDays else { return "--" }

        switch remainingCoverageDays {
        case ..<0:
            return "Abgelaufen"
        case 0:
            return "Heute letzter Tag"
        case 1:
            return "1 Tag"
        default:
            return "\(remainingCoverageDays) Tage"
        }
    }

    private func reload() {
        let latestAutoSettings = settingsStore.loadAutoSettings()

        stats = statsStore.load()
        autoSettings = latestAutoSettings
        settings = latestAutoSettings.asPrayerSettings(for: Date())

        cacheRange = prayerStore.cacheRangeText(settings: latestAutoSettings)
        cacheDayCount = prayerStore.cacheDayCount(settings: latestAutoSettings)
        cacheFetchedAt = prayerStore.cacheFetchedAt(settings: latestAutoSettings)
        remainingCoverageDays = prayerStore.remainingCoverageDays(
            from: Date(),
            settings: latestAutoSettings
        )
    }
}

#Preview {
    StatisticsView()
}
