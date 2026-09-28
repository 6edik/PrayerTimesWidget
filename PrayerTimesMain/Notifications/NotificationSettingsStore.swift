import Foundation

/// Persists notification preferences completely separately from the
/// prayer-times cache (`SharedPrayerTimesStore`) and from `AutoPrayerSettings`
/// — a notification-type change (sound, reminder lead time, which holiday is
/// selected) never touches, invalidates, or re-fetches prayer data.
struct NotificationSettingsStore {
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "notification_settings_v1"

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    func load() -> NotificationSettings {
        guard
            let data = defaults?.data(forKey: key),
            let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data)
        else {
            return .zero
        }
        return decoded
    }

    func save(_ settings: NotificationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: key)
    }
}
