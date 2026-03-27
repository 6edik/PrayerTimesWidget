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
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
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
                Text("﷽")
                    .font(.system(size: 34, weight: .ultraLight, design: .serif))
                    .frame(height: 30)

                HStack(spacing: 8) {
                    Text(prayerTimes.readableDate)
                    Text("•")
                    Text(prayerTimes.hijriDate)
                }
                .font(.subheadline)

                if prayerTimes.hijriDay != "--" {
                    Text(prayerTimes.hijriDay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        await loadPrayerTimes(source: .manual)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Gebetszeiten")
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
                            await loadPrayerTimes(source: .manual)
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
                    await loadPrayerTimesIfNeeded()
                }
            }
        }
    }

    @MainActor
    private func loadPrayerTimes(source: RefreshSource) async {
        isLoading = true
        errorMessage = nil

        let settings = settingsStore.load()
        currentAddress = settings.address
        currentMethod = PrayerCalculationMethod(rawValue: settings.method)?.title ?? "Unbekannt"

        statsStore.markAttempt(source: source)

        do {
            let times = try await service.fetchPrayerTimes(settings: settings)
            prayerTimes = times
            store.save(times)
            saveLastRefreshDate()

            statsStore.markSuccess(source: source)
            statsStore.incrementWidgetReloadCount()

            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
        } catch {
            errorMessage = "API konnte nicht geladen werden."
            statsStore.markFailure(source: source, error: error.localizedDescription)
        }

        isLoading = false
    }

    @MainActor
    private func loadPrayerTimesIfNeeded() async {
        let lastRefresh = UserDefaults(suiteName: AppGroup.id)?.object(forKey: "last_refresh") as? Date
        let shouldRefresh = lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) > 15 * 60

        if shouldRefresh {
            await loadPrayerTimes(source: .appActive)
        }
    }

    private func saveLastRefreshDate() {
        UserDefaults(suiteName: AppGroup.id)?.set(Date(), forKey: "last_refresh")
    }
}

#Preview {
    ContentView()
}
