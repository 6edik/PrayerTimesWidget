import Foundation

struct SharedPrayerSettingsStore {
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.id)
    }

    private let key = "prayer_settings"

    func load() -> PrayerSettings {
        guard
            let data = defaults?.data(forKey: key),
            let settings = try? JSONDecoder().decode(PrayerSettings.self, from: data)
        else {
            return PrayerSettings(
                address: "Gelsenkirchen, Germany",
                date: Date(),
                method: PrayerCalculationMethod.diyanet.rawValue
            )
        }
        return settings
    }

    func save(_ settings: PrayerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: key)
    }
}
