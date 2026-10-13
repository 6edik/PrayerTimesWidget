import Foundation

/// The single, central SF Symbol mapping for every prayer-related icon in
/// the app — the Gebetszeiten page's individual prayer rows, its
/// "Aktueller Status" section, and every widget family that shows a
/// prayer/status icon. No view computes its own icon mapping; they all
/// call into this type, so the same state can never render a different
/// symbol in two places.
///
/// Every name here was verified to actually exist in the SDK's SF Symbols
/// catalog (via `UIImage(systemName:) != nil`) before being chosen —
/// never a guessed or invented symbol name.
nonisolated enum PrayerStatusIcon {
    /// For one of the six canonical Gebetszeiten-page row names
    /// (`PrayerWindowResolver`'s/`PrayerTimesMapper`'s "Fajr", "Shuruk",
    /// "Dhuhr", "Asr", "Maghrib", "Isha" — never the Jum'ah-relabeled
    /// display name, which doesn't affect which prayer this is). Falls
    /// back to a neutral clock glyph for any other value rather than a
    /// fabricated guess.
    static func symbolName(forCanonicalRow canonicalName: String) -> String {
        switch canonicalName {
        case "Fajr": return "sunrise"
        case "Shuruk": return "sunrise.fill"
        case "Dhuhr": return "sun.max.fill"
        case "Asr": return "sun.min.fill"
        case "Maghrib": return "sunset.fill"
        case "Isha": return "moon.stars.fill"
        default: return "clock.fill"
        }
    }

    /// For a `CurrentPrayerStatusCalculator.Kind` — the "Aktueller
    /// Status" section and every widget's own current-status icon. The
    /// five obligatory kinds reuse exactly the same symbol as their
    /// canonical row above. All four Karāha kinds deliberately share one
    /// consistent symbol (`sun.haze.fill`) — the same underlying
    /// phenomenon, recognizable at a glance regardless of which of the
    /// four is active (including the post-midnight Isha Karāha, even
    /// though it falls at night). Duha and the last third of the night
    /// each get their own distinct symbol instead of borrowing Dhuhr's or
    /// Isha's, so no two different active states ever render the
    /// identical icon.
    static func symbolName(for kind: CurrentPrayerStatusCalculator.Kind) -> String {
        switch kind {
        case .fajr: return symbolName(forCanonicalRow: "Fajr")
        case .dhuhr: return symbolName(forCanonicalRow: "Dhuhr")
        case .asr: return symbolName(forCanonicalRow: "Asr")
        case .maghrib: return symbolName(forCanonicalRow: "Maghrib")
        case .isha: return symbolName(forCanonicalRow: "Isha")
        case .sunriseKaraha, .preDhuhrKaraha, .preMaghribKaraha, .postMidnightKaraha: return "sun.haze.fill"
        case .duha: return "sun.and.horizon.fill"
        case .lastThirdOfNight: return "moon.stars"
        }
    }
}
