import SwiftUI
import WidgetKit

/// A third, separately selectable lock-screen widget (see
/// `AppGroup.widgetKindDate`) — the inline Gregorian/Hijri date in
/// `PrayerDateLockWidgetView`, offered alongside the two prayer-time lock
/// widgets rather than replacing either. Reuses the exact same
/// `Provider`/`PrayerEntry` — no second cache read, no second
/// timeline-scheduling logic.
struct PrayerDateLockWidgetStructure: Widget {
    let kind: String = AppGroup.widgetKindDate

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PrayerDateLockWidgetView(entry: entry)
        }
        .configurationDisplayName("Datum")
        .description("Zeigt das gregorianische und das Hijri-Datum auf dem Sperrbildschirm.")
        .supportedFamilies([.accessoryInline])
    }
}
