import Foundation

/// Pure persistence for the Islamic-calendar special-day cache — no
/// filtering logic here. This file is compiled into both the main app and
/// the widget extension target, but `IslamicHolidayClassifier` (the app's
/// curated-holiday definition) is main-app-only, so it can't be referenced
/// from here. Every caller is expected to pass only already-filtered
/// (`IslamicHolidayClassifier.filterRelevant`) days to `saveYear` — see
/// `IslamicCalendarViewModel` and `NotificationScheduler`, the only two
/// production call sites, both of which filter before calling this and
/// migrate already-persisted data via
/// `IslamicHolidayClassifier.loadYearMigratingIfNeeded`.
struct SharedIslamicCalendarStore {
    // Defaults to the real App Group suite for every production call site.
    // Tests can pass a dedicated suite name so they don't read/write the
    // developer's real cached holiday data.
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "islamic_calendar_cache_v1"

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    func loadYear(_ year: Int) -> [IslamicSpecialDay]? {
        loadAll().first(where: { $0.year == year })?.specialDays
    }

    func saveYear(_ year: Int, days: [IslamicSpecialDay]) {
        var caches = loadAll()
        caches.removeAll { $0.year == year }
        caches.append(
            IslamicCalendarYearCache(
                year: year,
                fetchedAt: Date(),
                specialDays: days
            )
        )

        guard let data = try? JSONEncoder().encode(caches) else { return }
        defaults?.set(data, forKey: key)
    }

    func clear() {
        defaults?.removeObject(forKey: key)
    }

    private func loadAll() -> [IslamicCalendarYearCache] {
        guard
            let data = defaults?.data(forKey: key),
            let caches = try? JSONDecoder().decode([IslamicCalendarYearCache].self, from: data)
        else {
            return []
        }

        return caches
    }
}
