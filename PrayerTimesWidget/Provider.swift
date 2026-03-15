import Foundation
import WidgetKit

struct Provider: TimelineProvider {
    private let store = SharedPrayerTimesStore()

    private let fallback = PrayerTimes(
        fajr: "--:--",
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
        hijriDate: "--",
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
        let entry = PrayerEntry(date: Date(), times: store.load() ?? fallback)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
