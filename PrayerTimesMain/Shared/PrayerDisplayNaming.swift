import Foundation

/// Friday's Dhuhr is commonly called "Jum'ah". This changes only the
/// user-facing label — never the internal "Dhuhr" identifier, the AlAdhan
/// API parameter, any cache key, or the computed clock time itself.
///
/// Weekday is always determined in the *prayer location's* own timezone
/// (an IANA identifier, e.g. `PrayerTimes.timezone`) — never the device's —
/// so a location in a different timezone than the device is judged by its
/// own calendar day, exactly as the spec requires.
nonisolated enum PrayerDisplayNaming {
    static func isJumuahDhuhr(date: Date, timezoneIdentifier: String) -> Bool {
        guard let zone = TimeZone(identifier: timezoneIdentifier) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // Gregorian calendar weekday: Sunday = 1 ... Friday = 6.
        return calendar.component(.weekday, from: date) == 6
    }

    /// "Jum'ah" on Friday, "Dhuhr" every other day.
    static func dhuhrLabel(date: Date, timezoneIdentifier: String) -> String {
        isJumuahDhuhr(date: date, timezoneIdentifier: timezoneIdentifier) ? "Jum'ah" : "Dhuhr"
    }

    /// "JUM" on Friday, "DHR" every other day — for the same tight
    /// abbreviated slots the widget already uses for the other prayers
    /// (FJR/SRK/ASR/MGB/ISH).
    static func dhuhrShortLabel(date: Date, timezoneIdentifier: String) -> String {
        isJumuahDhuhr(date: date, timezoneIdentifier: timezoneIdentifier) ? "JUM" : "DHR"
    }

    /// Short, honest caption shown only next to a "Jum'ah"-labeled row: the
    /// displayed time is still just the calculated Dhuhr time, never a
    /// specific mosque's actual Khutba/Jum'ah start time.
    static let khutbaClarificationCaption =
        "Berechnete Dhuhr-Zeit — nicht die Khutba-/Jum'ah-Zeit einer bestimmten Moschee."
}
