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

    /// AlAdhan occasionally lists a differently-titled entry (e.g. a
    /// regional "Urs" or "Birth of …"/"Birthday …" observance) under the
    /// *exact* same Hijri (day, month) as one of the 8 curated holidays —
    /// a genuine date collision, not a mismatch. Titles containing these
    /// keywords are excluded unconditionally, even in that exact
    /// collision: the app never shows them regardless of what else falls
    /// on the same day.
    private static let excludedTitleKeywords = ["urs", "birth"]

    private static func hasExcludedTitle(_ specialDay: IslamicSpecialDay) -> Bool {
        let normalized = specialDay.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return excludedTitleKeywords.contains { normalized.contains($0) }
    }

    static func isMajorHoliday(_ specialDay: IslamicSpecialDay, hijriCalendar: Calendar) -> Bool {
        guard !hasExcludedTitle(specialDay) else { return false }
        guard let key = hijriHolidayKey(for: specialDay, hijriCalendar: hijriCalendar) else {
            return false
        }
        return majorHolidayKeys.contains(key)
    }

    static func majorHoliday(for specialDay: IslamicSpecialDay, hijriCalendar: Calendar) -> MajorIslamicHoliday? {
        guard !hasExcludedTitle(specialDay) else { return nil }
        guard let key = hijriHolidayKey(for: specialDay, hijriCalendar: hijriCalendar) else {
            return nil
        }
        return MajorIslamicHoliday.allCases.first { $0.hijriKey == key }
    }

    /// A stable identity for a special day, independent of its source
    /// (AlAdhan API, a locally-synthesized entry like the user's own
    /// Zakat-due-date occurrence, …). Built from the event's *category*
    /// (one of the 8 curated `MajorIslamicHoliday` cases, or a
    /// normalized-title fallback for anything else — e.g. the synthetic
    /// Zakat entry), its Hijri date, its concrete Gregorian day, and its
    /// normalized title — deliberately never the title alone, so two
    /// genuinely different events that happen to land on the same day are
    /// never collapsed into one.
    struct SpecialDayDedupeKey: Hashable {
        let category: String
        let hijriDay: String
        let hijriMonth: String
        let hijriYear: String
        let gregorianDayStart: TimeInterval
        let normalizedTitle: String
    }

    static func dedupeKey(for specialDay: IslamicSpecialDay, hijriCalendar: Calendar) -> SpecialDayDedupeKey {
        let category = majorHoliday(for: specialDay, hijriCalendar: hijriCalendar)?.rawValue
            ?? specialDay.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = .autoupdatingCurrent

        return SpecialDayDedupeKey(
            category: category,
            hijriDay: specialDay.hijriDay,
            hijriMonth: specialDay.hijriMonth,
            hijriYear: specialDay.hijriYear,
            gregorianDayStart: gregorianCalendar.startOfDay(for: specialDay.sortDate).timeIntervalSince1970,
            normalizedTitle: specialDay.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        )
    }

    /// Centrally removes exact duplicates — same category, same Hijri
    /// date, same Gregorian day, same normalized title — and returns the
    /// result in chronological order (ties broken by title, for a fully
    /// deterministic order regardless of input order). The single place
    /// every consumer of a mixed special-day list (the calendar grid, the
    /// day sheet, the "Besondere Tage" overview, the holiday-notification
    /// scheduler) goes through — directly or via `filterRelevant`, which
    /// calls this too — so none of them can silently diverge on what
    /// counts as "the same" special day. Keeps the first-sorted entry for
    /// any given key; never merges two entries that differ in category,
    /// date, or title, even if they land on the same day.
    static func deduplicatedAndSorted(_ days: [IslamicSpecialDay], hijriCalendar: Calendar) -> [IslamicSpecialDay] {
        let sorted = days.sorted {
            $0.sortDate != $1.sortDate ? $0.sortDate < $1.sortDate : $0.title < $1.title
        }

        var seen = Set<SpecialDayDedupeKey>()
        return sorted.filter { seen.insert(dedupeKey(for: $0, hijriCalendar: hijriCalendar)).inserted }
    }

    /// The single, central filter for "which AlAdhan special days may this
    /// app ever keep": only entries matching one of the 8 curated
    /// `MajorIslamicHoliday` cases survive, and exact duplicates (see
    /// `deduplicatedAndSorted`) are removed — e.g. AlAdhan occasionally
    /// reporting the same holiday twice in one response, or a cache
    /// written before this dedup step existed. Everything else — "Urs of
    /// …", "Birth of …"/"Birthday …" and any other personal/regional
    /// observance AlAdhan happens to report — is dropped here too.
    ///
    /// Both `SharedIslamicCalendarStore` (before every persistent write,
    /// and self-healing already-persisted data on every read, via
    /// `loadYearMigratingIfNeeded` below) and `IslamicCalendarViewModel`
    /// (right after a fresh network fetch, so the in-memory `specialDays`
    /// driving the UI is never briefly unfiltered/undeduped either) call
    /// this — same rule, multiple enforcement points, so no call site can
    /// accidentally let an irrelevant or duplicate event through by
    /// forgetting to filter.
    static func filterRelevant(_ days: [IslamicSpecialDay], hijriCalendar: Calendar) -> [IslamicSpecialDay] {
        let relevant = days.filter { isMajorHoliday($0, hijriCalendar: hijriCalendar) }
        return deduplicatedAndSorted(relevant, hijriCalendar: hijriCalendar)
    }

    /// Reads `year` from `store` and — if it still contains any entry that
    /// isn't one of the curated holidays (i.e. it predates this filter, or
    /// was written by an older app version) — immediately re-persists the
    /// cleaned-up version, so this migration runs at most once per stale
    /// cache and purely offline, no network request.
    ///
    /// `SharedIslamicCalendarStore` can't do this filtering itself: it's
    /// compiled into the widget extension target too, which doesn't
    /// include this file. Every read of a cached year must go through this
    /// helper instead of calling `store.loadYear` directly, so a cache
    /// written before this filter existed gets cleaned the first time the
    /// (main-app-only) view model or notification scheduler touches it —
    /// not just filtered transiently for display.
    ///
    /// Returns `nil` exactly when the store has nothing cached for this
    /// year — never conflated with "present but fully filtered out",
    /// which returns an empty array.
    static func loadYearMigratingIfNeeded(
        _ year: Int,
        store: SharedIslamicCalendarStore,
        hijriCalendar: Calendar
    ) -> [IslamicSpecialDay]? {
        guard let cached = store.loadYear(year) else { return nil }

        let relevant = filterRelevant(cached, hijriCalendar: hijriCalendar)
        if relevant.count != cached.count {
            store.saveYear(year, days: relevant)
        }
        return relevant
    }
}
