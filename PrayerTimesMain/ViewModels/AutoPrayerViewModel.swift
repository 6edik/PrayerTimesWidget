import Foundation
import WidgetKit
import Combine

@MainActor
final class AutoPrayerViewModel: ObservableObject {
    @Published var autoSettings: AutoPrayerSettings
    @Published private(set) var todayTimes: PrayerTimes?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let settingsStore: SharedPrayerSettingsStore
    private let timesStore: SharedPrayerTimesStore
    private let service: PrayerTimesService

    init(
        settingsStore: SharedPrayerSettingsStore? = nil,
        timesStore: SharedPrayerTimesStore? = nil,
        service: PrayerTimesService? = nil
    ) {
        let resolvedSettingsStore = settingsStore ?? SharedPrayerSettingsStore()
        let resolvedTimesStore = timesStore ?? SharedPrayerTimesStore()
        let resolvedService = service ?? PrayerTimesService()

        self.settingsStore = resolvedSettingsStore
        self.timesStore = resolvedTimesStore
        self.service = resolvedService
        self.autoSettings = resolvedSettingsStore.loadAutoSettings()
        self.todayTimes = resolvedTimesStore.load(for: Date(), settings: resolvedSettingsStore.loadAutoSettings())
    }

    func reloadLocalState() {
        let latestSettings = settingsStore.loadAutoSettings()
        autoSettings = latestSettings
        todayTimes = timesStore.load(for: Date(), settings: latestSettings)
    }

    func saveSettings(address: String, method: PrayerCalculationMethod) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAddress = "Gelsenkirchen, DE"
        let newAddress = trimmed.isEmpty ? fallbackAddress : trimmed

        let oldNormalizedAddress = autoSettings.address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let newNormalizedAddress = newAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let addressChanged = oldNormalizedAddress != newNormalizedAddress
        let methodChanged = method != autoSettings.method

        if addressChanged || methodChanged {
            timesStore.clear()
            todayTimes = nil
        }

        let updated = AutoPrayerSettings(
            address: newAddress,
            method: method
        )

        settingsStore.saveAutoSettings(updated)
        autoSettings = updated
    }

    func refreshTodayFromAPI() async {
        isLoading = true
        errorMessage = nil

        do {
            let settings = settingsStore.loadPrayerSettings(for: Date())
            let fetchStart = PrayerCachePolicy.fetchStart(from: settings.date)

            let cache = try await service.fetchPrayerTimesCache(
                settings: settings,
                referenceDate: fetchStart,
                coverageDays: PrayerCachePolicy.totalDays
            )

            timesStore.replaceCache(with: cache)
            todayTimes = timesStore.load(for: Date(), settings: autoSettings)

            UserDefaults(suiteName: AppGroup.id)?.set(Date(), forKey: "last_refresh")
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
