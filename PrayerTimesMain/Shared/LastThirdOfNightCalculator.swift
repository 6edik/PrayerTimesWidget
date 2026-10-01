import Foundation

/// The last third of the night: from Maghrib of one day until Fajr of the
/// following day, the final third of that full duration.
///
/// Deliberately pure and Date-only — no timezone/cache lookups here, that's
/// `LastThirdOfNightResolver`'s job. Given two already-resolved absolute
/// instants (personal minute adjustments already applied, each already
/// anchored to the correct calendar day and location timezone via
/// `PrayerTimeAdjuster`), this only does the arithmetic.
nonisolated enum LastThirdOfNightCalculator {
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
        let nightDuration = followingFajr.timeIntervalSince(maghrib)
        let start = followingFajr.addingTimeInterval(-nightDuration / 3)
        return Window(start: start, end: followingFajr)
    }
}
