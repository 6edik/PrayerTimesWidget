import SwiftUI
import WidgetKit

struct PrayerTimesWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    private let accent = Color.green

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                homeSmallView
            case .systemMedium:
                homeMediumView
            case .accessoryInline:
                lockInlineView
            case .accessoryCircular:
                lockCircularView
            case .accessoryRectangular:
                lockRectangularView
            default:
                homeSmallView
            }
        }
        .widgetBackground()
    }

    private var homeSmallView: some View {
        let next = nextPrayerInfo()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nächstes Gebet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(shortTimezone(entry.times.timezone))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(next.name)
                    .font(.headline)
                    .foregroundStyle(accent)

                Text(next.time)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            Divider()

            VStack(spacing: 6) {
                compactRow("Fajr", entry.times.fajr)
                compactRow("Dhuhr", entry.times.dhuhr)
                compactRow("Asr", entry.times.asr)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var homeMediumView: some View {
        let next = nextPrayerInfo()

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gebetszeiten")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(entry.times.readableDate)
                    Text("•")
                    Text(entry.times.hijriDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nächstes Gebet")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(next.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)

                    Text(next.time)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()

                Text(shortTimezone(entry.times.timezone))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                detailedRow("Fajr", entry.times.fajr)
                detailedRow("Dhuhr", entry.times.dhuhr)
                detailedRow("Asr", entry.times.asr)
                detailedRow("Maghrib", entry.times.maghrib)
                detailedRow("Isha", entry.times.isha)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var lockInlineView: some View {
        let next = nextPrayerInfo()

        return Text("\(next.name) \(next.time)")
            .font(.caption)
            .monospacedDigit()
    }

    private var lockCircularView: some View {
        let next = nextPrayerInfo()

        return ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Text(shortLabel(next.name))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)

                //Text(shortClock(next.time))
                Text(next.time)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var lockRectangularView: some View {
        let next = nextPrayerInfo()

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text("\(next.name) \(next.time)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 28, height: 28)

                    Text(dayNumber())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }

            HStack(spacing: 0) {
                prayerLockTile(symbol: "sparkles", short: "FJR", time: entry.times.fajr, showDivider: true)
                prayerLockTile(symbol: "sun.max.fill", short: "JUM", time: entry.times.dhuhr, showDivider: true)
                prayerLockTile(symbol: "cloud.sun.fill", short: "ASR", time: entry.times.asr, showDivider: true)
                prayerLockTile(symbol: "sunset.fill", short: "MGB", time: entry.times.maghrib, showDivider: true)
                prayerLockTile(symbol: "moon.stars.fill", short: "ISH", time: entry.times.isha, showDivider: false)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
        .background(Color.black.opacity(0.92))
    }

    private func prayerLockTile(symbol: String, short: String, time: String, showDivider: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 14)

                Text(short)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(time)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 38)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func dayNumber() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: entry.date)
    }

    private func compactRow(_ name: String, _ time: String) -> some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func detailedRow(_ name: String, _ time: String) -> some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(time)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pill(_ name: String, _ time: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .foregroundStyle(.secondary)
            Text(time)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption2)
    }

    private func nextPrayerInfo() -> (name: String, time: String) {
        let prayers: [(String, String)] = [
            ("Fajr", entry.times.fajr),
            ("Dhuhr", entry.times.dhuhr),
            ("Asr", entry.times.asr),
            ("Maghrib", entry.times.maghrib),
            ("Isha", entry.times.isha)
        ]

        let now = Date()
        let calendar = Calendar.current

        for prayer in prayers {
            if let prayerDate = timeToDate(prayer.1, base: now),
               prayerDate > now {
                return prayer
            }
        }

        return ("Fajr", entry.times.fajr)
    }

    private func timeToDate(_ value: String, base: Date) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }

        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: base
        )
    }

    private func shortLabel(_ value: String) -> String {
        switch value {
        case "Fajr": return "FJR"
        case "Dhuhr": return "DHR"
        case "Asr": return "ASR"
        case "Maghrib": return "MGB"
        case "Isha": return "ISH"
        default: return value.prefix(3).uppercased()
        }
    }

    private func shortClock(_ value: String) -> String {
        value.replacingOccurrences(of: ":", with: "")
    }

    private func shortTimezone(_ value: String) -> String {
        if value.contains("/") {
            return value.split(separator: "/").last.map(String.init) ?? value
        }
        return value
    }
}

extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.96),
                        Color.black.opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            self.background(Color.black.opacity(0.92))
        }
    }
}
