import Foundation

/// The Karāha that begins once Islamic midnight passes without Isha having
/// been prayed yet: from the midpoint of Maghrib (one day) and Fajr (the
/// following day) until that following Fajr. Isha's own valid time still
/// runs all the way to Fajr — this never claims otherwise — but delaying
/// it past the midpoint is traditionally discouraged, mirroring
/// `LastThirdOfNightCalculator`'s exact night-span arithmetic with a
/// different fraction (the midpoint, not the final third).
///
/// Deliberately pure and Date-only — no timezone/cache lookups here,
/// that's `IshaMidnightKarahaResolver`'s job. Given two already-resolved
/// absolute instants (personal minute adjustments already applied, each
/// already anchored to the correct calendar day and location timezone via
/// `PrayerTimeAdjuster`), this only does the arithmetic.
nonisolated enum IshaMidnightKarahaCalculator {
    struct Window: Equatable {
        let start: Date
        let end: Date
    }

    /// - Parameters:
    ///   - maghrib: Maghrib of the night's first day.
    ///   - followingFajr: Fajr of the *next* calendar day.
    /// - Returns: `nil` if `followingFajr` is not strictly after `maghrib`
    ///   — never fabricates a window from malformed input.
    static func window(maghrib: Date, followingFajr: Date) -> Window? {
        guard followingFajr > maghrib else { return nil }
        let midpoint = maghrib.addingTimeInterval(followingFajr.timeIntervalSince(maghrib) / 2)
        return Window(start: midpoint, end: followingFajr)
    }
}
