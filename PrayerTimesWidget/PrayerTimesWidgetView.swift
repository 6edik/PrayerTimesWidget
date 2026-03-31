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
        let current = currentAndNextPrayerInfo().currentName

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(smallHijriHeader())
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(smallGregorianHeader())
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.top, 8)
                .padding(.bottom, 10)

            VStack(spacing: 4) {
                smallPrayerRow(icon: "sparkles", name: "Fajr", time: entry.times.fajr, isActive: current == "Fajr")
                smallPrayerRow(icon: "sunrise.fill", name: "Sunrise", time: entry.times.shuruk, isActive: current == "Shuruk")
                smallPrayerRow(icon: "sun.max.fill", name: "Dhuhr", time: entry.times.dhuhr, isActive: current == "Dhuhr")
                smallPrayerRow(icon: "cloud.sun.fill", name: "Asr", time: entry.times.asr, isActive: current == "Asr")
                smallPrayerRow(icon: "sunset.fill", name: "Maghrib", time: entry.times.maghrib, isActive: current == "Maghrib")
                smallPrayerRow(icon: "moon.stars.fill", name: "Isha", time: entry.times.isha, isActive: current == "Isha")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func smallPrayerRow(
        icon: String,
        name: String,
        time: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 16, alignment: .leading)
                .foregroundStyle(isActive ? .white : Color.white.opacity(0.72))

            Spacer()
            
            Text(name)
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

        let separators = CharacterSet(charactersIn: "-./ ")
        let parts = raw.components(separatedBy: separators).filter { !$0.isEmpty }

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
        case 7:  month = "RAJB."
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
        let window = prayerWindow()

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
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktuell")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    
                    HStack(spacing: 5){
                        Text(window.currentName)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                        
                        Text(window.currentTime)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Noch")
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.68))

                        Text(window.end, style: .timer)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(Color.orange.opacity(0.95))
                    }

                    Text("bis \(window.nextName)")
                        .font(.system(size: 12, weight: .medium, design: .serif))
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
                        Text(window.currentName)
                        Spacer()
                        Text(window.nextName)
                    }
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            VStack(spacing: 7) {
                mediumPrayerRow("Fajr", entry.times.fajr, isCurrent: window.currentName == "Fajr", isNext: window.nextName == "Fajr")
                mediumPrayerRow("Shuruk", entry.times.shuruk, isCurrent: window.currentName == "Shuruk", isNext: window.nextName == "Shuruk")
                mediumPrayerRow("Dhuhr", entry.times.dhuhr, isCurrent: window.currentName == "Dhuhr", isNext: window.nextName == "Dhuhr")
                mediumPrayerRow("Asr", entry.times.asr, isCurrent: window.currentName == "Asr", isNext: window.nextName == "Asr")
                mediumPrayerRow("Maghrib", entry.times.maghrib, isCurrent: window.currentName == "Maghrib", isNext: window.nextName == "Maghrib")
                mediumPrayerRow("Isha", entry.times.isha, isCurrent: window.currentName == "Isha", isNext: window.nextName == "Isha")
            }
            .frame(width: 120, alignment: .leading)
        }
        .padding()
    }

    private func mediumPrayerRow(
        _ name: String,
        _ time: String,
        isCurrent: Bool,
        isNext: Bool
    ) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .serif))
                .foregroundStyle(isCurrent ? .white : (isNext ? Color.orange.opacity(0.92) : Color.white.opacity(0.62)))

            Spacer(minLength: 6)

            Text(time)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .serif))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? .white : (isNext ? Color.orange.opacity(0.92) : Color.white.opacity(0.62)))
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
    
    private func prayerWindow() -> (
        currentName: String,
        currentTime: String,
        nextName: String,
        nextTime: String,
        start: Date,
        end: Date,
        progress: Double
    ) {
        let info = currentAndNextPrayerInfo()
        let now = entry.date
        let calendar = Calendar.current

        if let fajrDate = timeToDate(entry.times.fajr, base: now),
           now < fajrDate {
            let yesterdayBase = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = timeToDate(entry.previousDayTimes?.isha ?? "--:--", base: yesterdayBase) ?? yesterdayBase
            let end = fajrDate

            return (
                currentName: "Isha",
                currentTime: entry.previousDayTimes?.isha ?? "--:--",
                nextName: "Fajr",
                nextTime: entry.times.fajr,
                start: start,
                end: end,
                progress: progressValue(now: now, start: start, end: end)
            )
        }

        let prayers: [(name: String, time: String)] = [
            ("Fajr", entry.times.fajr),
            ("Shuruk", entry.times.shuruk),
            ("Dhuhr", entry.times.dhuhr),
            ("Asr", entry.times.asr),
            ("Maghrib", entry.times.maghrib),
            ("Isha", entry.times.isha)
        ]

        for index in prayers.indices {
            guard let start = timeToDate(prayers[index].time, base: now) else { continue }

            let end: Date
            let nextName: String
            let nextTime: String

            if index + 1 < prayers.count,
               let next = timeToDate(prayers[index + 1].time, base: now) {
                end = next
                nextName = prayers[index + 1].name
                nextTime = prayers[index + 1].time
            } else {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                let tomorrowFajr = calendar.date(
                    bySettingHour: Int(entry.times.fajr.split(separator: ":").first ?? "0") ?? 0,
                    minute: Int(entry.times.fajr.split(separator: ":").dropFirst().first ?? "0") ?? 0,
                    second: 0,
                    of: tomorrow
                ) ?? tomorrow
                end = tomorrowFajr
                nextName = "Fajr"
                nextTime = entry.times.fajr
            }

            if now >= start && now < end {
                return (
                    currentName: prayers[index].name,
                    currentTime: prayers[index].time,
                    nextName: nextName,
                    nextTime: nextTime,
                    start: start,
                    end: end,
                    progress: progressValue(now: now, start: start, end: end)
                )
            }
        }

        let fallbackStart = timeToDate(entry.times.fajr, base: now) ?? now
        let fallbackEnd = timeToDate(entry.times.dhuhr, base: now) ?? now.addingTimeInterval(60 * 60)

        return (
            currentName: info.currentName,
            currentTime: info.currentTime,
            nextName: info.nextName,
            nextTime: info.nextTime,
            start: fallbackStart,
            end: fallbackEnd,
            progress: progressValue(now: now, start: fallbackStart, end: fallbackEnd)
        )
    }
    
    private func progressValue(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }

        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    private var lockInlineView: some View {
        let next = currentAndNextPrayerInfo()

        return Text("\(next.currentName) \(next.currentTime)")
            .font(.caption)
            .monospacedDigit()
    }

    private var lockCircularView: some View {
        let next = currentAndNextPrayerInfo()

        return ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 1) {
                VStack(spacing: 1) {
                    Text(shortLabel(next.currentName))
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(accent)

                    Text(next.currentTime)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .monospacedDigit()
                }

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 38, height: 1)

                HStack(spacing: 2) {
                    Text(shortLabel(next.nextName))
                        .font(.system(size: 7, weight: .semibold, design: .serif))
                        .foregroundStyle(accent)

                    Text(next.nextTime)
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .monospacedDigit()
                }
            }
        }
    }

    private var lockRectangularView: some View {
        let next = currentAndNextPrayerInfo()

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text("\(next.currentName) \(next.currentTime)")
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
        entry.times.hijriDate
            .split(separator: "-")
            .first
            .map(String.init) ?? "--"
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

    private func currentAndNextPrayerInfo() -> (
        currentName: String,
        currentTime: String,
        nextName: String,
        nextTime: String
    ) {
        let now = entry.date

        if let fajrDate = timeToDate(entry.times.fajr, base: now),
           now < fajrDate {
            return (
                currentName: "Isha",
                currentTime: entry.previousDayTimes?.isha ?? "--:--",
                nextName: "Fajr",
                nextTime: entry.times.fajr
            )
        }

        let prayers: [(name: String, time: String)] = [
            ("Fajr", entry.times.fajr),
            ("Shuruk", entry.times.shuruk),
            ("Dhuhr", entry.times.dhuhr),
            ("Asr", entry.times.asr),
            ("Maghrib", entry.times.maghrib),
            ("Isha", entry.times.isha)
        ]

        var currentName = "Fajr"
        var currentTime = entry.times.fajr
        var nextName = "Dhuhr"
        var nextTime = entry.times.dhuhr

        for (index, prayer) in prayers.enumerated() {
            guard let prayerDate = timeToDate(prayer.time, base: now) else { continue }

            if prayerDate <= now {
                currentName = prayer.name
                currentTime = prayer.time

                if index + 1 < prayers.count {
                    nextName = prayers[index + 1].name
                    nextTime = prayers[index + 1].time
                } else {
                    nextName = "Fajr"
                    nextTime = entry.times.fajr
                }
            }
        }

        return (currentName, currentTime, nextName, nextTime)
    }
    
    private func timeToDate(_ value: String, base: Date) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
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
