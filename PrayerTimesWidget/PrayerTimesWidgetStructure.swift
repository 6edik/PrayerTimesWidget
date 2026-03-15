import SwiftUI
import WidgetKit

struct PrayerTimesWidgetStructure: Widget {
    let kind: String = AppGroup.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PrayerTimesWidgetView(entry: entry)
        }
        .configurationDisplayName("Gebetszeiten")
        .description("Zeigt Gebetszeiten auf Home- und Sperrbildschirm an.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
