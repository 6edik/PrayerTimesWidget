import Foundation

struct SharedIslamicCalendarStore {
    // Defaults to the real App Group suite for every production call site.
    // Tests can pass a dedicated suite name so they don't read/write the
    // developer's real cached holiday data.
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    private let key = "islamic_calendar_cache_v1"

    init(suiteName: String = AppGroup.id) {
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
