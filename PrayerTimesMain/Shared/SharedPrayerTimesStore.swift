import Foundation

struct SharedPrayerTimesStore {
    private let defaults = UserDefaults(suiteName: AppGroup.id)
    private let key = "shared_prayer_times"

    func save(_ times: PrayerTimes) {
        guard let data = try? JSONEncoder().encode(times) else { return }
        defaults?.set(data, forKey: key)
    }

    func load() -> PrayerTimes? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PrayerTimes.self, from: data)
    }
}
