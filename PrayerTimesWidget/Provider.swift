import Foundation
import WidgetKit

struct Provider: TimelineProvider {
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let statsStore = RefreshStatsStore()
    private let refreshCoordinator = PrayerRefreshCoordinator()
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

            if refreshCoordinator.needsRefresh(settings: settings, referenceDate: now) {
                let outcome = await refreshCoordinator.refreshIfNeeded(
                    settings: settings,
                    source: .widgetTimeline,
                    now: now
                )

                if case .failure = outcome {
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
        let adjusted = raw.applyingAdjustmentsWithDayOffsets(settings.adjustments)

        let previousRaw = store.loadPreviousDay(for: date, settings: settings)
        let previousAdjusted = previousRaw?.applyingAdjustmentsWithDayOffsets(settings.adjustments)

        return PrayerEntry(
            date: date,
            times: adjusted.times,
            dayOffsets: adjusted.dayOffsets,
            previousDayTimes: previousAdjusted?.times,
            previousDayOffsets: previousAdjusted?.dayOffsets ?? .zero
        )
    }

    private func buildEntries(from now: Date, settings: AutoPrayerSettings) -> [PrayerEntry] {
        var dates: [Date] = [normalizedTimelineDate(now)]

        // Only the boundary instant where "Letztes Drittel der Nacht"
        // begins — never periodic ticks — so the widget refreshes exactly
        // when the window starts, without extra API requests.
        if let lastThird = LastThirdOfNightResolver.window(now: now, store: store, settings: settings),
           lastThird.start > now {
            dates.append(normalizedTimelineDate(lastThird.start))
        }

        // Same idea for the Karāha boundaries: only their start/end
        // instants, so the widget's "active now" indicator flips exactly
        // on time without periodic ticks.
        let qiratWindows = QiratTimeResolver.windows(now: now, store: store, settings: settings)
        for boundary in [qiratWindows.sunriseKaraha?.start, qiratWindows.sunriseKaraha?.end, qiratWindows.lateMaghribKaraha?.start, qiratWindows.lateMaghribKaraha?.end] {
            if let boundary, boundary > now {
                dates.append(normalizedTimelineDate(boundary))
            }
        }

        let todayRaw = store.load(for: now, settings: settings) ?? fallback
        let todayAdjusted = todayRaw.applyingAdjustmentsWithDayOffsets(settings.adjustments)

        appendPrayerMoments(
            for: todayAdjusted,
            base: now,
            threshold: now,
            into: &dates
        )

        appendProgressDates(
            for: todayAdjusted,
            base: now,
            threshold: now,
            stepMinutes: 5,
            into: &dates
        )

        if let tomorrowStart = nextMidnightRefreshDate(from: now) {
            dates.append(normalizedTimelineDate(tomorrowStart))

            let tomorrowRaw = store.load(for: tomorrowStart, settings: settings) ?? fallback
            let tomorrowAdjusted = tomorrowRaw.applyingAdjustmentsWithDayOffsets(settings.adjustments)

            appendPrayerMoments(
                for: tomorrowAdjusted,
                base: tomorrowStart,
                threshold: now,
                into: &dates
            )
        }

        let uniqueSortedDates = Array(Set(dates)).sorted()
        return uniqueSortedDates.map { makeEntry(for: $0, settings: settings) }
    }

    private func adjustedMoments(for adjusted: AdjustedPrayerTimes) -> [PrayerTimeAdjuster.AdjustedTime] {
        [
            .init(value: adjusted.times.fajr, dayOffset: adjusted.dayOffsets.fajr),
            .init(value: adjusted.times.shuruk, dayOffset: adjusted.dayOffsets.shuruk),
            .init(value: adjusted.times.dhuhr, dayOffset: adjusted.dayOffsets.dhuhr),
            .init(value: adjusted.times.asr, dayOffset: adjusted.dayOffsets.asr),
            .init(value: adjusted.times.maghrib, dayOffset: adjusted.dayOffsets.maghrib),
            .init(value: adjusted.times.isha, dayOffset: adjusted.dayOffsets.isha)
        ]
    }

    private func appendProgressDates(
        for adjusted: AdjustedPrayerTimes,
        base: Date,
        threshold: Date,
        stepMinutes: Int,
        into dates: inout [Date]
    ) {
        let sortedMoments = adjustedMoments(for: adjusted)
            .compactMap { PrayerTimeAdjuster.date(forAdjusted: $0, base: base, calendar: calendar) }
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
        for adjusted: AdjustedPrayerTimes,
        base: Date,
        threshold: Date,
        into dates: inout [Date]
    ) {
        for moment in adjustedMoments(for: adjusted) {
            if let date = PrayerTimeAdjuster.date(forAdjusted: moment, base: base, calendar: calendar), date > threshold {
                dates.append(normalizedTimelineDate(date))
            }
        }
    }

    private func nextMidnightRefreshDate(from date: Date) -> Date? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)
        return calendar.date(byAdding: .minute, value: 1, to: startOfTomorrow)
    }
}
