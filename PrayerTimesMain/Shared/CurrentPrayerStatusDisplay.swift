import Foundation

/// Shared German labels for `CurrentPrayerStatusCalculator.Kind` — used by
/// both the Gebetszeiten page's "Aktueller Status" section and the widget,
/// so the two can never drift apart on wording. Icon mapping lives
/// separately in `PrayerStatusIcon`. Presentation-only: carries no
/// timing/calculation logic of its own.
nonisolated enum CurrentPrayerStatusDisplay {
    /// `dhuhrTitle` is passed in rather than recomputed here so every
    /// caller keeps using the one already-resolved Jum'ah/Dhuhr label
    /// (`PrayerDisplayNaming.dhuhrLabel`) for the correct calendar day.
    /// All four Karāha kinds deliberately share the bare "Karāha" label,
    /// with no further qualifier — knowing it's a Karāha window is enough.
    static func label(for kind: CurrentPrayerStatusCalculator.Kind, dhuhrTitle: String) -> String {
        switch kind {
        case .fajr: return "Fajr"
        case .sunriseKaraha, .preDhuhrKaraha, .preMaghribKaraha, .postMidnightKaraha: return "Karāha"
        case .duha: return "Duha"
        case .dhuhr: return dhuhrTitle
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        case .lastThirdOfNight: return "Letztes Drittel"
        }
    }

    /// `true` only for the five canonical obligatory prayers. Drives
    /// whether a status is allowed to use the app's "current obligatory
    /// prayer" chrome (the orange tile highlight on the Gebetszeiten page)
    /// — Karāha, Duha and the last third of the night must never be
    /// styled as if they were an obligatory prayer.
    static func isObligatory(_ kind: CurrentPrayerStatusCalculator.Kind) -> Bool {
        switch kind {
        case .fajr, .dhuhr, .asr, .maghrib, .isha: return true
        case .sunriseKaraha, .duha, .preDhuhrKaraha, .preMaghribKaraha, .postMidnightKaraha, .lastThirdOfNight: return false
        }
    }

    /// `true` for all four Karāha kinds. A Karāha window is a caution
    /// period, not a voluntary-prayer opportunity — it must never be
    /// labeled "freiwillig" the way Duha or the last third of the night
    /// are.
    static func isKaraha(_ kind: CurrentPrayerStatusCalculator.Kind) -> Bool {
        switch kind {
        case .sunriseKaraha, .preDhuhrKaraha, .preMaghribKaraha, .postMidnightKaraha: return true
        case .fajr, .duha, .dhuhr, .asr, .maghrib, .isha, .lastThirdOfNight: return false
        }
    }
}
