import Foundation

struct SharedPrayerSettingsStore {
    private let defaults = UserDefaults(suiteName: AppGroup.id)
    private let key = "auto_prayer_settings_v1"

    func loadAutoSettings() -> AutoPrayerSettings {
        guard
            let data = defaults?.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AutoPrayerSettings.self, from: data)
        else {
            return AutoPrayerSettings()
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
}
