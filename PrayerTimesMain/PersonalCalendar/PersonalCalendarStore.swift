import Foundation

/// Pure persistence for the user's personal calendar entries. Uses its own
/// dedicated storage key, entirely separate from `SharedPrayerTimesStore`
/// (prayer-times cache) and `SharedIslamicCalendarStore` (AlAdhan holiday
/// cache) — a cache reset, API refresh, location change or calculation
/// method change never touches this key (see `CacheResetService`, which
/// intentionally never references this store). Never logs entry content:
/// titles and notes are private user data.
nonisolated struct PersonalCalendarStore {
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "personal_calendar_entries_v1"

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    nonisolated func loadAll() -> [PersonalCalendarEntry] {
        guard
            let data = defaults?.data(forKey: key),
            let entries = try? JSONDecoder().decode([PersonalCalendarEntry].self, from: data)
        else {
            return []
        }

        return entries
    }

    nonisolated func upsert(_ entry: PersonalCalendarEntry) {
        var entries = loadAll()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        save(entries)
    }

    nonisolated func delete(id: UUID) {
        var entries = loadAll()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    private nonisolated func save(_ entries: [PersonalCalendarEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults?.set(data, forKey: key)
    }
}
