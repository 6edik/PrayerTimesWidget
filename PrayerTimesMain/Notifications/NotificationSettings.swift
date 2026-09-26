import Foundation

/// The five prayers a notification can be scheduled for. Shuruk (sunrise)
/// is intentionally excluded — it isn't a prayer.
enum PrayerNotificationKind: String, CaseIterable, Codable, Identifiable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: return "Fajr"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }
}

enum NotificationSoundOption: String, Codable, CaseIterable, Identifiable {
    case silent
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silent: return "Lautlos"
        case .standard: return "Mit Ton"
        }
    }
}

/// How long before the prayer's own start time an additional reminder
/// should fire. `.none` means only the at-start notification is used.
enum ReminderLeadTime: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var title: String {
        self == .none ? "Keine zusätzliche Erinnerung" : "\(rawValue) Minuten vorher"
    }
}

struct PrayerNotificationSetting: Codable, Equatable {
    var isEnabled: Bool = false
    var reminderLeadTime: ReminderLeadTime = .none
    var sound: NotificationSoundOption = .standard
}

struct HolidayNotificationSetting: Codable, Equatable {
    var isEnabled: Bool = false
    var notifyDayBefore: Bool = false
    var notifyOnDay: Bool = true
    var hour: Int = 9
    var minute: Int = 0

    var isConfigurationUseless: Bool {
        !notifyDayBefore && !notifyOnDay
    }
}

struct NotificationSettings: Codable, Equatable {
    var fajr = PrayerNotificationSetting()
    var dhuhr = PrayerNotificationSetting()
    var asr = PrayerNotificationSetting()
    var maghrib = PrayerNotificationSetting()
    var isha = PrayerNotificationSetting()

    // Keyed by `MajorIslamicHoliday.rawValue`. Absent entries behave like
    // `HolidayNotificationSetting()` (disabled).
    var holidays: [String: HolidayNotificationSetting] = [:]

    static let zero = NotificationSettings()

    func setting(for kind: PrayerNotificationKind) -> PrayerNotificationSetting {
        switch kind {
        case .fajr: return fajr
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }

    mutating func setSetting(_ setting: PrayerNotificationSetting, for kind: PrayerNotificationKind) {
        switch kind {
        case .fajr: fajr = setting
        case .dhuhr: dhuhr = setting
        case .asr: asr = setting
        case .maghrib: maghrib = setting
        case .isha: isha = setting
        }
    }

    func setting(for holiday: MajorIslamicHoliday) -> HolidayNotificationSetting {
        holidays[holiday.rawValue] ?? HolidayNotificationSetting()
    }

    mutating func setSetting(_ setting: HolidayNotificationSetting, for holiday: MajorIslamicHoliday) {
        holidays[holiday.rawValue] = setting
    }

    var hasAnyPrayerEnabled: Bool {
        PrayerNotificationKind.allCases.contains { setting(for: $0).isEnabled }
    }

    var hasAnyHolidayEnabled: Bool {
        MajorIslamicHoliday.allCases.contains { setting(for: $0).isEnabled && !setting(for: $0).isConfigurationUseless }
    }
}
