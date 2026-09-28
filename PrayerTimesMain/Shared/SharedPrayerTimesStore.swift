import Foundation

struct SharedPrayerTimesStore {
    // Defaults to the real App Group suite for every production call site.
    // Tests can pass a dedicated suite name so they don't read/write the
    // developer's real cached prayer times.
    private let suiteName: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
    // v3: the cache is now keyed by confirmed location (coordinate when
    // available) instead of by address string alone — bumping the storage
    // key deliberately invalidates any v2 cache instead of trying to
    // reinterpret its addressKey, which never carried coordinates.
    private let key = "prayer_times_cache_v3"
    private let calendar = Calendar(identifier: .gregorian)

    nonisolated init(suiteName: String = AppGroup.id) {
        self.suiteName = suiteName
    }

    func replaceCache(with cache: PrayerTimesCache) {
        // A single `set(forKey:)` call is itself atomic, so writing the new
        // cache directly (without clearing first) avoids a brief window
        // where readers (app, widget, background task) would see an empty
        // cache between the clear and the save. saveCache() always writes
        // the full `days` array for the given key, so no stale data from a
        // previous address/method can leak through.
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
            locationKey: cache.locationKey,
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
        return cache.locationKey == LocationKey.key(address: settings.address, location: settings.location)
            && cache.methodKey == String(describing: settings.method)
    }

    private func lastAvailableDate(from cache: PrayerTimesCache) -> Date? {
        guard let iso = cache.lastISODate else { return nil }
        return dateFromISO(iso)
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
    
    func loadPrayerDay(for date: Date = Date(), settings: AutoPrayerSettings) -> PrayerDay? {
        let cache = loadValidatedCache(settings: settings)
        let iso = isoDateString(from: date)
        return cache.days.first(where: { $0.isoDate == iso })
    }
    
    func loadHijriDay(for date: Date = Date(), settings: AutoPrayerSettings) -> HijriDay? {
        loadPrayerDay(for: date, settings: settings)?.hijri
    }

    /// Decodes the cache once and returns all cached days keyed by ISO date.
    /// Use this instead of calling `loadPrayerDay`/`load` in a loop (e.g. once
    /// per calendar grid cell), which would otherwise re-decode the full
    /// cache from UserDefaults for every single day.
    func loadAllDays(settings: AutoPrayerSettings) -> [String: PrayerDay] {
        let cache = loadValidatedCache(settings: settings)
        return Dictionary(uniqueKeysWithValues: cache.days.map { ($0.isoDate, $0) })
    }

    /// Returns the cache exactly as stored on disk, without validating it
    /// against any particular `AutoPrayerSettings` — unlike every other
    /// accessor above, this can return data for a location/method that no
    /// longer matches the current settings (`loadValidatedCache` would
    /// silently collapse that to `.empty`). Only the "Gespeicherte
    /// Gebetszeiten" inspector should call this: it needs to show — and
    /// explain mismatches for — whatever is actually persisted, not just
    /// what would currently be served. Read-only, single decode; never
    /// writes anything.
    func snapshot() -> PrayerTimesCache {
        loadRawCache()
    }
}
