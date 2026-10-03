import Foundation
import WidgetKit

struct Provider: TimelineProvider {
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let statsStore = RefreshStatsStore()
    private let refreshCoordinator = PrayerRefreshCoordinator()
    private let calendar = Calendar(identifier: .gregorian)

    // How many cached future days to plan timeline entries for in a single
    // `getTimeline` call. Bounded well inside `PrayerCachePolicy.futureDays`
    // (30) so entries never run past what's actually cached; small enough
    // that a timeline stays a short list of real prayer-change/day-boundary
    // instants, never a dense per-minute schedule (the progress bar itself
    // is driven by `ProgressView(timerInterval:)` in the view layer, so no
    // intermediate "tick" entries are needed at all). Planning several days
    // ahead — instead of stopping at tomorrow — means `.atEnd` chains to a
    // fresh `getTimeline` call only every few days, not daily.
    private static let planningHorizonDays = 7

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

        let previousDay = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let previousRaw = store.load(for: previousDay, settings: settings)
        let previousAdjusted = previousRaw?.applyingAdjustmentsWithDayOffsets(settings.adjustments)

        let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let nextRaw = store.load(for: nextDay, settings: settings)
        let nextAdjusted = nextRaw?.applyingAdjustmentsWithDayOffsets(settings.adjustments)

        return PrayerEntry(
            date: date,
            times: adjusted.times,
            dayOffsets: adjusted.dayOffsets,
            previousDayTimes: previousAdjusted?.times,
            previousDayOffsets: previousAdjusted?.dayOffsets ?? .zero,
            nextDayTimes: nextAdjusted?.times,
            nextDayOffsets: nextAdjusted?.dayOffsets ?? .zero
        )
    }

    /// Builds one timeline entry for every prayer change and day boundary
    /// from `now` through `planningHorizonDays` cached days ahead — or
    /// fewer, the moment the cache actually runs out — never a fabricated
    /// entry beyond what's really stored. Each entry's own `date` resolves
    /// to that entry's own calendar day's cached times in `makeEntry`, so a
    /// later entry never carries an earlier day's stale snapshot.
    private func buildEntries(from now: Date, settings: AutoPrayerSettings) -> [PrayerEntry] {
        var dates: Set<Date> = [normalizedTimelineDate(now)]

        // Only the boundary instant where "Letztes Drittel der Nacht"
        // begins — never periodic ticks — so the widget refreshes exactly
        // when the window starts, without extra API requests.
        if let lastThird = LastThirdOfNightResolver.window(now: now, store: store, settings: settings),
           lastThird.start > now {
            dates.insert(normalizedTimelineDate(lastThird.start))
        }

        // Same idea for the Karāha boundaries: only their start/end
        // instants, so the widget's "active now" indicator flips exactly
        // on time without periodic ticks.
        let qiratWindows = QiratTimeResolver.windows(now: now, store: store, settings: settings)
        for boundary in [qiratWindows.sunriseKaraha?.start, qiratWindows.sunriseKaraha?.end, qiratWindows.lateMaghribKaraha?.start, qiratWindows.lateMaghribKaraha?.end] {
            if let boundary, boundary > now {
                dates.insert(normalizedTimelineDate(boundary))
            }
        }

        var cursorDay = calendar.startOfDay(for: now)

        for _ in 0..<Self.planningHorizonDays {
            guard let dayRaw = store.load(for: cursorDay, settings: settings) else { break }
            let dayAdjusted = dayRaw.applyingAdjustmentsWithDayOffsets(settings.adjustments)

            var locationCalendar = calendar
            locationCalendar.timeZone = TimeZone(identifier: dayAdjusted.times.timezone) ?? .current

            appendPrayerMoments(for: dayAdjusted, base: cursorDay, threshold: now, calendar: locationCalendar, into: &dates)

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursorDay) else { break }

            // A day-boundary instant even on days with no prayer moment
            // landing exactly at midnight, so "today"-scoped display (the
            // Gregorian/Hijri header, the Friday-only Jum'ah naming) still
            // refreshes right at midnight.
            if let midnightRefresh = calendar.date(byAdding: .minute, value: 1, to: nextDay), midnightRefresh > now {
                dates.insert(normalizedTimelineDate(midnightRefresh))
            }

            cursorDay = nextDay
        }

        let uniqueSortedDates = dates.sorted()
        return uniqueSortedDates.map { makeEntry(for: $0, settings: settings) }
    }

    private func appendPrayerMoments(
        for adjusted: AdjustedPrayerTimes,
        base: Date,
        threshold: Date,
        calendar: Calendar,
        into dates: inout Set<Date>
    ) {
        let moments: [(value: String, dayOffset: Int)] = [
            (adjusted.times.fajr, adjusted.dayOffsets.fajr),
            (adjusted.times.shuruk, adjusted.dayOffsets.shuruk),
            (adjusted.times.dhuhr, adjusted.dayOffsets.dhuhr),
            (adjusted.times.asr, adjusted.dayOffsets.asr),
            (adjusted.times.maghrib, adjusted.dayOffsets.maghrib),
            (adjusted.times.isha, adjusted.dayOffsets.isha)
        ]

        for moment in moments {
            if let date = PrayerTimeAdjuster.date(
                forAdjusted: .init(value: moment.value, dayOffset: moment.dayOffset),
                base: base,
                calendar: calendar
            ), date > threshold {
                dates.insert(normalizedTimelineDate(date))
            }
        }
    }

    private func normalizedTimelineDate(_ date: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }
}
