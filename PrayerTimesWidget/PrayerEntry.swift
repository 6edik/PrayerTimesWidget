import WidgetKit

struct PrayerEntry: TimelineEntry {
    let date: Date
    let times: PrayerTimes
    // Per-prayer day offsets for `times`, so consumers that need to build an
    // absolute `Date` for a prayer moment (widget "current/next" logic) know
    // whether a midnight-crossing adjustment moved it onto the previous/next
    // calendar day. Plain display code can ignore this and just print
    // `times.fajr` etc.
    let dayOffsets: PrayerDayOffsets
    let previousDayTimes: PrayerTimes?
    let previousDayOffsets: PrayerDayOffsets
}
