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

    func asPrayerSettings(for date: Date = Date()) -> PrayerSettings {
        PrayerSettings(
            address: address,
            location: location,
            date: date,
            method: method
        )
    }
}
