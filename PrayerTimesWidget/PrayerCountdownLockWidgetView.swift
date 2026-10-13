import SwiftUI
import WidgetKit

/// A simple, three-line lock-screen layout: "{nächstes Gebet}: {Uhrzeit}"
/// bold, a subdued "Noch bis {nächstes Gebet}" line, and the remaining
/// duration as a live countdown (e.g. "5:14:36") — a plainer alternative
/// to the six-prayer `lockRectangularView` in `PrayerTimesWidgetView`, for
/// anyone who just wants "what's next and how long" at a glance. The bold
/// line names the *upcoming* prayer (not the one currently active) —
/// the duration underneath is how much longer the current prayer's own
/// window still has left, which is exactly the time remaining until that
/// upcoming prayer starts.
///
/// `Text(_:style:.timer)` — not a worded string computed once from
/// `entry.date` — exactly like `lockInlineView`/`lockCircularView` in
/// `PrayerTimesWidgetView` already do: a plain string only reflects the
/// instant its timeline entry was built, and timeline entries here are
/// only built at prayer/Karāha boundaries (see `Provider`), which can be
/// hours apart — so a static duration visibly goes stale (or looks
/// "stuck"/wrong) until WidgetKit happens to swap in the next entry.
/// Removing and re-adding the widget forces a fresh snapshot for "now",
/// which is exactly why that made it look correct again. `Text(_:style:)`
/// is one of the few views WidgetKit itself keeps animating between
/// entries, so this never goes stale.
struct PrayerCountdownLockWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        Group {
            if let window = resolvedWindow() {
                // Same serif design + weight/size conventions every other
                // widget family in this app already uses (see
                // `lockRectangularView`/`lockCircularView` in
                // `PrayerTimesWidgetView`) — never a different font family
                // just because this is a separate widget kind.
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(displayName(for: window.nextName)): \(window.nextTime)")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("Noch bis \(displayName(for: window.nextName))")
                        .font(.system(size: 11, weight: .light, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Orange matches the "Noch"/remaining-time countdown
                    // color already used everywhere else (e.g. the medium
                    // widget's own countdown).
                    Text(window.end, style: .timer)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Keine Daten")
                    .font(.system(.caption2, design: .serif))
            }
        }
        .widgetBackground()
    }

    /// Resolves the current/next prayer window purely from data already
    /// carried on the entry — no extra App-Group read from inside the view
    /// layer, the exact same `PrayerWindowResolver` every other widget
    /// family already uses. `nil` means there genuinely isn't enough
    /// cached data to resolve a window.
    private func resolvedWindow() -> PrayerWindowResolver.Window? {
        let todayAdjusted = AdjustedPrayerTimes(times: entry.times, dayOffsets: entry.dayOffsets)
        let previousAdjusted = entry.previousDayTimes.map {
            AdjustedPrayerTimes(times: $0, dayOffsets: entry.previousDayOffsets)
        }
        let nextAdjusted = entry.nextDayTimes.map {
            AdjustedPrayerTimes(times: $0, dayOffsets: entry.nextDayOffsets)
        }

        return PrayerWindowResolver.resolve(
            now: entry.date,
            todayTimes: todayAdjusted,
            previousDayTimes: previousAdjusted,
            nextDayTimes: nextAdjusted
        )
    }

    /// Today's Dhuhr/Jum'ah label, in the prayer location's own timezone.
    private var dhuhrTitle: String {
        PrayerDisplayNaming.dhuhrLabel(date: entry.date, timezoneIdentifier: entry.times.timezone)
    }

    private func displayName(for value: String) -> String {
        switch value {
        case "Dhuhr": return dhuhrTitle
        default: return value
        }
    }
}
