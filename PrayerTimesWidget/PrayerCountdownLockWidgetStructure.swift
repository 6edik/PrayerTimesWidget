import SwiftUI
import WidgetKit

/// A second, separately selectable lock-screen widget (see
/// `AppGroup.widgetKindCountdown`) — the simple "current prayer + worded
/// countdown" layout in `PrayerCountdownLockWidgetView`, offered alongside
/// the six-prayer `PrayerTimesWidgetStructure` rather than replacing it.
/// Reuses the exact same `Provider`/`PrayerEntry` — no second cache read,
/// no second timeline-scheduling logic.
struct PrayerCountdownLockWidgetStructure: Widget {
    let kind: String = AppGroup.widgetKindCountdown

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PrayerCountdownLockWidgetView(entry: entry)
        }
        .configurationDisplayName("Gebetszeiten Countdown")
        .description("Zeigt das aktuelle Gebet und die verbleibende Zeit bis zum nächsten Gebet auf dem Sperrbildschirm.")
        .supportedFamilies([.accessoryRectangular])
    }
}
