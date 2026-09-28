import Foundation

/// Persists the user's manual dark-mode override, completely independent of
/// `SharedPrayerSettingsStore`/`NotificationSettingsStore` — a UI
/// preference, not prayer/location/notification data. Same App-Group-backed
/// `UserDefaults` convention as the other stores, purely for consistency;
/// nothing outside the main app target reads this key today (the widget
/// intentionally doesn't — see `AppearanceViewModel`'s doc comment).
struct AppearanceSettingsStore {
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "app_dark_mode_enabled_v1"

    init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    /// Absent key defaults to `false` (light) — the app's existing look
    /// before this toggle existed, so installs that never touch the new
    /// switch keep exactly the same appearance as before.
    func isDarkModeEnabled() -> Bool {
        defaults?.bool(forKey: key) ?? false
    }

    func setDarkModeEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: key)
    }
}
