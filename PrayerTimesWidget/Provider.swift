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
        let raw = store.load(for: date, settings: settings) ?? fallback
        let adjusted = raw.applyingAdjustments(settings.adjustments)

        return PrayerEntry(
            date: date,
            times: adjusted,
            previousDayTimes: store.loadPreviousDay(for: date, settings: settings)?
                .applyingAdjustments(settings.adjustments)
        )
    }

    private func buildEntries(from now: Date, settings: AutoPrayerSettings) -> [PrayerEntry] {
        var dates: [Date] = [normalizedTimelineDate(now)]

        let todayRaw = store.load(for: now, settings: settings) ?? fallback
        let todayTimes = todayRaw.applyingAdjustments(settings.adjustments)

        appendPrayerMoments(
            for: todayTimes,
            base: now,
            threshold: now,
            into: &dates
        )

        appendProgressDates(
            for: todayTimes,
            base: now,
            threshold: now,
            stepMinutes: 5,
            into: &dates
        )

        if let tomorrowStart = nextMidnightRefreshDate(from: now) {
            dates.append(normalizedTimelineDate(tomorrowStart))

            let tomorrowRaw = store.load(for: tomorrowStart, settings: settings) ?? fallback
            let tomorrowTimes = tomorrowRaw.applyingAdjustments(settings.adjustments)

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

    private func appendProgressDates(
        for times: PrayerTimes,
        base: Date,
        threshold: Date,
        stepMinutes: Int,
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

        let sortedMoments = prayerMoments
            .compactMap { timeToDate($0, base: base) }
            .sorted()

        guard let nextMoment = sortedMoments.first(where: { $0 > threshold }) else {
            return
        }

        var cursor = nextFiveMinuteMark(after: threshold, stepMinutes: stepMinutes)

        while cursor < nextMoment {
            dates.append(cursor)

            guard let nextCursor = calendar.date(byAdding: .minute, value: stepMinutes, to: cursor) else {
                break
            }

            cursor = normalizedTimelineDate(nextCursor)
        }
    }

    private func nextFiveMinuteMark(after date: Date, stepMinutes: Int) -> Date {
        let normalized = normalizedTimelineDate(date)
        let minute = calendar.component(.minute, from: normalized)
        let remainder = minute % stepMinutes
        let delta = remainder == 0 ? stepMinutes : (stepMinutes - remainder)

        let rounded = calendar.date(byAdding: .minute, value: delta, to: normalized) ?? normalized
        return normalizedTimelineDate(rounded)
    }

    private func normalizedTimelineDate(_ date: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
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
                dates.append(normalizedTimelineDate(date))
            }
        }
    }

    private func timeToDate(_ value: String, base: Date) -> Date? {
        let parts = value.split(separator: ":")
        guard
            parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else { return nil }

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
