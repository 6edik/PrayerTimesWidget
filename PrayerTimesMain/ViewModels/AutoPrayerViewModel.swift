import Foundation
import WidgetKit
import Combine

@MainActor
final class AutoPrayerViewModel: ObservableObject {
    @Published var autoSettings: AutoPrayerSettings
    @Published private(set) var todayTimes: PrayerTimes?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    // Set by `LegacyLocationMigrator` when a saved address had no
    // coordinate and couldn't be matched unambiguously against the local
    // city list. Cleared as soon as a real coordinate is confirmed/saved.
    @Published private(set) var needsLocationConfirmation: Bool

    private let settingsStore: SharedPrayerSettingsStore
    private let timesStore: SharedPrayerTimesStore
    private let refreshCoordinator: PrayerRefreshCoordinator
    private let legacyMigrator: LegacyLocationMigrator

    init(
        settingsStore: SharedPrayerSettingsStore? = nil,
        timesStore: SharedPrayerTimesStore? = nil,
        refreshCoordinator: PrayerRefreshCoordinator? = nil,
        legacyMigrator: LegacyLocationMigrator? = nil
    ) {
        let resolvedSettingsStore = settingsStore ?? SharedPrayerSettingsStore()
        let resolvedTimesStore = timesStore ?? SharedPrayerTimesStore()

        self.settingsStore = resolvedSettingsStore
        self.timesStore = resolvedTimesStore
        self.refreshCoordinator = refreshCoordinator ?? PrayerRefreshCoordinator(store: resolvedTimesStore)
        self.legacyMigrator = legacyMigrator ?? LegacyLocationMigrator(
            settingsStore: resolvedSettingsStore,
            timesStore: resolvedTimesStore
        )
        self.autoSettings = resolvedSettingsStore.loadAutoSettings()
        self.needsLocationConfirmation = resolvedSettingsStore.needsLocationConfirmation()

        let rawToday = resolvedTimesStore.load(for: Date(), settings: resolvedSettingsStore.loadAutoSettings())
        self.todayTimes = rawToday?.applyingAdjustments(self.autoSettings.adjustments)

        let migrator = self.legacyMigrator
        Task { [weak self] in
            await migrator.migrateIfNeeded()
            self?.reloadLocalState()
        }
    }

    func reloadLocalState() {
        let latestSettings = settingsStore.loadAutoSettings()
        autoSettings = latestSettings
        needsLocationConfirmation = settingsStore.needsLocationConfirmation()

        let rawToday = timesStore.load(for: Date(), settings: latestSettings)
        todayTimes = rawToday?.applyingAdjustments(latestSettings.adjustments)
    }

    /// - Parameter location: the coordinate confirmed by the city list,
    ///   GPS, or a resolved geocoding result for `address`. The UI is
    ///   expected to require this before allowing "Speichern" — passing
    ///   `nil` here leaves the previous location's cache/coordinate state
    ///   untouched rather than guessing one.
    func saveSettings(
        address: String,
        location: PrayerLocation?,
        method: PrayerCalculationMethod,
        adjustments: PrayerAdjustments,
        lateKerahetOffsetMinutes: Int? = nil,
        sunriseKarahaOffsetMinutes: Int? = nil
    ) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAddress = trimmed.isEmpty ? PrayerLocation.defaultGelsenkirchen.name : trimmed
        let newLocation = trimmed.isEmpty ? PrayerLocation.defaultGelsenkirchen : location

        // Location-key aware, not just a display-name comparison: the
        // bundled city list has 22 duplicate names, so two different
        // places could otherwise look "unchanged" by name alone.
        let oldKey = LocationKey.key(address: autoSettings.address, location: autoSettings.location)
        let newKey = LocationKey.key(address: newAddress, location: newLocation)

        let locationChanged = oldKey != newKey
        let methodChanged = method != autoSettings.method
        let adjustmentsChanged = adjustments != autoSettings.adjustments

        if locationChanged || methodChanged {
            timesStore.clear()
            todayTimes = nil
        } else if adjustmentsChanged {
            let rawToday = timesStore.load(for: Date(), settings: autoSettings)
            todayTimes = rawToday?.applyingAdjustments(adjustments)
        }

        let updated = AutoPrayerSettings(
            address: newAddress,
            location: newLocation,
            method: method,
            adjustments: adjustments,
            lateKerahetOffsetMinutesOverride: lateKerahetOffsetMinutes,
            sunriseKarahaOffsetMinutesOverride: sunriseKarahaOffsetMinutes
        )

        settingsStore.saveAutoSettings(updated)
        autoSettings = updated

        // A freshly saved, coordinate-confirmed location always resolves
        // whatever previously required re-confirmation — never wait for
        // the next migration pass to clear the banner.
        if newLocation?.coordinate.isPlausible == true {
            settingsStore.clearNeedsLocationConfirmation()
            needsLocationConfirmation = false
        }

        // Reload on every save, not just when the adjustments changed: a
        // location/method change invalidates the widget's cache too, and
        // the widget should stop showing the previous location's timeline
        // as soon as possible instead of waiting for its next natural
        // refresh.
        if locationChanged || methodChanged || adjustmentsChanged {
            WidgetCenter.shared.reloadAllTimelines()
        }

        // Location/method/adjustment changes all affect when a
        // notification should fire. If the cache was just cleared above,
        // this correctly schedules nothing until fresh data arrives —
        // never a notification with the old location's/adjustment's time.
        if locationChanged || methodChanged || adjustmentsChanged {
            Task { await NotificationScheduler().reschedule() }
        }
    }

    func refreshTodayFromAPI() async {
        isLoading = true
        errorMessage = nil

        let outcome = await refreshCoordinator.refreshIfNeeded(
            settings: autoSettings,
            source: .manual,
            forceNetwork: true
        )

        let rawToday = timesStore.load(for: Date(), settings: autoSettings)
        todayTimes = rawToday?.applyingAdjustments(autoSettings.adjustments)

        if case .failure(let message) = outcome {
            errorMessage = message
        } else {
            await NotificationScheduler().reschedule()
        }

        isLoading = false
    }
}
