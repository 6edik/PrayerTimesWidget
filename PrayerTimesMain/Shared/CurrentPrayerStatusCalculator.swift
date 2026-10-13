import Foundation

/// Centralizes "what relevant time window is the user currently in" across
/// the whole app — the single source of truth shared by the Gebetszeiten
/// page's "Aktueller Status" section and every widget family that shows a
/// current/countdown status, so they can never disagree about which state
/// is active, its progress, or its remaining time.
///
/// States are evaluated for a single instant from already-resolved,
/// already-adjusted windows (personal minute adjustments already applied
/// exactly once by the caller, same convention as `PrayerWindowResolver`/
/// `DuhaCalculator`/`LastThirdOfNightResolver`) — this performs no lookups
/// of its own, and fabricates nothing when a required window is `nil`.
nonisolated enum CurrentPrayerStatusCalculator {
    enum Kind: Equatable {
        case fajr
        case sunriseKaraha
        case duha
        case preDhuhrKaraha
        case dhuhr
        case asr
        case preMaghribKaraha
        case maghrib
        case isha
        /// Isha delayed past Islamic midnight (the midpoint between
        /// Maghrib and the following Fajr) — see
        /// `IshaMidnightKarahaResolver`. Only ever surfaces during an
        /// active Isha window, and only until `lastThirdOfNight` takes
        /// over as the more specific state.
        case postMidnightKaraha
        case lastThirdOfNight
    }

    struct Status: Equatable {
        let kind: Kind
        let start: Date
        let end: Date
        let elapsed: TimeInterval
        let remaining: TimeInterval
        /// Clamped 0...1 fraction of `start...end` elapsed at the instant
        /// this `Status` was resolved for.
        let progress: Double
        /// A second, concurrently-active state worth surfacing alongside
        /// `kind` as a compact marking — `.lastThirdOfNight` or
        /// `.postMidnightKaraha` overlapping an active Isha window, or
        /// `.preMaghribKaraha` overlapping an active Asr window — never a
        /// replacement for `kind` itself, and never equal to it.
        let additionalKind: Kind?
    }

    /// Precedence when more than one state is active at once, highest
    /// first:
    /// 1. The sunrise Karāha and the Karāha vor Dhuhr — both sit inside
    ///    the Shuruk-to-Dhuhr gap, where no obligatory prayer is ever
    ///    active, so there's nothing for them to interrupt.
    /// 2. The current obligatory prayer (Fajr/Dhuhr/Asr/Maghrib/Isha).
    ///    The Karāha vor Maghrib never promotes itself above Asr here —
    ///    it only ever rides along as `additionalKind`, exactly like the
    ///    last third of the night (or, before that starts, the
    ///    post-midnight Isha Karāha) rides along with Isha. Asr's own
    ///    row/highlight elsewhere is unaffected either way.
    /// 3. Duha.
    /// 4. The last third of the night / the Karāha vor Maghrib / the
    ///    post-midnight Isha Karāha, as a standalone main status — only
    ///    reached if the obligatory window
    ///    itself couldn't be resolved at all (never double-counted with
    ///    step 2's `additionalKind`).
    ///
    /// - Parameters:
    ///   - window: the current/next obligatory-prayer window (`nil` for
    ///     "Shuruk" falls through to the Karāha/Duha checks below, exactly
    ///     like the rest of the app never treats sunrise as an obligatory
    ///     prayer).
    ///   - duhaWindow: already resolved via `DuhaCalculator`.
    ///   - sunriseKarahaWindow: already resolved via `QiratTimeResolver`.
    ///   - preDhuhrKarahaWindow: already resolved via `QiratTimeResolver`.
    ///   - preMaghribKarahaWindow: already resolved via `QiratTimeResolver`
    ///     (its `lateMaghribKaraha`) — reused as-is, never a second,
    ///     independently computed window.
    ///   - lastThirdWindow: already resolved via `LastThirdOfNightResolver`.
    ///   - postMidnightKarahaWindow: already resolved via
    ///     `IshaMidnightKarahaResolver`.
    /// - Returns: `nil` whenever none of the above windows are available or
    ///   active at `now` — never a fabricated status.
    static func resolve(
        now: Date,
        window: PrayerWindowResolver.Window?,
        duhaWindow: DuhaCalculator.Window?,
        sunriseKarahaWindow: QiratTimeResolver.ApproximateWindow?,
        preDhuhrKarahaWindow: QiratTimeResolver.ApproximateWindow?,
        preMaghribKarahaWindow: QiratTimeResolver.ApproximateWindow?,
        lastThirdWindow: LastThirdOfNightResolver.ResolvedWindow?,
        postMidnightKarahaWindow: IshaMidnightKarahaResolver.ResolvedWindow?
    ) -> Status? {
        func isActive(_ karahaWindow: QiratTimeResolver.ApproximateWindow?) -> Bool {
            karahaWindow.map { now >= $0.start && now < $0.end } ?? false
        }

        let lastThirdActive = lastThirdWindow.map { now >= $0.start && now < $0.end } ?? false
        let preMaghribKarahaActive = isActive(preMaghribKarahaWindow)
        let postMidnightKarahaActive = postMidnightKarahaWindow.map { now >= $0.start && now < $0.end } ?? false

        func makeStatus(kind: Kind, start: Date, end: Date, additionalKind: Kind?) -> Status? {
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return nil }
            let elapsed = min(max(now.timeIntervalSince(start), 0), total)
            return Status(
                kind: kind,
                start: start,
                end: end,
                elapsed: elapsed,
                remaining: total - elapsed,
                progress: elapsed / total,
                additionalKind: additionalKind
            )
        }

        func activeKaraha(_ karahaWindow: QiratTimeResolver.ApproximateWindow?, kind: Kind) -> Status? {
            guard let karahaWindow, isActive(karahaWindow) else { return nil }
            return makeStatus(kind: kind, start: karahaWindow.start, end: karahaWindow.end, additionalKind: nil)
        }

        if let status = activeKaraha(sunriseKarahaWindow, kind: .sunriseKaraha) { return status }
        if let status = activeKaraha(preDhuhrKarahaWindow, kind: .preDhuhrKaraha) { return status }

        if let window, let obligatoryKind = obligatoryKind(for: window.currentName) {
            let additionalKind: Kind?
            if obligatoryKind == .isha, lastThirdActive {
                additionalKind = .lastThirdOfNight
            } else if obligatoryKind == .isha, postMidnightKarahaActive {
                // The last third always wins once it starts — it's the
                // more specific state, and (since the last third always
                // starts after the midpoint) it would otherwise never get
                // to show at all, this window being its superset.
                additionalKind = .postMidnightKaraha
            } else if obligatoryKind == .asr, preMaghribKarahaActive {
                additionalKind = .preMaghribKaraha
            } else {
                additionalKind = nil
            }
            return makeStatus(kind: obligatoryKind, start: window.start, end: window.end, additionalKind: additionalKind)
        }

        if let duhaWindow, now >= duhaWindow.start, now < duhaWindow.end {
            return makeStatus(kind: .duha, start: duhaWindow.start, end: duhaWindow.end, additionalKind: nil)
        }

        // Standalone fallbacks — only reached when the obligatory window
        // itself couldn't be resolved (so step 2 above never ran), never
        // double-counted with that step's `additionalKind`.
        if lastThirdActive, let lastThirdWindow {
            return makeStatus(kind: .lastThirdOfNight, start: lastThirdWindow.start, end: lastThirdWindow.end, additionalKind: nil)
        }

        if let status = activeKaraha(preMaghribKarahaWindow, kind: .preMaghribKaraha) { return status }

        if postMidnightKarahaActive, let postMidnightKarahaWindow {
            return makeStatus(kind: .postMidnightKaraha, start: postMidnightKarahaWindow.start, end: postMidnightKarahaWindow.end, additionalKind: nil)
        }

        return nil
    }

    /// `nil` for "Shuruk" — sunrise is never treated as an obligatory
    /// prayer window; the Karāha/Duha checks above handle that span.
    private static func obligatoryKind(for canonicalName: String) -> Kind? {
        switch canonicalName {
        case "Fajr": return .fajr
        case "Dhuhr": return .dhuhr
        case "Asr": return .asr
        case "Maghrib": return .maghrib
        case "Isha": return .isha
        default: return nil
        }
    }
}
