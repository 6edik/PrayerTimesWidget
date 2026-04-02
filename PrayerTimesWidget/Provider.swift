import Foundation
import WidgetKit

struct Provider: TimelineProvider {
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let statsStore = RefreshStatsStore()
    private let calendar = Calendar(identifier: .gregorian)

    private let fallback = PrayerTimes(
        fajr: "--:--",
        shuruk: "--:--",
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
        readableDay: "--",
        hijriDate: "--",
        hijriDay: "--",
        timezone: "--"
    )

    func placeholder(in context: Context) -> PrayerEntry {
        let settings = settingsStore.loadAutoSettings()
        return makeEntry(for: Date(), settings: settings)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        let settings = settingsStore.loadAutoSettings()
        completion(makeEntry(for: Date(), settings: settings))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        Task {
            let now = Date()
            let settings = settingsStore.loadAutoSettings()

            let shouldFetch =
                !store.hasFullRange(for: now, settings: settings) ||
                store.needsRefresh(
                    settings: settings,
                    referenceDate: now,
                    refreshThresholdDays: 2
                )

            if shouldFetch {
                statsStore.markAttempt(source: .widgetTimeline)

                do {
                    try await SharedPrayerCacheRefresher().refresh(
                        settings: settings,
                        now: now
                    )

                    statsStore.markSuccess(source: .widgetTimeline)
                    statsStore.setNextPlannedRefresh(
                        store.suggestedRefreshDate(
                            settings: settings,
                            refreshThresholdDays: 2
                        )
                    )
                } catch {
                    statsStore.markFailure(
                        source: .widgetTimeline,
                        error: error.localizedDescription
                    )

                    let retry = now.addingTimeInterval(30 * 60)
                    let entries = buildEntries(from: now, settings: settings)

                    statsStore.incrementTimelineBuildCount()
                    statsStore.setNextPlannedRefresh(retry)

                    completion(
                        Timeline(
                            entries: entries.isEmpty ? [makeEntry(for: now, settings: settings)] : entries,
                            policy: .after(retry)
                        )
                    )
                    return
                }
            }

            let entries = buildEntries(from: now, settings: settings)

            statsStore.incrementTimelineBuildCount()

            completion(
                Timeline(
                    entries: entries.isEmpty ? [makeEntry(for: now, settings: settings)] : entries,
                    policy: .atEnd
                )
            )
        }
    }

    private func makeEntry(for date: Date, settings: AutoPrayerSettings) -> PrayerEntry {
        PrayerEntry(
            date: date,
            times: store.load(for: date, settings: settings) ?? fallback,
            previousDayTimes: store.loadPreviousDay(for: date, settings: settings)
        )
    }

    private func buildEntries(from now: Date, settings: AutoPrayerSettings) -> [PrayerEntry] {
        var dates: [Date] = [now]

        let todayTimes = store.load(for: now, settings: settings) ?? fallback
        appendPrayerMoments(for: todayTimes, base: now, threshold: now, into: &dates)

        if let tomorrowStart = nextMidnightRefreshDate(from: now) {
            dates.append(tomorrowStart)

            let tomorrowTimes = store.load(for: tomorrowStart, settings: settings) ?? fallback
            appendPrayerMoments(
                for: tomorrowTimes,
                base: tomorrowStart,
                threshold: now,
                into: &dates
            )
        }

        let uniqueSortedDates = Array(Set(dates)).sorted()
        return uniqueSortedDates.map { makeEntry(for: $0, settings: settings) }
    }

    private func appendPrayerMoments(
        for times: PrayerTimes,
        base: Date,
        threshold: Date,
        into dates: inout [Date]
    ) {
        let prayerMoments = [
            times.fajr,
            times.shuruk,
            times.dhuhr,
            times.asr,
            times.maghrib,
            times.isha
        ]

        for value in prayerMoments {
            if let date = timeToDate(value, base: base), date > threshold {
                dates.append(date)
            }
        }
    }

    private func timeToDate(_ value: String, base: Date) -> Date? {
        let parts = value.split(separator: ":")

        guard
            parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return nil
        }

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: base
        )
    }

    private func nextMidnightRefreshDate(from date: Date) -> Date? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)
        return calendar.date(byAdding: .minute, value: 1, to: startOfTomorrow)
    }
}
