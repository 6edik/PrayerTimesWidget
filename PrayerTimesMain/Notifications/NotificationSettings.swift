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

struct PrayerNotificationSetting: Codable, Equatable {
    var isEnabled: Bool = false
}

/// Reminders for the three voluntary-fasting occasions the app recognizes
/// (see `VoluntaryFastingClassifier`). Each weekday/White-Days switch is
/// independent; `minutesAfterMaghrib` controls how long after the *eve's*
/// Maghrib the single combined reminder fires (never the fasting day's own
/// Maghrib — see `NotificationScheduler.fastingCandidates`).
struct VoluntaryFastingNotificationSetting: Codable, Equatable {
    var monday: Bool = false
    var thursday: Bool = false
    var whiteDays: Bool = false
    var minutesAfterMaghrib: Int = 10

    var hasAnyEnabled: Bool {
        monday || thursday || whiteDays
    }
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

/// Reminder for the user's own Zakat-due-date entries (`PersonalCalendarEntry`
/// with `kind == .zakatDueDate`). `notifyOnDay` isn't configurable here —
/// unlike holidays, the on-day reminder is the whole point of this feature;
/// only the optional day-before reminder is a separate toggle.
struct ZakatNotificationSetting: Codable, Equatable {
    var isEnabled: Bool = false
    var notifyDayBefore: Bool = false
    var hour: Int = 9
    var minute: Int = 0
}

/// Warns at the start of each daily Karāha window (see
/// `QiratTimeResolver`): Sonnenaufgangs-Karāha starting exactly at Shuruk
/// (never Fajr), and a fixed approximation immediately before Maghrib
/// (never "from Asr" — Asr's own valid time correctly extends all the way
/// to Maghrib, and is never presented as impermissible). Off by default,
/// per the same convention as every other opt-in reminder here — an
/// existing install never starts receiving these just because this key
/// now exists.
struct QiratTimesNotificationSetting: Codable, Equatable {
    var isEnabled: Bool = false
}

struct NotificationSettings: Codable, Equatable {
    var fajr: PrayerNotificationSetting
    var dhuhr: PrayerNotificationSetting
    var asr: PrayerNotificationSetting
    var maghrib: PrayerNotificationSetting
    var isha: PrayerNotificationSetting

    // Keyed by `MajorIslamicHoliday.rawValue`. Absent entries behave like
    // `HolidayNotificationSetting()` (disabled).
    var holidays: [String: HolidayNotificationSetting]

    var voluntaryFasting: VoluntaryFastingNotificationSetting

    // Off by default, per spec — an existing install never starts sending
    // Zakat reminders just because this key now exists.
    var zakat: ZakatNotificationSetting

    var qirat: QiratTimesNotificationSetting

    init(
        fajr: PrayerNotificationSetting = PrayerNotificationSetting(),
        dhuhr: PrayerNotificationSetting = PrayerNotificationSetting(),
        asr: PrayerNotificationSetting = PrayerNotificationSetting(),
        maghrib: PrayerNotificationSetting = PrayerNotificationSetting(),
        isha: PrayerNotificationSetting = PrayerNotificationSetting(),
        holidays: [String: HolidayNotificationSetting] = [:],
        voluntaryFasting: VoluntaryFastingNotificationSetting = VoluntaryFastingNotificationSetting(),
        zakat: ZakatNotificationSetting = ZakatNotificationSetting(),
        qirat: QiratTimesNotificationSetting = QiratTimesNotificationSetting()
    ) {
        self.fajr = fajr
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
        self.holidays = holidays
        self.voluntaryFasting = voluntaryFasting
        self.zakat = zakat
        self.qirat = qirat
    }

    private enum CodingKeys: String, CodingKey {
        case fajr, dhuhr, asr, maghrib, isha, holidays, voluntaryFasting, zakat, qirat
    }

    // Custom decode so settings saved before `holidays`/`voluntaryFasting`/
    // `zakat`/`qirat` existed still decode — with their defaults — instead
    // of a decode failure (missing key) that would silently reset every
    // other already-configured prayer notification setting too.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fajr = try container.decodeIfPresent(PrayerNotificationSetting.self, forKey: .fajr) ?? PrayerNotificationSetting()
        dhuhr = try container.decodeIfPresent(PrayerNotificationSetting.self, forKey: .dhuhr) ?? PrayerNotificationSetting()
        asr = try container.decodeIfPresent(PrayerNotificationSetting.self, forKey: .asr) ?? PrayerNotificationSetting()
        maghrib = try container.decodeIfPresent(PrayerNotificationSetting.self, forKey: .maghrib) ?? PrayerNotificationSetting()
        isha = try container.decodeIfPresent(PrayerNotificationSetting.self, forKey: .isha) ?? PrayerNotificationSetting()
        holidays = try container.decodeIfPresent([String: HolidayNotificationSetting].self, forKey: .holidays) ?? [:]
        voluntaryFasting = try container.decodeIfPresent(VoluntaryFastingNotificationSetting.self, forKey: .voluntaryFasting) ?? VoluntaryFastingNotificationSetting()
        zakat = try container.decodeIfPresent(ZakatNotificationSetting.self, forKey: .zakat) ?? ZakatNotificationSetting()
        qirat = try container.decodeIfPresent(QiratTimesNotificationSetting.self, forKey: .qirat) ?? QiratTimesNotificationSetting()
    }

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

    var hasAnyVoluntaryFastingEnabled: Bool {
        voluntaryFasting.hasAnyEnabled
    }

    var hasAnyZakatEnabled: Bool {
        zakat.isEnabled
    }

    var hasAnyQiratEnabled: Bool {
        qirat.isEnabled
    }
}
