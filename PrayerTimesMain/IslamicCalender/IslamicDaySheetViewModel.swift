import Foundation
import Combine

/// Backs the prayer-times section of the Islamic calendar's day sheet for
/// exactly one tapped calendar day: a cache-first, single-day lookup.
///
/// If the persistent Auto-Cache already has an entry for this day that
/// matches the *current* `AutoPrayerSettings` (location and calculation
/// method — checked by `SharedPrayerTimesStore.loadPrayerDay`, which only
/// ever returns a day whose stored `locationKey`/`methodKey` still match),
/// that entry is used immediately with no network request at all. Otherwise
/// this performs exactly one targeted single-day fetch for this date — never
/// a whole month or the app's multi-day auto-refresh window — using the
/// currently configured location (including its confirmed coordinate, when
/// the architecture has one) and calculation method.
///
/// The fetched result is held only in this view model's own `@Published`
/// state. It is never written to `SharedPrayerTimesStore`, so Home, the
/// widget and notification scheduling never see it, and no separate
/// persistent "manual cache" is created either.
@MainActor
final class IslamicDaySheetViewModel: ObservableObject {
    enum PrayerTimesSource: Equatable {
        /// Served from the shared, persistent Auto-Cache.
        case cached
        /// Fetched just now for this one day only; held only in `state`,
        /// never persisted anywhere.
        case fetched
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(raw: PrayerTimes, adjusted: PrayerTimes, source: PrayerTimesSource)
        case offline
        case failed(String)
    }

    /// The calendar day this instance was created for. Passed straight
    /// through, unmodified, to both the cache lookup and the single-day
    /// fetch's `PrayerSettings.date` — the calendar grid already built this
    /// `Date` using the device's own current calendar/timezone (the same
    /// one `PrayerTimesService`'s request-date formatting and
    /// `SharedPrayerTimesStore`'s ISO-date keys use), so passing it on
    /// as-is avoids introducing a second, inconsistent timezone conversion
    /// that could shift the request onto the wrong calendar day.
    let date: Date

    @Published private(set) var state: LoadState = .idle

    private let prayerStore: SharedPrayerTimesStore
    private let settingsProvider: () -> AutoPrayerSettings
    private let service: any SingleDayPrayerTimesFetching
    private var currentTask: Task<Void, Never>?

    init(
        date: Date,
        prayerStore: SharedPrayerTimesStore,
        settingsProvider: @escaping () -> AutoPrayerSettings,
        service: any SingleDayPrayerTimesFetching = PrayerTimesService()
    ) {
        self.date = date
        self.prayerStore = prayerStore
        self.settingsProvider = settingsProvider
        self.service = service
    }

    deinit {
        currentTask?.cancel()
    }

    /// Cache-first lookup for `date`. Safe to call again (e.g. after a
    /// failed/offline attempt, or if the sheet re-appears) — any previous
    /// in-flight request is cancelled first, so only the latest call can
    /// ever update `state`.
    func load() {
        currentTask?.cancel()

        let settings = settingsProvider()
        let requestedDate = date

        // Cache hit: `loadPrayerDay` already validates the stored
        // locationKey/methodKey against `settings`, so a same-day entry
        // left over from a previous city or calculation method is never
        // returned here — it's treated exactly like a miss below.
        if let cachedDay = prayerStore.loadPrayerDay(for: requestedDate, settings: settings) {
            state = .loaded(
                raw: cachedDay.times,
                adjusted: cachedDay.times.applyingAdjustments(settings.adjustments),
                source: .cached
            )
            return
        }

        state = .loading

        let service = self.service
        let prepared = settings.asPrayerSettings(for: requestedDate)

        currentTask = Task { [weak self] in
            do {
                let raw = try await service.fetchPrayerTimesForSingleDayUncached(settings: prepared)
                guard !Task.isCancelled, let self else { return }

                self.state = .loaded(
                    raw: raw,
                    adjusted: raw.applyingAdjustments(settings.adjustments),
                    source: .fetched
                )
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = Self.isOfflineError(error) ? .offline : .failed(error.localizedDescription)
            }
        }
    }

    /// Cancels any in-flight single-day request without touching `state` —
    /// call this when the sheet is dismissed (or replaced by a different
    /// day) before the request finished, so a late result can never land in
    /// a closed or reused sheet.
    func cancel() {
        currentTask?.cancel()
    }

    private static func isOfflineError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
