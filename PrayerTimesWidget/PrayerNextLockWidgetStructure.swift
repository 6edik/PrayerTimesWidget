import SwiftUI
import WidgetKit

/// A fourth, separately selectable lock-screen widget (see
/// `AppGroup.widgetKindNext`) — the inline "current prayer + start time +
/// countdown" layout in `PrayerNextLockWidgetView`, offered alongside the
/// other lock-screen widgets rather than replacing any of them. Reuses
/// the exact same `Provider`/`PrayerEntry` — no second cache read, no
/// second timeline-scheduling logic.
struct PrayerNextLockWidgetStructure: Widget {
    let kind: String = AppGroup.widgetKindNext

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PrayerNextLockWidgetView(entry: entry)
        }
        .configurationDisplayName("Aktuelles Gebet")
        .description("Zeigt das aktuelle Gebet, dessen Beginn und einen Countdown bis zum nächsten Gebet auf dem Sperrbildschirm.")
        .supportedFamilies([.accessoryInline])
    }
}
