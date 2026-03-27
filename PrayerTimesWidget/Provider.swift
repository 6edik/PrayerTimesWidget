import Foundation
import WidgetKit

struct Provider: TimelineProvider {
    private let service = PrayerTimesService()
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let statsStore = RefreshStatsStore()

    private let fallback = PrayerTimes(
        fajr: "--:--",
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
        hijriDate: "--",
        hijriDay: "--",
        timezone: "--"
    )

    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(date: Date(), times: store.load() ?? fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        let entry = PrayerEntry(date: Date(), times: store.load() ?? fallback)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        Task {
            let settings = settingsStore.load()
            statsStore.markAttempt(source: .widgetTimeline)

            do {
                let times = try await service.fetchPrayerTimes(settings: settings)
                store.save(times)

                let entry = PrayerEntry(date: Date(), times: times)
                let nextRefresh = nextMidnightRefreshDate()

                statsStore.markSuccess(source: .widgetTimeline)
                statsStore.incrementTimelineBuildCount()
                statsStore.setNextPlannedRefresh(nextRefresh)

                completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
            } catch {
                let entry = PrayerEntry(date: Date(), times: store.load() ?? fallback)
                let retry = Date().addingTimeInterval(15 * 60)

                statsStore.markFailure(source: .widgetTimeline, error: error.localizedDescription)
                statsStore.incrementTimelineBuildCount()
                statsStore.setNextPlannedRefresh(retry)

                completion(Timeline(entries: [entry], policy: .after(retry)))
            }
        }
    }

    private func nextMidnightRefreshDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)
        return calendar.date(byAdding: .minute, value: 1, to: startOfTomorrow) ?? Date().addingTimeInterval(15 * 60)
    }
}
