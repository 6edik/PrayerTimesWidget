import Foundation

/// Pure Date-only calculation of the Duha (Chasht) voluntary-prayer window
/// per Hanafi fiqh: it begins only once the sunrise Karāha has ended —
/// never at Shuruk itself — and ends where the Karāha-vor-Dhuhr window
/// begins (never at Dhuhr's own start directly — that short Karāha window
/// sits between Duha and Dhuhr, never shown as part of either). The
/// preferred time is approximately one quarter of the way between Shuruk
/// and Dhuhr, but is never allowed to fall before `start` or after `end`.
///
/// Deliberately pure and Date-only — no timezone/cache lookups here,
/// mirroring `LastThirdOfNightCalculator`/`QiratTimeCalculator`. Given
/// already-resolved absolute instants (personal minute adjustments already
/// applied exactly once by the caller), this only does the arithmetic —
/// never fabricates a window from missing or malformed input.
nonisolated enum DuhaCalculator {
    struct Window: Equatable {
        /// End of the sunrise Karāha — the earliest Duha may be prayed.
        /// Always exactly the same instant already shown elsewhere in the
        /// app as the Karāha-nach-Shuruk end (see `QiratTimeResolver`) —
        /// never a second, independently computed Karāha boundary.
        let start: Date
        /// The start of the Karāha-vor-Dhuhr window — the latest Duha may
        /// be prayed. Duha is never shown extending into that Karāha, let
        /// alone into Dhuhr's own waqt itself.
        let end: Date
        /// Approximately Shuruk + one quarter of the Shuruk-to-Dhuhr
        /// duration, clamped to fall within `start...end`. `nil` only when
        /// Shuruk itself wasn't available to compute the quarter-point —
        /// never a fabricated fallback time.
        let preferredStart: Date?

        /// Clamped 0...1 fraction of the window elapsed at `date`.
        func progress(at date: Date) -> Double {
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return 0 }
            return min(max(date.timeIntervalSince(start) / total, 0), 1)
        }
    }

    /// - Parameters:
    ///   - sunriseKarahaEnd: the already-computed end of the sunrise Karāha
    ///     window (`QiratTimeResolver.ApproximateWindow.end`), reused as-is
    ///     for `start` — the app's single source of truth for that moment.
    ///   - shuruk: Shuruk itself, used only to locate the preferred-time
    ///     quarter-point — never to derive `start`.
    ///   - dhuhr: the start of Dhuhr's own waqt — used only for the
    ///     quarter-point calculation, never as `end` directly.
    ///   - preDhuhrKarahaStart: the already-computed start of the Karāha-
    ///     vor-Dhuhr window (`QiratTimeResolver.ApproximateWindow.start`),
    ///     reused as-is for `end` — never a second, independently computed
    ///     boundary. Falls back to `dhuhr` only when that Karāha window
    ///     itself is unavailable (suppressed, e.g. implausible latitude),
    ///     so Duha still resolves to a sane (if slightly generous) window
    ///     instead of disappearing entirely.
    /// - Returns: `nil` whenever the resulting `end` is not strictly after
    ///   `sunriseKarahaEnd` — never a fabricated or inverted window.
    static func window(sunriseKarahaEnd: Date, shuruk: Date?, dhuhr: Date, preDhuhrKarahaStart: Date?) -> Window? {
        let end = preDhuhrKarahaStart ?? dhuhr
        guard end > sunriseKarahaEnd else { return nil }

        var preferredStart: Date?
        if let shuruk, dhuhr > shuruk {
            let quarterPoint = shuruk.addingTimeInterval(dhuhr.timeIntervalSince(shuruk) / 4)
            preferredStart = min(max(quarterPoint, sunriseKarahaEnd), end)
        }

        return Window(start: sunriseKarahaEnd, end: end, preferredStart: preferredStart)
    }

    /// Convenience that resolves "today's" Shuruk/Dhuhr from already-
    /// adjusted cached data and reuses `sunriseKarahaWindow.end`/
    /// `preDhuhrKarahaWindow.start` as `start`/`end` — never recomputing a
    /// second Karāha window. `nil` whenever the sunrise-Karāha window
    /// itself is unavailable (suppressed, e.g. implausible latitude, or no
    /// cached data) — without a computed Karāha end there is no
    /// fiqh-correct Duha start either — or Dhuhr can't be resolved to an
    /// absolute `Date`.
    static func resolve(
        now: Date,
        todayTimes: AdjustedPrayerTimes,
        sunriseKarahaWindow: QiratTimeResolver.ApproximateWindow?,
        preDhuhrKarahaWindow: QiratTimeResolver.ApproximateWindow?,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Window? {
        guard let sunriseKarahaWindow else { return nil }

        var locationCalendar = calendar
        locationCalendar.timeZone = TimeZone(identifier: todayTimes.times.timezone) ?? .current
        let today = locationCalendar.startOfDay(for: now)

        let shuruk = PrayerTimeAdjuster.date(
            forAdjusted: .init(value: todayTimes.times.shuruk, dayOffset: todayTimes.dayOffsets.shuruk),
            base: today,
            calendar: locationCalendar
        )

        guard let dhuhr = PrayerTimeAdjuster.date(
            forAdjusted: .init(value: todayTimes.times.dhuhr, dayOffset: todayTimes.dayOffsets.dhuhr),
            base: today,
            calendar: locationCalendar
        ) else { return nil }

        return window(
            sunriseKarahaEnd: sunriseKarahaWindow.end,
            shuruk: shuruk,
            dhuhr: dhuhr,
            preDhuhrKarahaStart: preDhuhrKarahaWindow?.start
        )
    }
}
