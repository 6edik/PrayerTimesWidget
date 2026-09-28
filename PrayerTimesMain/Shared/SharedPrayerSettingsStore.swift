import Foundation

struct SharedPrayerSettingsStore {
    // Defaults to the real App Group suite for every production call site.
    // Tests can pass a dedicated suite name so they don't read/write the
    // developer's real saved settings.
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "auto_prayer_settings_v1"
    // Set by `LegacyLocationMigrator` whenever a saved address has no
    // coordinate and couldn't be matched unambiguously against the local
    // city list — cleared as soon as a real coordinate is saved. Read by
    // Home to show the non-blocking "Ort erneut bestätigen" banner.
    private let needsConfirmationKey = "auto_prayer_needs_location_confirmation_v1"
    // The exact `address` string `LegacyLocationMigrator` last checked, so
    // it doesn't repeat the same (already-decided) lookup — and the
    // cache-clear that comes with it — on every app start.
    private let lastCheckedLegacyAddressKey = "auto_prayer_last_checked_legacy_address_v1"

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    func loadAutoSettings() -> AutoPrayerSettings {
        guard
            let data = defaults?.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AutoPrayerSettings.self, from: data)
        else {
            // The one true "app default for a never-configured install":
            // address and location assembled together, consistently, from
            // the single verified Gelsenkirchen entry in the project's own
            // DE_cities.json — never independently defaulted (see
            // AutoPrayerSettings.location's doc comment for why that
            // matters).
            return AutoPrayerSettings(
                address: PrayerLocation.defaultGelsenkirchen.name,
                location: PrayerLocation.defaultGelsenkirchen,
                method: .ditib,
                adjustments: .zero
            )
        }
        return decoded
    }

    func saveAutoSettings(_ settings: AutoPrayerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: key)
    }

    func loadPrayerSettings(for date: Date = Date()) -> PrayerSettings {
        loadAutoSettings().asPrayerSettings(for: date)
    }

    func loadAdjustments() -> PrayerAdjustments {
        loadAutoSettings().adjustments
    }

    func saveAdjustments(_ adjustments: PrayerAdjustments) {
        var settings = loadAutoSettings()
        settings.adjustments = adjustments
        saveAutoSettings(settings)
    }

    func needsLocationConfirmation() -> Bool {
        defaults?.bool(forKey: needsConfirmationKey) ?? false
    }

    func setNeedsLocationConfirmation(_ value: Bool) {
        defaults?.set(value, forKey: needsConfirmationKey)
    }

    func clearNeedsLocationConfirmation() {
        defaults?.set(false, forKey: needsConfirmationKey)
    }

    func lastCheckedLegacyAddress() -> String? {
        defaults?.string(forKey: lastCheckedLegacyAddressKey)
    }

    func setLastCheckedLegacyAddress(_ address: String) {
        defaults?.set(address, forKey: lastCheckedLegacyAddressKey)
    }
}
