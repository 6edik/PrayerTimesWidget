import Foundation

struct SharedPrayerTimesStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }
    private let key = "prayer_times_cache_v2"
    private let calendar = Calendar(identifier: .gregorian)

    func replaceCache(with cache: PrayerTimesCache) {
        clear()
        saveCache(cache)
    }

    func clear() {
        defaults?.removeObject(forKey: key)
    }

    func load(for date: Date = Date(), settings: AutoPrayerSettings) -> PrayerTimes? {
        let cache = loadValidatedCache(settings: settings)
        let iso = isoDateString(from: date)
        return cache.days.first(where: { $0.isoDate == iso })?.times
    }

    func loadPreviousDay(for date: Date, settings: AutoPrayerSettings) -> PrayerTimes? {
        let previous = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        return load(for: previous, settings: settings)
    }

    func hasData(for date: Date, settings: AutoPrayerSettings) -> Bool {
        let cache = loadValidatedCache(settings: settings)
        let iso = isoDateString(from: date)
        return cache.days.contains(where: { $0.isoDate == iso })
    }

    func hasFullRange(for referenceDate: Date, settings: AutoPrayerSettings) -> Bool {
        let cache = loadValidatedCache(settings: settings)
        guard !cache.days.isEmpty else { return false }

        let availableDates = Set(cache.days.map(\.isoDate))
        let start = PrayerCachePolicy.fetchStart(from: referenceDate, calendar: calendar)

        for offset in 0..<PrayerCachePolicy.totalDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return false
            }

            let iso = isoDateString(from: date)
            if !availableDates.contains(iso) {
                return false
            }
        }

        return true
    }

    func hasToday(for settings: AutoPrayerSettings, referenceDate: Date = Date()) -> Bool {
        hasData(for: referenceDate, settings: settings)
    }

    func needsRefresh(
        settings: AutoPrayerSettings,
        referenceDate: Date = Date(),
        refreshThresholdDays: Int = 2
    ) -> Bool {
        let cache = loadValidatedCache(settings: settings)

        guard !cache.days.isEmpty else { return true }
        guard hasData(for: referenceDate, settings: settings) else { return true }
        guard let lastAvailable = lastAvailableDate(from: cache) else { return true }

        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: lastAvailable)
        let remainingDays = calendar.dateComponents([.day], from: start, to: end).day ?? -1

        return remainingDays <= refreshThresholdDays
    }

    func suggestedRefreshDate(
        settings: AutoPrayerSettings,
        refreshThresholdDays: Int = 2
    ) -> Date? {
        let cache = loadValidatedCache(settings: settings)

        guard !cache.days.isEmpty else { return Date() }
        guard let lastAvailable = lastAvailableDate(from: cache) else { return Date() }

        let targetDay = calendar.date(
            byAdding: .day,
            value: -refreshThresholdDays,
            to: lastAvailable
        ) ?? Date()

        return calendar.date(bySettingHour: 0, minute: 1, second: 0, of: targetDay) ?? targetDay
    }

    func cacheRangeText(settings: AutoPrayerSettings) -> String {
        let cache = loadValidatedCache(settings: settings)
        guard let first = cache.firstISODate, let last = cache.lastISODate else {
            return "--"
        }
        return "\(first) – \(last)"
    }

    func cacheDayCount(settings: AutoPrayerSettings) -> Int {
        loadValidatedCache(settings: settings).days.count
    }

    func cacheFetchedAt(settings: AutoPrayerSettings) -> Date? {
        let cache = loadValidatedCache(settings: settings)
        return cache.days.isEmpty ? nil : cache.fetchedAt
    }

    func remainingCoverageDays(
        from referenceDate: Date = Date(),
        settings: AutoPrayerSettings
    ) -> Int? {
        let cache = loadValidatedCache(settings: settings)
        guard let lastAvailable = lastAvailableDate(from: cache) else { return nil }

        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: lastAvailable)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    private func loadRawCache() -> PrayerTimesCache {
        guard
            let data = defaults?.data(forKey: key),
            let cache = try? JSONDecoder().decode(PrayerTimesCache.self, from: data)
        else {
            return .empty
        }

        return cache
    }

    private func saveCache(_ cache: PrayerTimesCache) {
        let uniqueDays = Dictionary(grouping: cache.days, by: \.isoDate)
            .compactMap { $0.value.first }
            .sorted { $0.isoDate < $1.isoDate }

        let cleaned = PrayerTimesCache(
            addressKey: cache.addressKey,
            methodKey: cache.methodKey,
            fetchedAt: cache.fetchedAt,
            days: uniqueDays
        )

        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        defaults?.set(data, forKey: key)
    }

    private func loadValidatedCache(settings: AutoPrayerSettings) -> PrayerTimesCache {
        let cache = loadRawCache()
        guard cacheMatchesSettings(cache, settings: settings) else {
            return .empty
        }
        return cache
    }

    private func cacheMatchesSettings(_ cache: PrayerTimesCache, settings: AutoPrayerSettings) -> Bool {
        let prayerSettings = settings.asPrayerSettings(for: Date())
        return cache.addressKey == normalizedAddress(prayerSettings.address)
            && cache.methodKey == String(describing: prayerSettings.method)
    }

    private func lastAvailableDate(from cache: PrayerTimesCache) -> Date? {
        guard let iso = cache.lastISODate else { return nil }
        return dateFromISO(iso)
    }

    private func normalizedAddress(_ address: String) -> String {
        address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dateFromISO(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }
}
