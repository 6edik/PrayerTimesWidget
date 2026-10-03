import Foundation

/// The user's single personal Zakat-due-date rule, configured under
/// "Besondere Tage" — entirely separate from personal notes
/// (`PersonalCalendarEntry`/`PersonalCalendarStore`), the AlAdhan holiday
/// cache (`SharedIslamicCalendarStore`) and the prayer-times cache
/// (`SharedPrayerTimesStore`). Always recurs every Hijri year; there is no
/// one-time variant and no Gregorian-based repeat option — see
/// `ZakatOccurrenceCalculator` for turning this fixed rule into concrete
/// Gregorian occurrences for display/notifications. The app never computes
/// or claims this date is religiously binding; it only stores the day the
/// user themselves chose.
nonisolated struct ZakatDueDate: Codable, Equatable {
    /// 1...30, Umm-al-Qura basis (`HijriDateFormatting.calendar()`).
    var hijriDay: Int
    /// 1...12.
    var hijriMonth: Int
    /// Lets the user keep their chosen Hijri day/month on record while
    /// deactivating it — distinct from deleting it outright. Every call
    /// site that surfaces this rule (the "Besondere Tage" chronological
    /// list, the day sheet's event block, and `NotificationScheduler
    /// .zakatCandidates`) must treat a disabled rule exactly like "no rule
    /// configured", never partially honoring it.
    var isEnabled: Bool

    nonisolated init(hijriDay: Int, hijriMonth: Int, isEnabled: Bool = true) {
        self.hijriDay = hijriDay
        self.hijriMonth = hijriMonth
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case hijriDay, hijriMonth, isEnabled
    }

    // Saved before `isEnabled` existed: such a value was always active,
    // so it decodes as enabled rather than failing to decode.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hijriDay = try container.decode(Int.self, forKey: .hijriDay)
        hijriMonth = try container.decode(Int.self, forKey: .hijriMonth)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// Pure persistence for `ZakatDueDate`. Its own dedicated storage key,
/// never touched by `CacheResetService`, a location change, a calculation
/// method change, or an AlAdhan/prayer-times refresh.
nonisolated struct ZakatDueDateStore {
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "zakat_due_date_v1"

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    nonisolated func load() -> ZakatDueDate? {
        guard
            let data = defaults?.data(forKey: key),
            let decoded = try? JSONDecoder().decode(ZakatDueDate.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    nonisolated func save(_ value: ZakatDueDate) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: key)
    }

    nonisolated func clear() {
        defaults?.removeObject(forKey: key)
    }

    /// One-time migration from the previous design, where a Zakat due date
    /// was created as a `PersonalCalendarEntry` with `kind == .zakatDueDate`
    /// mixed into "Meine Notizen". Runs at most once: if this store already
    /// has a value, it does nothing. Otherwise it takes the first legacy
    /// Zakat entry found (if any), carries its (day, month) rule forward
    /// into this store, and removes every legacy Zakat entry from
    /// `personalStore` — so it can never again show up in "Meine Notizen"
    /// or be editable through the notes form, regardless of how many
    /// duplicates existed.
    nonisolated static func migrateFromPersonalCalendarIfNeeded(
        personalStore: PersonalCalendarStore = PersonalCalendarStore(),
        zakatStore: ZakatDueDateStore = ZakatDueDateStore()
    ) {
        guard zakatStore.load() == nil else { return }

        let allEntries = personalStore.loadAll()
        let legacyZakatEntries = allEntries.filter { $0.kind == .zakatDueDate }
        guard !legacyZakatEntries.isEmpty else { return }

        if let first = legacyZakatEntries.first, let day = first.hijriDay, let month = first.hijriMonth {
            zakatStore.save(ZakatDueDate(hijriDay: day, hijriMonth: month))
        }

        for entry in legacyZakatEntries {
            personalStore.delete(id: entry.id)
        }
    }
}
