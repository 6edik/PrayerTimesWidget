import SwiftUI
import WidgetKit

struct PrayerTimesWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    private let accent = Color.orange
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()

    private struct PrayerMoment {
        let name: String
        let time: String
        let date: Date
    }

    private typealias PrayerWindow = (
        currentName: String,
        currentTime: String,
        nextName: String,
        nextTime: String,
        start: Date,
        end: Date,
        progress: Double
    )

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
        let window = resolvedPrayerWindow()
        let highlights = todaysHighlightState(window: window)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(smallGregorianHeader())
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(smallHijriHeader())
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)

            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.top, 8)
                .padding(.bottom, 10)

            VStack(spacing: 4) {
                smallPrayerRow(
                    icon: "sparkles",
                    title: "Fajr",
                    time: entry.times.fajr,
                    isActive: highlights.primary == "Fajr"
                )

                smallPrayerRow(
                    icon: "sunrise.fill",
                    title: "Sunrise",
                    time: entry.times.shuruk,
                    isActive: highlights.primary == "Shuruk"
                )

                smallPrayerRow(
                    icon: "sun.max.fill",
                    title: "Dhuhr",
                    time: entry.times.dhuhr,
                    isActive: highlights.primary == "Dhuhr"
                )

                smallPrayerRow(
                    icon: "cloud.sun.fill",
                    title: "Asr",
                    time: entry.times.asr,
                    isActive: highlights.primary == "Asr"
                )

                smallPrayerRow(
                    icon: "sunset.fill",
                    title: "Maghrib",
                    time: entry.times.maghrib,
                    isActive: highlights.primary == "Maghrib"
                )

                smallPrayerRow(
                    icon: "moon.stars.fill",
                    title: "Isha",
                    time: entry.times.isha,
                    isActive: highlights.primary == "Isha"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallPrayerRow(
        icon: String,
        title: String,
        time: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 16, alignment: .leading)
                .foregroundStyle(isActive ? .white : Color.white.opacity(0.72))

            Spacer()

            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isActive ? .white : Color.white.opacity(0.72))

            Text(time)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .serif))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(isActive ? .white : Color.white.opacity(0.72))
        }
    }

    private func smallGregorianHeader() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: entry.date).uppercased()
    }

    private func smallHijriHeader() -> String {
        let raw = entry.times.hijriDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = hijriDateParts()

        guard parts.count >= 2 else {
            return raw.uppercased()
        }

        let day = parts[0]
        let monthNumber = Int(parts[1]) ?? 0
        let month: String

        switch monthNumber {
        case 1:  month = "MUH"
        case 2:  month = "SFR"
        case 3:  month = "R-AW"
        case 4:  month = "R-TH"
        case 5:  month = "J-AW"
        case 6:  month = "J-TH"
        case 7:  month = "RAJB"
        case 8:  month = "SHBN"
        case 9:  month = "RMD"
        case 10: month = "SHWL"
        case 11: month = "DHQD"
        case 12: month = "DHHJ"
        default: month = parts[1].uppercased()
        }

        return "\(day). \(month)"
    }

    private var homeMediumView: some View {
        let window = resolvedPrayerWindow()
        let highlights = todaysHighlightState(window: window)

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    Text(smallGregorianHeader())
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .kerning(0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(smallHijriHeader())
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .kerning(0.4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .foregroundStyle(Color.orange.opacity(0.65))
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktuell")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.65))

                    HStack(spacing: 5) {
                        Text(displayName(for: window.currentName))
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)

                        Text(window.currentTime)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("Noch")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.68))

                        Spacer(minLength: 25)

                        Text(window.end, style: .timer)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(Color.orange.opacity(0.95))
                    }
                    .frame(maxWidth: .infinity)

                    Text("bis \(displayName(for: window.nextName))")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.68))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.orange.opacity(0.95),
                                            Color.yellow.opacity(0.85)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(10, geo.size.width * window.progress))
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text(displayName(for: window.currentName))
                        Spacer()
                        Text(displayName(for: window.nextName))
                    }
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            VStack(spacing: 7) {
                mediumPrayerRow(
                    title: "Fajr",
                    time: entry.times.fajr,
                    isCurrent: highlights.current == "Fajr",
                    isNext: highlights.next == "Fajr"
                )

                mediumPrayerRow(
                    title: "Sunrise",
                    time: entry.times.shuruk,
                    isCurrent: highlights.current == "Shuruk",
                    isNext: highlights.next == "Shuruk"
                )

                mediumPrayerRow(
                    title: "Dhuhr",
                    time: entry.times.dhuhr,
                    isCurrent: highlights.current == "Dhuhr",
                    isNext: highlights.next == "Dhuhr"
                )

                mediumPrayerRow(
                    title: "Asr",
                    time: entry.times.asr,
                    isCurrent: highlights.current == "Asr",
                    isNext: highlights.next == "Asr"
                )

                mediumPrayerRow(
                    title: "Maghrib",
                    time: entry.times.maghrib,
                    isCurrent: highlights.current == "Maghrib",
                    isNext: highlights.next == "Maghrib"
                )

                mediumPrayerRow(
                    title: "Isha",
                    time: entry.times.isha,
                    isCurrent: highlights.current == "Isha",
                    isNext: highlights.next == "Isha"
                )
            }
            .frame(width: 120, alignment: .leading)
        }
        .padding()
    }

    private func mediumPrayerRow(
        title: String,
        time: String,
        isCurrent: Bool,
        isNext: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .serif))
                .foregroundStyle(
                    isCurrent ? .white : (isNext ? Color.orange.opacity(0.92) : Color.white.opacity(0.62))
                )

            Spacer(minLength: 6)

            Text(time)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .serif))
                .monospacedDigit()
                .foregroundStyle(
                    isCurrent ? .white : (isNext ? Color.orange.opacity(0.92) : Color.white.opacity(0.62))
                )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Color.white.opacity(0.09) : (isNext ? Color.orange.opacity(0.12) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCurrent ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }

    private var lockInlineView: some View {
        let window = resolvedPrayerWindow()

        return ViewThatFits(in: .horizontal) {
            inlineCountdownText(
                symbol: symbolForPrayer(window.currentName),
                current: shortLabel(window.currentName),
                end: window.end,
                next: shortLabel(window.nextName)
            )

            inlineCompactCountdownText(
                symbol: symbolForPrayer(window.currentName),
                current: shortLabel(window.currentName),
                end: window.end
            )

            Text("\(shortLabel(window.currentName)) \(window.currentTime)")
                .font(.system(.caption2, design: .serif))
                .monospacedDigit()
        }
    }

    private func inlineCountdownText(
        symbol: String,
        current: String,
        end: Date,
        next: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))

            Text(current)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.semibold)

            Text("·")

            Text(end, style: .timer)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.bold)
                .monospacedDigit()

            Text("→ \(next)")
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(.secondary)
        }
    }

    private func inlineCompactCountdownText(
        symbol: String,
        current: String,
        end: Date
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))

            Text(current)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.semibold)

            Text(end, style: .timer)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.bold)
                .monospacedDigit()
        }
    }

    private func symbolForPrayer(_ value: String) -> String {
        switch value {
        case "Fajr": return "sparkles"
        case "Shuruk": return "sunrise.fill"
        case "Dhuhr": return "sun.max.fill"
        case "Asr": return "cloud.sun.fill"
        case "Maghrib": return "sunset.fill"
        case "Isha": return "moon.stars.fill"
        default: return "clock.fill"
        }
    }

    private var lockCircularView: some View {
        let window = resolvedPrayerWindow()

        return ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 1) {
                VStack(spacing: 1) {
                    Text(shortLabel(window.currentName))
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(accent)

                    Text(window.currentTime)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .monospacedDigit()
                }

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 38, height: 1)

                HStack(spacing: 2) {
                    Text(shortLabel(window.nextName))
                        .font(.system(size: 7, weight: .semibold, design: .serif))
                        .foregroundStyle(accent)

                    Text(window.nextTime)
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .monospacedDigit()
                }
            }
        }
    }

    private var lockRectangularView: some View {
        let window = resolvedPrayerWindow()

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text("\(displayName(for: window.currentName)) \(window.currentTime)")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fontDesign(.serif)

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.brown.opacity(0.6))
                        .frame(width: 18, height: 18)

                    Text(dayNumber())
                        .font(.system(size: 12, weight: .light, design: .serif))
                }
            }

            HStack(spacing: 0) {
                prayerLockTile(symbol: "sparkles", short: "FJR", time: entry.times.fajr, showDivider: true)
                prayerLockTile(symbol: "sunrise.fill", short: "SRK", time: entry.times.shuruk, showDivider: true)
                prayerLockTile(symbol: "sun.max.fill", short: "DHR", time: entry.times.dhuhr, showDivider: true)
                prayerLockTile(symbol: "cloud.sun.fill", short: "ASR", time: entry.times.asr, showDivider: true)
                prayerLockTile(symbol: "sunset.fill", short: "MGB", time: entry.times.maghrib, showDivider: true)
                prayerLockTile(symbol: "moon.stars.fill", short: "ISH", time: entry.times.isha, showDivider: false)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
    }

    private func prayerLockTile(symbol: String, short: String, time: String, showDivider: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(height: 10)

                Text(short)
                    .font(.system(size: 9, weight: .light, design: .serif))
                    .foregroundStyle(.brown)

                Text(time)
                    .font(.system(size: 12, weight: .light, design: .serif))
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
        hijriDateParts().first ?? "--"
    }

    private func resolvedPrayerWindow() -> PrayerWindow {
        let now = entry.date
        let calendar = Calendar.current
        let autoSettings = settingsStore.loadAutoSettings()

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now

        let yesterdayTimes = entry.previousDayTimes ?? store.load(for: yesterday, settings: autoSettings)
        let tomorrowTimes = store.load(for: tomorrow, settings: autoSettings)
        let tomorrowFajrTime = tomorrowTimes?.fajr ?? entry.times.fajr

        var moments: [PrayerMoment] = []

        if let yesterdayIsha = yesterdayTimes?.isha,
           let yesterdayIshaDate = timeToDate(yesterdayIsha, base: yesterday) {
            moments.append(
                PrayerMoment(
                    name: "Isha",
                    time: yesterdayIsha,
                    date: yesterdayIshaDate
                )
            )
        }

        let todayMoments: [(name: String, time: String)] = [
            ("Fajr", entry.times.fajr),
            ("Shuruk", entry.times.shuruk),
            ("Dhuhr", entry.times.dhuhr),
            ("Asr", entry.times.asr),
            ("Maghrib", entry.times.maghrib),
            ("Isha", entry.times.isha)
        ]

        for item in todayMoments {
            if let date = timeToDate(item.time, base: now) {
                moments.append(
                    PrayerMoment(
                        name: item.name,
                        time: item.time,
                        date: date
                    )
                )
            }
        }

        if let tomorrowFajrDate = timeToDate(tomorrowFajrTime, base: tomorrow) {
            moments.append(
                PrayerMoment(
                    name: "Fajr",
                    time: tomorrowFajrTime,
                    date: tomorrowFajrDate
                )
            )
        }

        moments.sort { $0.date < $1.date }

        guard !moments.isEmpty else {
            let fallbackStart = now
            let fallbackEnd = now.addingTimeInterval(60 * 60)

            return (
                currentName: "Fajr",
                currentTime: entry.times.fajr,
                nextName: "Dhuhr",
                nextTime: entry.times.dhuhr,
                start: fallbackStart,
                end: fallbackEnd,
                progress: progressValue(now: now, start: fallbackStart, end: fallbackEnd)
            )
        }

        let current = moments.last(where: { $0.date <= now }) ?? moments.first!
        let fallbackNext = PrayerMoment(
            name: "Fajr",
            time: tomorrowFajrTime,
            date: timeToDate(tomorrowFajrTime, base: tomorrow) ?? now.addingTimeInterval(60 * 60)
        )
        let next = moments.first(where: { $0.date > now }) ?? fallbackNext
        let safeEnd = next.date > current.date ? next.date : current.date.addingTimeInterval(60 * 60)

        return (
            currentName: current.name,
            currentTime: current.time,
            nextName: next.name,
            nextTime: next.time,
            start: current.date,
            end: safeEnd,
            progress: progressValue(now: now, start: current.date, end: safeEnd)
        )
    }

    private func todaysHighlightState(window: PrayerWindow) -> (
        current: String?,
        next: String?,
        primary: String?
    ) {
        let calendar = Calendar.current

        let currentToday = calendar.isDate(window.start, inSameDayAs: entry.date) ? window.currentName : nil
        let nextToday = calendar.isDate(window.end, inSameDayAs: entry.date) ? window.nextName : nil
        let primary = currentToday ?? nextToday

        return (
            current: currentToday,
            next: nextToday,
            primary: primary
        )
    }

    private func progressValue(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }

        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    private func timeToDate(_ value: String, base: Date) -> Date? {
        let parts = value.split(separator: ":")

        guard
            parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return nil
        }

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
        case "Shuruk": return "SRK"
        case "Dhuhr": return "DHR"
        case "Asr": return "ASR"
        case "Maghrib": return "MGB"
        case "Isha": return "ISH"
        default: return String(value.prefix(3)).uppercased()
        }
    }

    private func displayName(for value: String) -> String {
        switch value {
        case "Shuruk": return "Sunrise"
        default: return value
        }
    }

    private func hijriDateParts() -> [String] {
        let raw = entry.times.hijriDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "-./ ")
        return raw.components(separatedBy: separators).filter { !$0.isEmpty }
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
