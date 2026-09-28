import Foundation

/// One-time, local-only migration for `AutoPrayerSettings` saved before
/// coordinates existed. Deliberately never makes a network request — only
/// the bundled `DE_cities.json` is consulted, per product decision (no
/// surprise network access right after an app update). An unambiguous
/// case-insensitive name match backfills the coordinate silently; anything
/// else leaves `location` untouched and flags that the user must
/// re-confirm the place explicitly via
/// `SharedPrayerSettingsStore.needsLocationConfirmation()`.
struct LegacyLocationMigrator {
    private let settingsStore: SharedPrayerSettingsStore
    private let timesStore: SharedPrayerTimesStore
    // Injectable so tests can supply a fixed city list instead of depending
    // on `Bundle.main` resolving `DE_cities.json` inside the test process.
    private let loadGermanCities: () async throws -> [CityItem]

    init(
        settingsStore: SharedPrayerSettingsStore = SharedPrayerSettingsStore(),
        timesStore: SharedPrayerTimesStore = SharedPrayerTimesStore(),
        loadGermanCities: @escaping () async throws -> [CityItem] = CityLoader.loadGermanCities
    ) {
        self.settingsStore = settingsStore
        self.timesStore = timesStore
        self.loadGermanCities = loadGermanCities
    }

    /// Runs the migration for whatever is currently saved. Safe to call
    /// repeatedly — a location that's already confirmed, or an address
    /// that's already been checked and flagged, is a cheap no-op.
    func migrateIfNeeded() async {
        var settings = settingsStore.loadAutoSettings()

        if let location = settings.location, location.coordinate.isPlausible {
            settingsStore.clearNeedsLocationConfirmation()
            return
        }

        // Already checked this exact address before — don't repeat the
        // (already-decided) lookup or re-clear a cache the user might have
        // already refreshed since.
        guard settingsStore.lastCheckedLegacyAddress() != settings.address else {
            return
        }

        settingsStore.setLastCheckedLegacyAddress(settings.address)

        guard let match = await uniqueGermanCityMatch(for: settings.address) else {
            settingsStore.setNeedsLocationConfirmation(true)
            timesStore.clear()
            return
        }

        settings.location = PrayerLocation(name: settings.address, coordinate: match, source: .confirmedPlace)
        settingsStore.saveAutoSettings(settings)
        settingsStore.clearNeedsLocationConfirmation()
        // The pre-migration cache (if any) was keyed by the normalized
        // address string, never by this newly-attached coordinate — it can
        // never be matched again, so clear it explicitly instead of
        // leaving it as unreachable, permanent clutter.
        timesStore.clear()
    }

    /// Splits `address` into "City, Country" (the shape this app has
    /// always saved), only attempts a local lookup for Germany (the only
    /// bundled list), and only returns a coordinate when exactly one city
    /// matches the name case-insensitively.
    private func uniqueGermanCityMatch(for address: String) async -> GeoCoordinate? {
        let parts = address
            .split(separator: ",", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let cityName = parts.first ?? address
        let countryPart = parts.count > 1 ? parts[1] : ""

        let isGermany = countryPart.isEmpty
            || countryPart.caseInsensitiveCompare("DE") == .orderedSame
            || countryPart.caseInsensitiveCompare("Deutschland") == .orderedSame
            || countryPart.caseInsensitiveCompare("Germany") == .orderedSame

        guard isGermany, !cityName.isEmpty else { return nil }
        guard let cities = try? await loadGermanCities() else { return nil }

        let matches = cities.filter { $0.name.localizedCaseInsensitiveCompare(cityName) == .orderedSame }
        guard matches.count == 1,
              let match = matches.first,
              let lat = match.latitude,
              let lon = match.longitude else {
            return nil
        }

        let coordinate = GeoCoordinate(latitude: lat, longitude: lon)
        return coordinate.isPlausible ? coordinate : nil
    }
}
