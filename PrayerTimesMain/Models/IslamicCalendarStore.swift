import Foundation

struct SharedIslamicCalendarStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }
    private let key = "islamic_calendar_cache_v1"

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
