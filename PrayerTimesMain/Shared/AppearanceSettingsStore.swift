import Foundation

/// Three-way appearance choice, replacing the earlier plain dark-mode
/// toggle. `.system` means "follow whatever iOS is currently set to,
/// including later system changes"; `.light`/`.dark` force that scheme
/// regardless of the system setting.
enum AppAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
}

/// Persists the user's appearance choice, completely independent of
/// `SharedPrayerSettingsStore`/`NotificationSettingsStore` — a UI
/// preference, not prayer/location/notification data. Same App-Group-backed
/// `UserDefaults` convention as the other stores, purely for consistency;
/// nothing outside the main app target reads this key today (the widget
/// intentionally doesn't — see `AppearanceViewModel`'s doc comment).
struct AppearanceSettingsStore {
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    private let modeKey = "app_appearance_mode_v1"
    // The single Bool this feature used before the System/Hell/Dunkel
    // picker existed. Checked once, on first access after the upgrade, so
    // an existing choice is migrated instead of silently reset to System.
    private let legacyDarkModeKey = "app_dark_mode_enabled_v1"

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    /// Absent everything (a genuinely fresh install, or one that never
    /// touched the setting) resolves to `.system` — the modern default for
    /// this picker. A legacy Bool from before this picker existed is
    /// migrated exactly once: `true` -> `.dark`, `false` -> `.light`, then
    /// persisted under the new key with the legacy key removed, so this
    /// migration path is only ever taken a single time per install.
    func appearanceMode() -> AppAppearance {
        if let raw = defaults?.string(forKey: modeKey), let mode = AppAppearance(rawValue: raw) {
            return mode
        }

        if let legacyEnabled = defaults?.object(forKey: legacyDarkModeKey) as? Bool {
            let migrated: AppAppearance = legacyEnabled ? .dark : .light
            setAppearanceMode(migrated)
            defaults?.removeObject(forKey: legacyDarkModeKey)
            return migrated
        }

        return .system
    }

    func setAppearanceMode(_ mode: AppAppearance) {
        defaults?.set(mode.rawValue, forKey: modeKey)
    }
}
