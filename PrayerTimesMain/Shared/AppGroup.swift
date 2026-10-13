import Foundation

enum AppGroup {
    nonisolated static let id = "group.com.mertgedik.prayertimes"
    nonisolated static let widgetKind = "PrayerTimesWidget"
    // A second, separately selectable lock-screen widget — simple
    // "current prayer + countdown wording" layout, distinct from the
    // six-prayer `widgetKind` rectangular widget.
    nonisolated static let widgetKindCountdown = "PrayerTimesCountdownWidget"
    // A third, separately selectable lock-screen widget — the inline
    // Gregorian/Hijri date, distinct from both prayer-time layouts above.
    nonisolated static let widgetKindDate = "PrayerTimesDateWidget"
    // A fourth, separately selectable lock-screen widget — the inline
    // "current prayer + start time + live countdown" layout, the
    // `.accessoryInline` counterpart to `widgetKindCountdown`'s
    // `.accessoryRectangular` layout.
    nonisolated static let widgetKindNext = "PrayerTimesNextWidget"
}
