import Foundation

struct AutoPrayerSettings: Codable, Equatable {
    var address: String = "Gelsenkirchen, DE"
    // Optional so settings saved before this field existed still decode
    // (via the compiler-synthesized `decodeIfPresent`) instead of falling
    // back to the whole-struct default — a legacy address string keeps
    // working on the address-based endpoints until the user re-confirms a
    // location (city list or GPS), which attaches real coordinates.
    //
    // Defaults to nil here — deliberately *not* `.defaultGelsenkirchen` —
    // so that constructing settings with a custom `address` but no
    // `location` argument (as every call site that only cares about the
    // address does) can never silently end up with a *mismatched*
    // Gelsenkirchen coordinate paired with a different address string. The
    // one true "app default for a never-configured install" is assembled
    // explicitly, consistently, in `SharedPrayerSettingsStore.loadAutoSettings()`.
    var location: PrayerLocation? = nil
    var method: PrayerCalculationMethod = .ditib
    var adjustments: PrayerAdjustments = .zero

    // Optional so settings saved before this field existed still decode
    // (via the compiler-synthesized `decodeIfPresent`) with the default
    // orientation value, instead of a decode failure that would reset the
    // whole struct. `nil` means "use the default" — never persisted as a
    // guessed concrete number. This is never a computed or fiqh-exact
    // value; see `QiratTimeResolver`'s doc comment for why the late-
    // Maghrib Kerahet window this controls is only ever an approximation.
    var lateKerahetOffsetMinutesOverride: Int? = nil

    var lateKerahetOffsetMinutes: Int {
        lateKerahetOffsetMinutesOverride ?? QiratTimeResolver.defaultLateKerahetOffsetMinutes
    }

    // Same backward-compatible optionality pattern as
    // `lateKerahetOffsetMinutesOverride` above, for the separate
    // Sonnenaufgangs-Karāha approximation (Shuruk until approximately
    // Shuruk + this many minutes — never Fajr-anchored).
    var sunriseKarahaOffsetMinutesOverride: Int? = nil

    var sunriseKarahaOffsetMinutes: Int {
        sunriseKarahaOffsetMinutesOverride ?? QiratTimeResolver.defaultSunriseKarahaOffsetMinutes
    }

    func asPrayerSettings(for date: Date = Date()) -> PrayerSettings {
        PrayerSettings(
            address: address,
            location: location,
            date: date,
            method: method
        )
    }
}
