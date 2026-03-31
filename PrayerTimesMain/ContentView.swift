import SwiftUI
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let service = PrayerTimesService()
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let statsStore = RefreshStatsStore()

    @State private var prayerTimes = PrayerTimes(
        fajr: "--:--",
        shuruk: "--:--",
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
        readableDay: "--",
        hijriDate: "--",
        hijriDay: "--",
        timezone: "--"
    )

    @State private var currentAddress = "--"
    @State private var currentMethod = "--"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeSheet: ActiveSheet?
    @State private var hasLoadedInitially = false

    enum ActiveSheet: Identifiable {
        case settings
        case statistics

        var id: Int {
            switch self {
            case .settings: return 1
            case .statistics: return 2
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Gebetszeiten")
                    .font(.system(size: 34, weight: .ultraLight, design: .serif))
                    .frame(height: 30)

                HStack(spacing: 8) {
                    Text(prayerTimes.readableDate)
                    Text("•")
                    Text(prayerTimes.hijriDate)
                }
                .font(.subheadline)

                HStack(spacing: 8){
                    if prayerTimes.readableDay != "--" {
                        Text(prayerTimes.readableDay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if prayerTimes.hijriDay != "--" {
                        Text(prayerTimes.hijriDay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(prayerTimes.timezone)
                    .foregroundStyle(.secondary)

                Text(currentAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(currentMethod)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(PrayerTimesMapper.rows(from: prayerTimes)) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(row.time)
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if isLoading {
                    ProgressView()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Neu laden") {
                    Task {
                        await loadPrayerTimes(source: .manual, forceNetwork: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Stats") {
                        activeSheet = .statistics
                    }

                    Button("Settings") {
                        activeSheet = .settings
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    PrayerSettingsView {
                        Task {
                            await loadPrayerTimes(source: .manual, forceNetwork: true)
                        }
                    }

                case .statistics:
                    StatisticsView()
                }
            }
        }
        .task {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            await loadPrayerTimes(source: .appStart)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, hasLoadedInitially {
                Task {
                    await loadPrayerTimes(source: .appActive)
                }
            }
        }
    }

    @MainActor
    private func loadPrayerTimes(
        source: RefreshSource,
        forceNetwork: Bool = false
    ) async {
        let settings = settingsStore.load()
        currentAddress = settings.address
        currentMethod = PrayerCalculationMethod(rawValue: settings.method)?.title ?? "Unbekannt"

        if let cachedToday = store.load(for: Date()) {
            prayerTimes = cachedToday
        }

        let shouldFetch =
            forceNetwork ||
            !store.hasToday(for: settings, referenceDate: Date()) ||
            store.needsRefresh(settings: settings, referenceDate: Date(), refreshThresholdDays: 2)

        guard shouldFetch else {
            errorMessage = nil
            statsStore.setNextPlannedRefresh(
                store.suggestedRefreshDate(settings: settings, refreshThresholdDays: 2)
            )
            return
        }

        isLoading = true
        errorMessage = nil
        statsStore.markAttempt(source: source)

        do {
            let cache = try await service.fetchPrayerTimesCache(
                settings: settings,
                referenceDate: Date(),
                coverageDays: 7
            )

            store.saveCache(cache)

            if let today = store.load(for: Date()) {
                prayerTimes = today
            }

            saveLastRefreshDate()
            statsStore.markSuccess(source: source)
            statsStore.incrementWidgetReloadCount()
            statsStore.setNextPlannedRefresh(
                store.suggestedRefreshDate(settings: settings, refreshThresholdDays: 2)
            )

            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
        } catch {
            if let cachedToday = store.load(for: Date()) {
                prayerTimes = cachedToday
                errorMessage = "Keine Verbindung – lokale Daten werden verwendet."
            } else {
                errorMessage = "API konnte nicht geladen werden."
            }

            statsStore.markFailure(source: source, error: error.localizedDescription)
        }

        isLoading = false
    }

    private func saveLastRefreshDate() {
        UserDefaults(suiteName: AppGroup.id)?.set(Date(), forKey: "last_refresh")
    }
}

#Preview {
    ContentView()
}
