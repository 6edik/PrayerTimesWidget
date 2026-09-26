import Foundation

/// The 8 major Islamic holidays shown in the app's "Feiertage"-overview
/// (`IslamicHolidayOverviewSheet`), each identified by its Hijri (day,
/// month) — the single source of truth for both that overview and the
/// prayer/holiday notification scheduler, so "which holidays exist" never
/// drifts between the two.
enum MajorIslamicHoliday: String, CaseIterable, Codable, Identifiable {
    case hajjDay
    case dayOfArafah
    case eidAlAdha
    case islamicNewYear
    case ashura
    case israMiraj
    case ramadanStart
    case eidAlFitr

    var id: String { rawValue }

    var hijriKey: IslamicHolidayClassifier.HijriHolidayKey {
        switch self {
        case .hajjDay: return .init(day: 8, month: 12)
        case .dayOfArafah: return .init(day: 9, month: 12)
        case .eidAlAdha: return .init(day: 10, month: 12)
        case .islamicNewYear: return .init(day: 1, month: 1)
        case .ashura: return .init(day: 10, month: 1)
        case .israMiraj: return .init(day: 27, month: 7)
        case .ramadanStart: return .init(day: 1, month: 9)
        case .eidAlFitr: return .init(day: 1, month: 10)
        }
    }

    var displayName: String {
        switch self {
        case .hajjDay: return "Tag der Hadsch"
        case .dayOfArafah: return "Tag von Arafah"
        case .eidAlAdha: return "Eid al-Adha"
        case .islamicNewYear: return "Islamisches Neujahr"
        case .ashura: return "Ashura"
        case .israMiraj: return "Isra' und Mi'raj"
        case .ramadanStart: return "Ramadan-Beginn"
        case .eidAlFitr: return "Eid al-Fitr"
        }
    }
}

/// Shared classification logic, extracted from `IslamicCalendarViewModel` so
/// the notification scheduler can decide "is this cached `IslamicSpecialDay`
/// one of the 8 major holidays" the exact same way the Feiertage-overview
/// does — without duplicating (and risking diverging from) that logic.
enum IslamicHolidayClassifier {
    struct HijriHolidayKey: Hashable {
        let day: Int
        let month: Int
    }

    static let majorHolidayKeys: Set<HijriHolidayKey> = Set(MajorIslamicHoliday.allCases.map(\.hijriKey))

    /// Prefer the Hijri day/month AlAdhan itself reported for this holiday.
    /// Re-deriving day/month from `sortDate` via a *different* calendar
    /// (Umm-al-Qura) risks disagreeing with AlAdhan by a day for
    /// moon-sighting-dependent dates (Ramadan start/end, Eid al-Adha,
    /// Ashura), which would silently drop the holiday out of every
    /// `majorHolidayKeys` match even though AlAdhan flagged it correctly.
    static func hijriHolidayKey(for specialDay: IslamicSpecialDay, hijriCalendar: Calendar) -> HijriHolidayKey? {
        if let month = specialDay.hijriMonthNumber, let day = Int(specialDay.hijriDay) {
            return HijriHolidayKey(day: day, month: month)
        }

        // Fallback only for cache entries saved before `hijriMonthNumber`
        // existed; they don't have AlAdhan's own month number persisted, so
        // fall back to the previous best-effort re-derivation until the
        // cache is refreshed.
        let components = hijriCalendar.dateComponents([.day, .month], from: specialDay.sortDate)

        guard let day = components.day, let month = components.month else {
            return nil
        }

        return HijriHolidayKey(day: day, month: month)
    }

    static func isMajorHoliday(_ specialDay: IslamicSpecialDay, hijriCalendar: Calendar) -> Bool {
        guard let key = hijriHolidayKey(for: specialDay, hijriCalendar: hijriCalendar) else {
            return false
        }
        return majorHolidayKeys.contains(key)
    }

    static func majorHoliday(for specialDay: IslamicSpecialDay, hijriCalendar: Calendar) -> MajorIslamicHoliday? {
        guard let key = hijriHolidayKey(for: specialDay, hijriCalendar: hijriCalendar) else {
            return nil
        }
        return MajorIslamicHoliday.allCases.first { $0.hijriKey == key }
    }
}
