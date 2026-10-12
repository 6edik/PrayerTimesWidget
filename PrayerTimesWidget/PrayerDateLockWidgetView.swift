import SwiftUI
import WidgetKit

/// A third, separately selectable lock-screen widget — just the Gregorian
/// and Hijri date, for anyone who wants the date on their lock screen
/// without any prayer-time information. `.accessoryInline` renders as a
/// single line of text next to the lock-screen clock, so this is
/// deliberately just one `Text`, not a `VStack` like the other lock-screen
/// layouts in `PrayerCountdownLockWidgetView`/`PrayerTimesWidgetView`.
struct PrayerDateLockWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        Text("\(Self.gregorianDateText(for: entry.date)) • \(HijriDateFormatting.displayText(for: entry.date))")
            .widgetBackground()
    }

    /// Same German-locale format as the Home screen's own Gregorian date
    /// line (`PrayerTimesHomeView.formattedGregorianDate`) — kept as a
    /// separate copy here since that one is `private` to its view and the
    /// widget extension can't import it directly.
    private static func gregorianDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMMM yyyy"
        return formatter.string(from: date)
    }
}
