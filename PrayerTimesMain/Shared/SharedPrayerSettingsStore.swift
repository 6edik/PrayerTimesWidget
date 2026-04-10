import Foundation

struct SharedPrayerSettingsStore {
    // Defaults to the real App Group suite for every production call site.
    // Tests can pass a dedicated suite name so they don't read/write the
    // developer's real saved settings.
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "auto_prayer_settings_v1"

    init(suiteName: String = AppGroup.id) {
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
}
