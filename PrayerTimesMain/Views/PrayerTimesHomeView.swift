import SwiftUI

struct PrayerTimesHomeView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let refreshCoordinator = PrayerRefreshCoordinator()
    private let legacyMigrator = LegacyLocationMigrator()

    private static let placeholderTimes = PrayerTimes(
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
        timezone: "--",
    )

    @State private var prayerTimes = PrayerTimesHomeView.placeholderTimes

    @State private var currentAddress = "--"
    @State private var currentLocation: PrayerLocation?
    @State private var currentMethod = "--"
    @State private var needsLocationConfirmation = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeSheet: ActiveSheet?
    @State private var hasLoadedInitially = false

    enum ActiveSheet: Identifiable {
        case settings
        case statistics
        case manualQuery
        case notifications
        case savedPrayerTimes

        var id: Int {
            switch self {
            case .settings: return 1
            case .statistics: return 2
            case .manualQuery: return 3
            case .notifications: return 4
            case .savedPrayerTimes: return 5
            }
        }
    }

    var body: some View {
        NavigationStack {
            AppPageContainer {
                AppPageHeader(title: "Gebetszeiten")

                HStack(spacing: 8) {
                    Text(prayerTimes.readableDate)
                    Text("•")
                    // Computed locally via Umm-al-Qura instead of the
                    // AlAdhan API's own Hijri string, so this always agrees
                    // with the Islamic-calendar tab and the widget.
                    Text(HijriDateFormatting.displayText(for: Date()))
                }
                .font(.subheadline)

                HStack(spacing: 8) {
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

                if let currentLocation, currentLocation.coordinate.isPlausible {
                    Text(LocationDisplayFormatter.line(for: currentLocation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if needsLocationConfirmation {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Ort erneut bestätigen", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

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
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.06),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
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
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TopBarActionButton(systemImage: "tray.full", accessibilityLabel: "Gespeicherte Gebetszeiten") {
                        activeSheet = .savedPrayerTimes
                    }

                    TopBarActionButton(systemImage: "chart.bar", accessibilityLabel: "Statistiken") {
                        activeSheet = .statistics
                    }

                    TopBarActionButton(systemImage: "magnifyingglass", accessibilityLabel: "Manuelle Suche") {
                        activeSheet = .manualQuery
                    }

                    TopBarActionButton(systemImage: "bell", accessibilityLabel: "Benachrichtigungen") {
                        activeSheet = .notifications
                    }

                    TopBarActionButton(systemImage: "gearshape", accessibilityLabel: "Einstellungen") {
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
                case .manualQuery:
                    ManualQueryView()
                case .notifications:
                    NotificationSettingsView()
                case .savedPrayerTimes:
                    CachedPrayerTimesView()
                }
            }
        }
        .task {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            await legacyMigrator.migrateIfNeeded()
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
        let autoSettings = settingsStore.loadAutoSettings()

        currentAddress = autoSettings.address
        currentLocation = autoSettings.location
        currentMethod = autoSettings.method.title
        needsLocationConfirmation = settingsStore.needsLocationConfirmation()

        // Show whatever is cached for the *current* settings right away.
        // If there is nothing cached for them (e.g. right after switching
        // address/method, especially offline), fall back to the placeholder
        // instead of leaving the previous location's times on screen under
        // the new address label.
        applyCachedTimes(autoSettings: autoSettings)

        // Without a confirmed coordinate there is nothing to fetch — never
        // fall back to an address-based request. The banner above already
        // tells the user to re-confirm the place.
        guard autoSettings.location?.coordinate.isPlausible == true else {
            errorMessage = nil
            return
        }

        let shouldFetch = forceNetwork || refreshCoordinator.needsRefresh(settings: autoSettings)

        guard shouldFetch else {
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        let outcome = await refreshCoordinator.refreshIfNeeded(
            settings: autoSettings,
            source: source,
            forceNetwork: forceNetwork
        )

        switch outcome {
        case .success:
            applyCachedTimes(autoSettings: autoSettings)
            errorMessage = nil
            await NotificationScheduler().reschedule()
        case .failure(let message):
            applyCachedTimes(autoSettings: autoSettings)
            errorMessage = message
        case .skipped, .alreadyInProgressElsewhere:
            applyCachedTimes(autoSettings: autoSettings)
            errorMessage = nil
        }

        isLoading = false
    }

    @MainActor
    private func applyCachedTimes(autoSettings: AutoPrayerSettings) {
        if let cachedRawToday = store.load(for: Date(), settings: autoSettings) {
            prayerTimes = cachedRawToday.applyingAdjustments(autoSettings.adjustments)
        } else {
            prayerTimes = Self.placeholderTimes
        }
    }
}
