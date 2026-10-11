import Foundation

/// The Karāha-related time windows this app surfaces, kept structurally
/// separate because they rest on very different footing:
///
/// - **Sonnenaufgangs-Karāha** (`sunriseKaraha`): the particularly
///   problematic window begins exactly *at* sunrise (Shuruk) — never at
///   Fajr — and ends only approximately, `sunriseKarahaOffsetMinutes`
///   (loosely "15–20 Minuten") later. `start` is exact (Shuruk is a real
///   cached timestamp); `end` is an **approximation**, never claimed to be
///   an exact fiqh boundary.
///
/// - **The separate Ḥanafī restriction on *voluntary* prayer from Fajr
///   until sunrise** (`afterFajrVoluntaryRestriction`): both endpoints are
///   exact cached timestamps (Fajr, Shuruk). This is a *different* rule
///   from `sunriseKaraha` above and is never labeled "Karāha" or merged
///   into one window with it — the app surfaces no notification/widget
///   text for this window today; it exists in the model purely so the two
///   concepts stay explicitly distinct instead of being silently
///   conflated into one pauschal "verboten" window.
///
/// - **Karāha vor Dhuhr** (`preDhuhrKaraha`): a fixed number of minutes
///   immediately before Dhuhr's own start. Mirrors `lateMaghribKaraha`
///   below in every respect (fixed approximation, anchored at the *end*,
///   latitude-gated) but sits before Dhuhr instead of Maghrib. This is
///   what separates Duha's own end from Dhuhr's own start — Duha ends
///   exactly where this window begins, Dhuhr begins exactly where it ends
///   (see `DuhaCalculator`, which consumes this window's `start` as
///   Duha's `end` instead of using Dhuhr directly).
///
/// - **Karāha vor Maghrib** (`lateMaghribKaraha`): a fixed number of
///   minutes immediately before Maghrib. Deliberately an
///   **approximation**, never an exact fiqh boundary, and — importantly —
///   never "Asr until Maghrib": Asr's own valid prayer time correctly
///   extends all the way to Maghrib. Only imminently approaching Maghrib
///   is the problematic part, which is why this window is short and
///   anchored at the *end* (Maghrib), not at Asr's start. AlAdhan provides
///   no "sun turning yellow" astronomical timestamp, so there is no
///   reliable, location- and day-exact source for when this phase
///   actually begins — hence the fixed, user-adjustable approximation.
///
/// A fixed-minute approximation stops being a meaningful "moderate
/// region" estimate at extreme latitudes (twilight duration and day
/// length vary too drastically there), so `sunriseKaraha`,
/// `preDhuhrKaraha` and `lateMaghribKaraha` are all suppressed entirely —
/// never shown with a number that would be actively misleading —
/// whenever the configured location's latitude is unknown or outside
/// `maxPlausibleLatitudeForApproximation`. `afterFajrVoluntaryRestriction`
/// has no such restriction: both its endpoints are exact data, not a
/// fixed offset, so it stays valid at any latitude the underlying
/// prayer-time calculation itself supports.
///
/// All windows reuse `PrayerTimeAdjuster` — the same midnight-safe,
/// location-timezone-aware machinery the rest of the app already relies
/// on — so personal minute adjustments and DST are handled exactly like
/// every other computed prayer moment. The Maghrib-/Dhuhr-minute
/// adjustments are each applied exactly once (inside
/// `applyingAdjustmentsWithDayOffsets` below); each approximation offset
/// is only ever added/subtracted from that single already-adjusted
/// instant.
nonisolated enum QiratTimeResolver {
    struct ResolvedWindow: Equatable {
        let start: Date
        let end: Date
        let timezoneIdentifier: String
    }

    /// `offsetMinutes` records exactly how many minutes this particular
    /// instance used, so UI and tests stay explicit about the number
    /// actually applied instead of hiding it behind a plain
    /// `ResolvedWindow`.
    struct ApproximateWindow: Equatable {
        let start: Date
        let end: Date
        let timezoneIdentifier: String
        let offsetMinutes: Int
    }

    struct ResolvedWindows: Equatable {
        let sunriseKaraha: ApproximateWindow?
        let afterFajrVoluntaryRestriction: ResolvedWindow?
        let preDhuhrKaraha: ApproximateWindow?
        let lateMaghribKaraha: ApproximateWindow?

        static let none = ResolvedWindows(
            sunriseKaraha: nil,
            afterFajrVoluntaryRestriction: nil,
            preDhuhrKaraha: nil,
            lateMaghribKaraha: nil
        )
    }

    /// Default orientation value only — NOT a computed or fiqh-exact
    /// boundary. Loosely "15–20 Minuten nach Sonnenaufgang". See the
    /// type-level documentation above.
    nonisolated static let defaultSunriseKarahaOffsetMinutes = 20

    /// Default orientation value only — NOT a computed or fiqh-exact
    /// boundary. See the type-level documentation above. Deliberately much
    /// shorter than the sunset approximation — the window right around
    /// solar noon is traditionally understood as brief.
    nonisolated static let defaultPreDhuhrKarahaOffsetMinutes = 10

    /// Default orientation value only — NOT a computed or fiqh-exact
    /// boundary. See the type-level documentation above.
    nonisolated static let defaultLateKerahetOffsetMinutes = 45

    /// Beyond this absolute latitude, a fixed-minute approximation
    /// (`sunriseKaraha`, `preDhuhrKaraha`, or `lateMaghribKaraha`) stops
    /// being a meaningful "moderate region" estimate. See the type-level
    /// documentation above.
    ///
    /// Deliberately well above all of Germany/Central Europe (Sylt, the
    /// country's northernmost point, sits at ~55°N; Berlin at ~52.5°N) —
    /// this app's primary audience — while still excluding genuinely
    /// extreme locations where day/night length varies drastically
    /// (northern Scandinavia, Iceland, etc.), e.g. Tromsø at ~69.6°N.
    nonisolated static let maxPlausibleLatitudeForApproximation = 60.0

    /// `base` anchors which calendar day `times`' "HH:mm" strings belong
    /// to. Pass the actual local midnight of that day (in its own
    /// timezone, e.g. via `PrayerMomentResolver.dayStart`) when resolving
    /// an arbitrary cached day (see `NotificationScheduler.qiratCandidates`),
    /// or simply `now` when resolving "today" (see the `now:store:settings:`
    /// overload below) — both work identically because
    /// `PrayerTimeAdjuster.date` only ever reads the calendar day off
    /// `base`, never its time-of-day.
    ///
    /// - Parameter latitude: the configured location's latitude, used
    ///   only for the plausibility check above. `nil` (no confirmed
    ///   location) suppresses all three approximations the same way an
    ///   out-of-range latitude does — never a guessed location.
    static func windows(
        base: Date,
        times: PrayerTimes,
        adjustments: PrayerAdjustments,
        latitude: Double?,
        lateKerahetOffsetMinutes: Int = defaultLateKerahetOffsetMinutes,
        sunriseKarahaOffsetMinutes: Int = defaultSunriseKarahaOffsetMinutes,
        preDhuhrKarahaOffsetMinutes: Int = defaultPreDhuhrKarahaOffsetMinutes
    ) -> ResolvedWindows {
        let adjusted = times.applyingAdjustmentsWithDayOffsets(adjustments)

        var locationCalendar = Calendar(identifier: .gregorian)
        locationCalendar.timeZone = TimeZone(identifier: adjusted.times.timezone) ?? .current

        func moment(_ value: String, _ dayOffset: Int) -> Date? {
            PrayerTimeAdjuster.date(
                forAdjusted: .init(value: value, dayOffset: dayOffset),
                base: base,
                calendar: locationCalendar
            )
        }

        let fajr = moment(adjusted.times.fajr, adjusted.dayOffsets.fajr)
        let shuruk = moment(adjusted.times.shuruk, adjusted.dayOffsets.shuruk)
        let dhuhr = moment(adjusted.times.dhuhr, adjusted.dayOffsets.dhuhr)
        let maghrib = moment(adjusted.times.maghrib, adjusted.dayOffsets.maghrib)

        let isLatitudePlausible = latitude.map { abs($0) <= maxPlausibleLatitudeForApproximation } ?? false

        var sunriseKaraha: ApproximateWindow?
        if let shuruk, sunriseKarahaOffsetMinutes > 0, isLatitudePlausible {
            // `start` is the exact Shuruk instant; only `end` is an
            // approximation — never the reverse, and never anchored to
            // Fajr for this specific window type.
            let end = shuruk.addingTimeInterval(Double(sunriseKarahaOffsetMinutes) * 60)
            sunriseKaraha = ApproximateWindow(
                start: shuruk,
                end: end,
                timezoneIdentifier: adjusted.times.timezone,
                offsetMinutes: sunriseKarahaOffsetMinutes
            )
        }

        let afterFajrVoluntaryRestriction = QiratTimeCalculator.window(start: fajr, end: shuruk).map {
            ResolvedWindow(start: $0.start, end: $0.end, timezoneIdentifier: adjusted.times.timezone)
        }

        var preDhuhrKaraha: ApproximateWindow?
        if let dhuhr, preDhuhrKarahaOffsetMinutes > 0, isLatitudePlausible {
            // `dhuhr` already has the personal Dhuhr-minute adjustment
            // applied exactly once, above. Only ever subtract the
            // approximation offset from this single already-adjusted
            // instant — never re-apply `adjustments.dhuhr` a second time.
            let start = dhuhr.addingTimeInterval(-Double(preDhuhrKarahaOffsetMinutes) * 60)
            preDhuhrKaraha = ApproximateWindow(
                start: start,
                end: dhuhr,
                timezoneIdentifier: adjusted.times.timezone,
                offsetMinutes: preDhuhrKarahaOffsetMinutes
            )
        }

        var lateMaghribKaraha: ApproximateWindow?
        if let maghrib, lateKerahetOffsetMinutes > 0, isLatitudePlausible {
            // `maghrib` already has the personal Maghrib-minute adjustment
            // applied exactly once, above. Only ever subtract the
            // approximation offset from this single already-adjusted
            // instant — never re-apply `adjustments.maghrib` a second time.
            let start = maghrib.addingTimeInterval(-Double(lateKerahetOffsetMinutes) * 60)
            lateMaghribKaraha = ApproximateWindow(
                start: start,
                end: maghrib,
                timezoneIdentifier: adjusted.times.timezone,
                offsetMinutes: lateKerahetOffsetMinutes
            )
        }

        return ResolvedWindows(
            sunriseKaraha: sunriseKaraha,
            afterFajrVoluntaryRestriction: afterFajrVoluntaryRestriction,
            preDhuhrKaraha: preDhuhrKaraha,
            lateMaghribKaraha: lateMaghribKaraha
        )
    }

    /// Convenience for "today", loading directly from the shared cache and
    /// the currently configured location/adjustments/approximation offsets.
    /// Returns `.none` — never a fabricated window — if today isn't
    /// cached for the current settings.
    static func windows(
        now: Date = Date(),
        store: SharedPrayerTimesStore,
        settings: AutoPrayerSettings
    ) -> ResolvedWindows {
        guard let raw = store.load(for: now, settings: settings) else { return .none }
        return windows(
            base: now,
            times: raw,
            adjustments: settings.adjustments,
            latitude: settings.location?.coordinate.latitude,
            lateKerahetOffsetMinutes: settings.lateKerahetOffsetMinutes,
            sunriseKarahaOffsetMinutes: settings.sunriseKarahaOffsetMinutes,
            preDhuhrKarahaOffsetMinutes: settings.preDhuhrKarahaOffsetMinutes
        )
    }
}
