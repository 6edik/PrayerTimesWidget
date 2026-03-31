import WidgetKit

struct PrayerEntry: TimelineEntry {
    let date: Date
    let times: PrayerTimes
    let previousDayTimes: PrayerTimes?
}
