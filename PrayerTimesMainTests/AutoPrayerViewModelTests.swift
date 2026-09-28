import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers "App und Widget verwenden denselben Ort": both read
/// `AutoPrayerSettings` from the same App-Group-backed
/// `SharedPrayerSettingsStore` suite, so saving a confirmed location from
/// the app view model must be visible, byte-for-byte, to any other
/// `SharedPrayerSettingsStore` instance reading that same suite (standing
/// in for the widget process) — plus the location-confirmation flag
/// behavior around `saveSettings`.
@MainActor
struct AutoPrayerViewModelTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// A migrator that never touches the real city list/network and never
    /// changes anything — isolates these tests from migration timing.
    private func noOpMigrator(settingsStore: SharedPrayerSettingsStore, timesStore: SharedPrayerTimesStore) -> LegacyLocationMigrator {
        LegacyLocationMigrator(settingsStore: settingsStore, timesStore: timesStore, loadGermanCities: { [] })
    }

    @Test func savedLocationIsVisibleToAnotherStoreReadingTheSameSuiteLikeTheWidgetWould() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        let viewModel = AutoPrayerViewModel(
            settingsStore: settingsStore,
            timesStore: timesStore,
            legacyMigrator: noOpMigrator(settingsStore: settingsStore, timesStore: timesStore)
        )

        let location = PrayerLocation(name: "Aachen, DE", coordinate: GeoCoordinate(latitude: 50.7755, longitude: 6.0836))

        viewModel.saveSettings(
            address: "Aachen, DE",
            location: location,
            method: .ditib,
            adjustments: .zero
        )

        // A fresh store instance over the same suite stands in for the
        // widget process, which never shares in-memory state with the app.
        let widgetSideStore = SharedPrayerSettingsStore(suiteName: suite)
        let widgetSideSettings = widgetSideStore.loadAutoSettings()

        #expect(widgetSideSettings.location == location)
        #expect(widgetSideSettings.address == "Aachen, DE")
    }

    @Test func savingAConfirmedLocationClearsTheNeedsConfirmationFlag() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)
        settingsStore.setNeedsLocationConfirmation(true)

        let viewModel = AutoPrayerViewModel(
            settingsStore: settingsStore,
            timesStore: timesStore,
            legacyMigrator: noOpMigrator(settingsStore: settingsStore, timesStore: timesStore)
        )

        viewModel.saveSettings(
            address: "Berlin, DE",
            location: PrayerLocation(name: "Berlin, DE", coordinate: GeoCoordinate(latitude: 52.52, longitude: 13.405)),
            method: .ditib,
            adjustments: .zero
        )

        #expect(viewModel.needsLocationConfirmation == false)
        #expect(settingsStore.needsLocationConfirmation() == false)
    }

    @Test func reloadLocalStatePicksUpConfirmationFlagFromStore() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let settingsStore = SharedPrayerSettingsStore(suiteName: suite)
        let timesStore = SharedPrayerTimesStore(suiteName: suite)

        let viewModel = AutoPrayerViewModel(
            settingsStore: settingsStore,
            timesStore: timesStore,
            legacyMigrator: noOpMigrator(settingsStore: settingsStore, timesStore: timesStore)
        )
        #expect(viewModel.needsLocationConfirmation == false)

        // Simulate the flag being set by a migration pass elsewhere.
        settingsStore.setNeedsLocationConfirmation(true)
        viewModel.reloadLocalState()

        #expect(viewModel.needsLocationConfirmation == true)
    }
}
