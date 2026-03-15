import Foundation

struct SharedPrayerSettingsStore {
    private let defaults = UserDefaults(suiteName: AppGroup.id)
    private let key = "shared_prayer_settings"

    func save(_ settings: PrayerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: key)
    }

    func load() -> PrayerSettings {
        if let data = defaults?.data(forKey: key),
           let settings = try? JSONDecoder().decode(PrayerSettings.self, from: data) {
            return settings
        }

        return PrayerSettings(
            address: "Gelsenkirchen, Germany",
            date: Date(),
            method: PrayerCalculationMethod.diyanet.rawValue
        )
    }
}
