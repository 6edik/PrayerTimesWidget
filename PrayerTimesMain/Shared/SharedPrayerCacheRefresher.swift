import Foundation

struct SharedPrayerCacheRefresher {
    private let service = PrayerTimesService()
    private let store = SharedPrayerTimesStore()

    func refresh(settings: PrayerSettings, now: Date = Date()) async throws {
        let fetchStart = PrayerCachePolicy.fetchStart(from: now)

        let cache = try await service.fetchPrayerTimesCache(
            settings: settings,
            referenceDate: fetchStart,
            coverageDays: PrayerCachePolicy.totalDays
        )

        store.saveCache(cache)
    }
}
