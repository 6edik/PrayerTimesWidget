import Foundation

enum RefreshSource: String, Codable {
    case appStart = "App Start"
    case manual = "Manual Refresh"
    case backgroundTask = "Background Task"
    case appActive = "App Active"
    case widgetTimeline = "Widget Timeline"
}

struct RefreshStatsStore {
    private let defaults = UserDefaults(suiteName: AppGroup.id)
    private let key = "refresh_stats"

    func load() -> RefreshStats {
        guard
            let data = defaults?.data(forKey: key),
            let stats = try? JSONDecoder().decode(RefreshStats.self, from: data)
        else {
            return .empty
        }
        return stats
    }

    func save(_ stats: RefreshStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults?.set(data, forKey: key)
    }

    func markAttempt(source: RefreshSource) {
        var stats = load()
        stats.lastAttemptAt = Date()
        stats.lastSource = source.rawValue
        incrementSourceCounter(&stats, source: source)
        save(stats)
    }

    func markSuccess(source: RefreshSource) {
        var stats = load()
        stats.lastSuccessAt = Date()
        stats.lastSource = source.rawValue
        stats.lastError = nil
        stats.successfulFetchCount += 1
        save(stats)
    }

    func markFailure(source: RefreshSource, error: String) {
        var stats = load()
        stats.lastFailureAt = Date()
        stats.lastSource = source.rawValue
        stats.lastError = error
        stats.failedFetchCount += 1
        save(stats)
    }

    func setNextPlannedRefresh(_ date: Date?) {
        var stats = load()
        stats.nextPlannedRefreshAt = date
        save(stats)
    }

    func incrementWidgetReloadCount() {
        var stats = load()
        stats.widgetReloadCount += 1
        save(stats)
    }

    func incrementTimelineBuildCount() {
        var stats = load()
        stats.timelineBuildCount += 1
        save(stats)
    }

    private func incrementSourceCounter(_ stats: inout RefreshStats, source: RefreshSource) {
        switch source {
        case .appStart:
            stats.appStartRefreshCount += 1
        case .manual:
            stats.manualRefreshCount += 1
        case .backgroundTask:
            stats.backgroundRefreshCount += 1
        case .appActive:
            stats.appActiveRefreshCount += 1
        case .widgetTimeline:
            stats.widgetTimelineRefreshCount += 1
        }
    }
}
