import Foundation

/// The single, shared source for Hijri display text used by the Home
/// screen, the widget and the Islamic-calendar tab: `Calendar(identifier:
/// .islamicUmmAlQura)`, computed locally from the Gregorian date. Before
/// this existed, the Home screen and the widget instead displayed the Hijri
/// date/day embedded in the AlAdhan API response (`PrayerTimes.hijriDate`),
/// which can disagree with Umm-al-Qura by a day, while the calendar tab
/// already computed Umm-al-Qura locally — so the same Gregorian day could
/// show two different Hijri dates depending on which screen you were on.
/// The prayer-calculation method itself stays independent of this; only
/// *display* and calendar-based rules (grid, headers, day sheet, widget,
/// White Days, holiday filtering) go through here.
enum HijriDateFormatting {
    /// - Parameter timeZone: defaults to the device's own timezone, exactly
    ///   as every existing call site relies on. Pass a specific location's
    ///   timezone (e.g. a cached prayer day's `PrayerTimes.timezone`)
    ///   instead when a day-boundary decision must follow *that* place's
    ///   calendar day rather than the device's — e.g. the voluntary-fasting
    ///   White-Days check, which must not misclassify a day right around
    ///   local midnight just because the device happens to sit in a
    ///   different timezone than the configured prayer location.
    static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = timeZone
        return calendar
    }

    /// Long localized text, e.g. "5. Ramadan 1447".
    static func displayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
        return formatter.string(from: date)
    }

    /// Just the Hijri day-of-month, e.g. "5" — matches what the calendar
    /// grid cell shows for the same Gregorian date.
    static func dayText(for date: Date) -> String {
        String(calendar().component(.day, from: date))
    }

    /// Day and month number (for compact widget headers that abbreviate the
    /// month name themselves).
    static func dayAndMonth(for date: Date) -> (day: Int, month: Int) {
        let components = calendar().dateComponents([.day, .month], from: date)
        return (components.day ?? 0, components.month ?? 0)
    }
}
