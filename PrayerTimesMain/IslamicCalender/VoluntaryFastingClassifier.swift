import Foundation

/// Which of the app's three recognized voluntary-fasting occasions a given
/// calendar day matches. A day can match more than one at once (e.g. a
/// Monday that's also a White Day) — callers combine matches into a single
/// notification rather than sending one per occasion (see
/// `NotificationScheduler.fastingCandidates`).
struct VoluntaryFastingOccasions: OptionSet {
    let rawValue: Int

    static let monday = VoluntaryFastingOccasions(rawValue: 1 << 0)
    static let thursday = VoluntaryFastingOccasions(rawValue: 1 << 1)
    /// The 13th, 14th, or 15th Hijri day of any month ("Ayyam al-Beed").
    static let whiteDay = VoluntaryFastingOccasions(rawValue: 1 << 2)

    /// German label for a single occasion, for building the notification
    /// text and the settings summary.
    var displayLabel: String {
        var parts: [String] = []
        if contains(.monday) { parts.append("Montag") }
        if contains(.thursday) { parts.append("Donnerstag") }
        if contains(.whiteDay) { parts.append("Weißer Tag") }

        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) und \(parts[1])"
        default: return "\(parts.dropLast().joined(separator: ", ")) und \(parts.last!)"
        }
    }
}

/// Single source of truth for "is this Gregorian day one of the app's three
/// recognized voluntary-fasting occasions" (Monday, Thursday, the Islamic
/// calendar's White Days) and "is voluntary fasting religiously
/// inappropriate on this day" (all of Ramadan, since the obligatory fast
/// already covers it; Eid al-Fitr and Eid al-Adha, on which fasting is
/// forbidden by consensus; and the three days of Tashriq — 11th-13th
/// Dhu al-Hijjah — which immediately follow Eid al-Adha and on which
/// fasting is likewise forbidden).
///
/// Extracted from `IslamicCalendarDayCell`'s own Monday/Thursday/White-Day
/// check (previously used there only for the blue "Sunnah fast day" text
/// color) so the notification scheduler classifies days exactly the same
/// way the calendar tab already highlights them — never a second,
/// independently drifting definition.
///
/// The exclusion rule intentionally does *not* special-case the narrow
/// classical exception allowing some Hajj pilgrims to fast during Tashriq
/// (only when they couldn't find a sacrificial animal) — this app has no
/// way to know a user's pilgrimage/sacrifice status, so it always suppresses
/// voluntary-fasting reminders on those days rather than guessing.
enum VoluntaryFastingClassifier {
    /// - Parameters:
    ///   - date: a `Date` representing local midnight of the calendar day
    ///     being classified, already resolved in whichever timezone the
    ///     caller cares about (e.g. the configured prayer location's own
    ///     timezone, via `PrayerMomentResolver.dayStart`). This function
    ///     performs no timezone conversion itself — it only reads
    ///     day/month/weekday components from the calendars it's given.
    ///   - gregorianCalendar: must have its `timeZone` set to match `date`'s
    ///     intended timezone.
    ///   - hijriCalendar: same timezone requirement; use
    ///     `HijriDateFormatting.calendar(timeZone:)` so the Hijri day/month
    ///     numbers agree with the rest of the app (White-Days highlighting,
    ///     Home/widget Hijri display, holiday classification).
    static func occasions(
        for date: Date,
        gregorianCalendar: Calendar,
        hijriCalendar: Calendar
    ) -> VoluntaryFastingOccasions {
        var result: VoluntaryFastingOccasions = []

        let weekday = gregorianCalendar.component(.weekday, from: date)
        if weekday == 2 { result.insert(.monday) }
        if weekday == 5 { result.insert(.thursday) }

        let hijriDay = hijriCalendar.component(.day, from: date)
        if hijriDay == 13 || hijriDay == 14 || hijriDay == 15 {
            result.insert(.whiteDay)
        }

        return result
    }

    /// True when a voluntary-fasting reminder would be religiously wrong on
    /// `date`, regardless of which occasion(s) `occasions(for:...)`
    /// otherwise matched — see the type-level doc comment for the exact
    /// rule and its scope.
    static func isExcludedFromVoluntaryFasting(date: Date, hijriCalendar: Calendar) -> Bool {
        let components = hijriCalendar.dateComponents([.day, .month], from: date)
        guard let day = components.day, let month = components.month else { return false }

        let isRamadan = month == 9
        let isEidAlFitr = month == 10 && day == 1
        let isEidAlAdha = month == 12 && day == 10
        let isTashriq = month == 12 && (day == 11 || day == 12 || day == 13)

        return isRamadan || isEidAlFitr || isEidAlAdha || isTashriq
    }
}
