import Foundation
import Combine

/// Backs the read-only "Gespeicherte Gebetszeiten" inspector. This view model
/// only ever reads `SharedPrayerTimesStore`/`SharedPrayerSettingsStore` — it
/// never calls `PrayerTimesService`, never writes to either store, and never
/// schedules a refresh. `load()` decodes the cache exactly once per call and
/// caches the result in `@Published` state so the view's list rows and the
/// raw/adjusted toggle never trigger another UserDefaults read.
@MainActor
final class CachedPrayerTimesViewModel: ObservableObject {
    /// One cached day, pre-resolved from the raw cache. Only ever built from
    /// entries that actually exist in the cache — there is no placeholder
    /// case, so a missing day is simply absent from `days`.
    struct DayEntry: Identifiable, Equatable {
        let id: String
        let isoDate: String
        let rawTimes: PrayerTimes
        let hijri: HijriDay?
    }

    @Published private(set) var days: [DayEntry] = []
    @Published private(set) var cacheLocationDisplay = "--"
    // The current, confirmed settings' coordinate line (e.g.
    // "Stadtkoordinaten: 51,5170° N · 7,1000° O") — only populated when the
    // cache actually matches those settings, so a stale/mismatched cache
    // never shows a coordinate line that belongs to a different place.
    @Published private(set) var cacheCoordinateDisplay: String?
    @Published private(set) var cacheMethodDisplay = "--"
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var locationMismatch = false
    @Published private(set) var methodMismatch = false
    @Published private(set) var missingTodayEntry = false
    @Published private(set) var currentAdjustments: PrayerAdjustments = .zero

    private let timesStore: SharedPrayerTimesStore
    private let settingsStore: SharedPrayerSettingsStore

    init(
        timesStore: SharedPrayerTimesStore = SharedPrayerTimesStore(),
        settingsStore: SharedPrayerSettingsStore = SharedPrayerSettingsStore()
    ) {
        self.timesStore = timesStore
        self.settingsStore = settingsStore
    }

    var hasCachedData: Bool { !days.isEmpty }

    var hasMismatch: Bool { locationMismatch || methodMismatch }

    /// Human-readable explanation for a mismatch/staleness banner, or `nil`
    /// when the cache matches the current settings and still covers today.
    /// Mismatch takes priority over staleness: if the cache belongs to a
    /// different place/method entirely, that's the more important fact.
    var noticeMessage: String? {
        guard hasCachedData else { return nil }

        switch (locationMismatch, methodMismatch) {
        case (true, true):
            return "Dieser Cache stammt von einem anderen Ort und einer anderen Berechnungsmethode als deine aktuellen Einstellungen. Diese Zeiten gelten nicht für den aktuell eingestellten Ort."
        case (true, false):
            return "Dieser Cache stammt von einem anderen Ort als deine aktuellen Einstellungen. Diese Zeiten gelten nicht für den aktuell eingestellten Ort."
        case (false, true):
            return "Dieser Cache wurde mit einer anderen Berechnungsmethode als deiner aktuellen Einstellung erzeugt."
        case (false, false):
            break
        }

        if missingTodayEntry {
            return "Der Cache enthält keinen Eintrag für den heutigen Tag und könnte veraltet sein."
        }

        return nil
    }

    /// Reads the current settings and the raw cache exactly once. Purely
    /// local UserDefaults reads — no network request, no cache write. Safe
    /// to call again later (e.g. from a manual "reload from disk" toolbar
    /// button) to pick up changes made by another process sharing the App
    /// Group, still without touching the network.
    func load(referenceDate: Date = Date()) {
        let settings = settingsStore.loadAutoSettings()
        currentAdjustments = settings.adjustments

        let cache = timesStore.snapshot()

        days = cache.days
            .map { DayEntry(id: $0.isoDate, isoDate: $0.isoDate, rawTimes: $0.times, hijri: $0.hijri) }
            .sorted { $0.isoDate < $1.isoDate }

        guard !days.isEmpty else {
            cacheLocationDisplay = "--"
            cacheCoordinateDisplay = nil
            cacheMethodDisplay = "--"
            fetchedAt = nil
            locationMismatch = false
            methodMismatch = false
            missingTodayEntry = false
            return
        }

        fetchedAt = cache.fetchedAt

        let expectedLocationKey = LocationKey.key(address: settings.address, location: settings.location)
        let expectedMethodKey = String(describing: settings.method)

        locationMismatch = cache.locationKey != expectedLocationKey
        methodMismatch = cache.methodKey != expectedMethodKey

        cacheLocationDisplay = locationMismatch
            ? Self.describeLocationKey(cache.locationKey)
            : settings.address

        cacheCoordinateDisplay = (!locationMismatch)
            ? settings.location.map { LocationDisplayFormatter.line(for: $0) }
            : nil

        cacheMethodDisplay = methodMismatch
            ? Self.describeMethodKey(cache.methodKey)
            : settings.method.title

        let todayISO = Self.isoDateFormatter().string(from: referenceDate)
        missingTodayEntry = !days.contains { $0.isoDate == todayISO }
    }

    /// The times to display for `entry`: raw API values when `showRaw` is
    /// true, otherwise the same personal minute adjustments Home and the
    /// widget apply — computed from already-loaded state, no store access.
    func displayTimes(for entry: DayEntry, showRaw: Bool) -> PrayerTimes {
        showRaw ? entry.rawTimes : entry.rawTimes.applyingAdjustments(currentAdjustments)
    }

    /// Which calendar day (relative to `entry`'s own ISO date) each adjusted
    /// prayer time actually falls on — used to flag a "+1 Tag"/"-1 Tag" badge
    /// on rows whose adjustment wraps across midnight, via the same
    /// `PrayerTimeAdjuster` logic Home/widget use for that computation.
    func dayOffsets(for entry: DayEntry) -> PrayerDayOffsets {
        entry.rawTimes.applyingAdjustmentsWithDayOffsets(currentAdjustments).dayOffsets
    }

    func date(for entry: DayEntry) -> Date? {
        Self.isoDateFormatter().date(from: entry.isoDate)
    }

    func isToday(_ entry: DayEntry, referenceDate: Date = Date()) -> Bool {
        entry.isoDate == Self.isoDateFormatter().string(from: referenceDate)
    }

    /// Best-effort label for a cache whose location no longer matches the
    /// current settings. `locationKey` only ever stores what
    /// `LocationKey.key(address:location:)` produced — either a rounded
    /// coordinate or a normalized address string — so this only reformats
    /// that same stored value, never invents a place name the cache doesn't
    /// actually have.
    private static func describeLocationKey(_ key: String) -> String {
        if let range = key.range(of: "coord:") {
            return "Koordinate \(key[range.upperBound...])"
        }
        if let range = key.range(of: "addr:") {
            return String(key[range.upperBound...])
        }
        return key
    }

    /// Best-effort label for a cache whose method no longer matches the
    /// current settings. `methodKey` is `String(describing:)` of a
    /// `PrayerCalculationMethod` case, so this only maps that back to the
    /// same case's `title` — it never guesses a method the cache didn't
    /// actually record.
    private static func describeMethodKey(_ key: String) -> String {
        if let method = PrayerCalculationMethod.allCases.first(where: { String(describing: $0) == key }) {
            return method.title
        }
        return key
    }

    // Must match SharedPrayerTimesStore's internal ISO-date formatting
    // exactly, since the keys read here come from that store's cache.
    private static func isoDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
