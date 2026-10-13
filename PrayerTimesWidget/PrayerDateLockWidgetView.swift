import SwiftUI
import WidgetKit

/// A third, separately selectable lock-screen widget — just the Hijri
/// date, for anyone who wants it on their lock screen without any
/// prayer-time information and without the Gregorian date (already
/// covered by Apple's own Lock Screen date widget). `.accessoryInline`
/// renders as a single, non-wrapping, non-scrolling line of text that
/// often shares its row with another widget/the clock — day + an
/// Arabic-script abbreviated month + year (see
/// `HijriDateFormatting.shortDisplayTextArabicMonth`), matching the Hijri
/// half of Apple's own Lock Screen date widget. Deliberately just one
/// `Text`, not a `VStack` like the other lock-screen layouts in
/// `PrayerCountdownLockWidgetView`/`PrayerTimesWidgetView`.
struct PrayerDateLockWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        Text(HijriDateFormatting.shortDisplayTextArabicMonth(for: entry.date))
            .widgetBackground()
    }
}
