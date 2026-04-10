import WidgetKit

enum CacheResetService {
    static func clearAllCaches() {
        SharedPrayerTimesStore().clear()
        SharedIslamicCalendarStore().clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
