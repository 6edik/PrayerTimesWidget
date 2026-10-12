import SwiftUI
import WidgetKit

/// A simple, three-line lock-screen layout: "{Gebet}: {Uhrzeit}" bold, a
/// subdued "Noch bis {nächstes Gebet}" line, and the remaining duration in
/// words (e.g. "8 Std. 53 Min.") — a plainer alternative to the six-prayer
/// `lockRectangularView` in `PrayerTimesWidgetView`, for anyone who just
/// wants "what's next and how long" at a glance. Deliberately a worded
/// duration, not a live-ticking timer — this layout refreshes at the same
/// timeline cadence as every other widget family here (see `Provider`),
/// which is already dense enough around prayer/Karāha boundaries.
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
                    Text("\(displayName(for: window.currentName)): \(window.currentTime)")
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
                    Text(formattedDuration(window.end.timeIntervalSince(entry.date)))
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(Color.orange.opacity(0.95))
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

    /// "8 Std. 53 Min." — never negative (clamped to 0 first), since
    /// `window.end` is always strictly after `entry.date` by construction
    /// (see `PrayerWindowResolver`), but clamping here keeps this function
    /// honest on its own regardless of caller.
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int((max(duration, 0) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) Std." : "\(hours) Std. \(minutes) Min."
    }
}
