import Foundation

struct SharedPrayerCacheRefresher {
    private let service = PrayerTimesService()
    private let store = SharedPrayerTimesStore()

    func refresh(settings: AutoPrayerSettings, now: Date = Date()) async throws {
        let fetchStart = PrayerCachePolicy.fetchStart(from: now)
        let prayerSettings = settings.asPrayerSettings(for: fetchStart)

        let cache = try await service.fetchPrayerTimesCache(
            settings: prayerSettings,
            referenceDate: fetchStart,
            coverageDays: PrayerCachePolicy.totalDays
        )

        store.replaceCache(with: cache)
    }
}
