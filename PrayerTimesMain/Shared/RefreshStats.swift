import Foundation

struct RefreshStats: Codable {
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var nextPlannedRefreshAt: Date?
    var lastSource: String?
    var lastError: String?

    var successfulFetchCount: Int
    var failedFetchCount: Int
    var widgetReloadCount: Int
    var timelineBuildCount: Int

    var appStartRefreshCount: Int
    var manualRefreshCount: Int
    var backgroundRefreshCount: Int
    var appActiveRefreshCount: Int
    var widgetTimelineRefreshCount: Int

    static let empty = RefreshStats(
        lastAttemptAt: nil,
        lastSuccessAt: nil,
        lastFailureAt: nil,
        nextPlannedRefreshAt: nil,
        lastSource: nil,
        lastError: nil,
        successfulFetchCount: 0,
        failedFetchCount: 0,
        widgetReloadCount: 0,
        timelineBuildCount: 0,
        appStartRefreshCount: 0,
        manualRefreshCount: 0,
        backgroundRefreshCount: 0,
        appActiveRefreshCount: 0,
        widgetTimelineRefreshCount: 0
    )
}
