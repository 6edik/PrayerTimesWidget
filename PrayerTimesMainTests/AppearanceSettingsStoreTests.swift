import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers Block 2 (Erscheinungsbild): migrating the old dark-mode Bool into
/// the new System/Hell/Dunkel picker, and the fresh-install default.
@MainActor
struct AppearanceSettingsStoreTests {

    private func makeSuite() -> (name: String, defaults: UserDefaults) {
        let name = "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    @Test func freshInstallWithNoKeyAtAllDefaultsToSystem() async throws {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        let store = AppearanceSettingsStore(suiteName: suite.name)
        #expect(store.appearanceMode() == .system)
    }

    @Test func legacyTrueMigratesToDarkAndRemovesLegacyKey() async throws {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        suite.defaults.set(true, forKey: "app_dark_mode_enabled_v1")

        let store = AppearanceSettingsStore(suiteName: suite.name)
        #expect(store.appearanceMode() == .dark)
        #expect(suite.defaults.object(forKey: "app_dark_mode_enabled_v1") == nil)
        #expect(suite.defaults.string(forKey: "app_appearance_mode_v1") == "dark")
    }

    @Test func legacyFalseMigratesToLightAndRemovesLegacyKey() async throws {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        suite.defaults.set(false, forKey: "app_dark_mode_enabled_v1")

        let store = AppearanceSettingsStore(suiteName: suite.name)
        #expect(store.appearanceMode() == .light)
        #expect(suite.defaults.object(forKey: "app_dark_mode_enabled_v1") == nil)
        #expect(suite.defaults.string(forKey: "app_appearance_mode_v1") == "light")
    }

    @Test func newFormatRoundTrips() async throws {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        let store = AppearanceSettingsStore(suiteName: suite.name)
        store.setAppearanceMode(.dark)
        #expect(store.appearanceMode() == .dark)

        store.setAppearanceMode(.system)
        #expect(store.appearanceMode() == .system)
    }

    @Test func newKeyTakesPrecedenceOverAnyLeftoverLegacyKey() async throws {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        // Simulates an already-migrated install where the legacy key
        // somehow still lingers — the new key must win, never re-migrate.
        suite.defaults.set(true, forKey: "app_dark_mode_enabled_v1")
        suite.defaults.set("light", forKey: "app_appearance_mode_v1")

        let store = AppearanceSettingsStore(suiteName: suite.name)
        #expect(store.appearanceMode() == .light)
    }
}
