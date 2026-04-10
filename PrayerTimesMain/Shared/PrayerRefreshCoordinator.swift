import Foundation
import WidgetKit

/// Single, shared refresh policy used by the main app (home screen and
/// settings screen), the background refresh task and the widget extension.
///
/// Before this type existed, each of those four call sites re-implemented
/// its own "does the cache need a network refresh" check and its own
/// post-refresh side effects (stats, next-planned-refresh, widget reload),
/// with small differences between them. Centralizing that here guarantees
/// app, background task and widget agree on when to fetch, and adds a
/// short-lived cross-process guard so two of them firing at nearly the same
/// moment don't both perform a full network refetch.
struct PrayerRefreshCoordinator {
    private let store: SharedPrayerTimesStore
    private let statsStore: RefreshStatsStore
    private let refresher: SharedPrayerCacheRefresher

    private static let inProgressKey = "prayer_cache_refresh_in_progress_until"
    // Generous but bounded: long enough to cover a normal multi-month
    // network fetch, short enough that a crashed/killed refresher can't
    // wedge future refreshes for more than this long.
    private static let inProgressGracePeriod: TimeInterval = 25

    init(
        store: SharedPrayerTimesStore = SharedPrayerTimesStore(),
        statsStore: RefreshStatsStore = RefreshStatsStore(),
        refresher: SharedPrayerCacheRefresher = SharedPrayerCacheRefresher()
    ) {
        self.store = store
        self.statsStore = statsStore
        self.refresher = refresher
    }

    enum Outcome: Equatable {
        case skipped
        case alreadyInProgressElsewhere
        case success
        case failure(String)
    }

    /// The one definition of "does the cache need a network refresh right
    /// now" shared by app, background task and widget: the cache must cover
    /// the full policy window (no holes) and still be far enough from
    /// running out.
    func needsRefresh(
        settings: AutoPrayerSettings,
        referenceDate: Date = Date(),
        refreshThresholdDays: Int = 2
    ) -> Bool {
        !store.hasFullRange(for: referenceDate, settings: settings) ||
        store.needsRefresh(settings: settings, referenceDate: referenceDate, refreshThresholdDays: refreshThresholdDays)
    }

    @discardableResult
    func refreshIfNeeded(
        settings: AutoPrayerSettings,
        source: RefreshSource,
        now: Date = Date(),
        forceNetwork: Bool = false,
        refreshThresholdDays: Int = 2
    ) async -> Outcome {
        guard forceNetwork || needsRefresh(settings: settings, referenceDate: now, refreshThresholdDays: refreshThresholdDays) else {
            statsStore.setNextPlannedRefresh(
                store.suggestedRefreshDate(settings: settings, refreshThresholdDays: refreshThresholdDays)
            )
            return .skipped
        }

        guard claimInProgress(now: now) else {
            return .alreadyInProgressElsewhere
        }
        defer { releaseInProgress() }

        statsStore.markAttempt(source: source)

        do {
            try await refresher.refresh(settings: settings, now: now)

            statsStore.markSuccess(source: source)
            statsStore.incrementWidgetReloadCount()
            statsStore.setNextPlannedRefresh(
                store.suggestedRefreshDate(settings: settings, refreshThresholdDays: refreshThresholdDays)
            )

            UserDefaults(suiteName: AppGroup.id)?.set(now, forKey: "last_refresh")
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)

            return .success
        } catch {
            statsStore.markFailure(source: source, error: error.localizedDescription)
            return .failure(error.localizedDescription)
        }
    }

    /// Best-effort, short-TTL marker in the shared App Group defaults so a
    /// concurrent refresh started by another process (app vs. widget
    /// extension) backs off instead of duplicating the network fetch. This
    /// is not a hard distributed lock (UserDefaults gives no compare-and-set
    /// primitive), just a proportionate mitigation for the rare case where
    /// both fire within the same few seconds.
    private func claimInProgress(now: Date) -> Bool {
        let defaults = UserDefaults(suiteName: AppGroup.id)

        if let until = defaults?.object(forKey: Self.inProgressKey) as? Date, until > now {
            return false
        }

        defaults?.set(now.addingTimeInterval(Self.inProgressGracePeriod), forKey: Self.inProgressKey)
        return true
    }

    private func releaseInProgress() {
        UserDefaults(suiteName: AppGroup.id)?.removeObject(forKey: Self.inProgressKey)
    }
}
