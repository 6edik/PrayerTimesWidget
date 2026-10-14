import SwiftUI
import WidgetKit

/// A fourth, separately selectable lock-screen widget — the *upcoming*
/// prayer's symbol, its abbreviated name, start time, and a live
/// countdown to it (how much longer the current prayer's own window still
/// has left), all on one `.accessoryInline` line (e.g.
/// "☀︎ ASR 15:00 · 2:45:10"). The `.accessoryRectangular` counterpart to
/// this same data is `PrayerCountdownLockWidgetView`; this one is just
/// the single-line version for whoever wants it inline instead.
/// Interpolating `Image(systemName:)` into the `Text` string embeds the
/// SF Symbol inline with the text — the WidgetKit-supported way to mix a
/// glyph into an otherwise plain line — and interpolating the date with
/// `style: .timer` keeps the countdown ticking live without any extra
/// timeline entries, the same pattern every other countdown in this app
/// already uses (see `PrayerTimesWidgetView`).
struct PrayerNextLockWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        Group {
            if let window = resolvedWindow() {
                Text("\(Image(systemName: PrayerStatusIcon.symbolName(forCanonicalRow: window.nextName))) \(shortLabel(for: window.nextName)) \(window.nextTime) · \(window.end, style: .timer)")
                    // Same serif design every other widget family in this
                    // app already uses — this line had no explicit font
                    // at all before, so it rendered in the plain system
                    // font instead of matching the rest of the app.
                    .font(.system(.caption2, design: .serif))
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

    /// Same tight three-letter abbreviations the six-prayer lock
    /// rectangular widget already uses (see `shortLabel(_:)` in
    /// `PrayerTimesWidgetView`), so a prayer name never gets cut off on
    /// this single, non-wrapping inline line.
    private func shortLabel(for value: String) -> String {
        switch value {
        case "Fajr": return "FJR"
        case "Shuruk": return "SRK"
        case "Dhuhr": return PrayerDisplayNaming.dhuhrShortLabel(date: entry.date, timezoneIdentifier: entry.times.timezone)
        case "Asr": return "ASR"
        case "Maghrib": return "MGB"
        case "Isha": return "ISH"
        default: return String(value.prefix(3)).uppercased()
        }
    }
}
