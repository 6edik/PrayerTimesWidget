import SwiftUI

struct IslamicCalendarDayCell: View {
    let item: IslamicCalendarDayItem
    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: -1) {
                Text(item.gregorianDayText)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryTextColor)

                if let hijriText = item.hijriText {
                    Text(hijriText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(todayBackground)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .opacity(item.isInDisplayedMonth ? 1 : 0.3)
        .contentShape(Rectangle())
    }

    private var hasEvent: Bool {
        !item.events.isEmpty
    }
    
    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var hijriCalendar: Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var isMondayOrThursday: Bool {
        let weekday = gregorianCalendar.component(.weekday, from: item.date)
        return weekday == 2 || weekday == 5
    }

    private var isWhiteDay: Bool {
        let hijriDay = hijriCalendar.dateComponents([.day], from: item.date).day
        return hijriDay == 13 || hijriDay == 14 || hijriDay == 15
    }

    private var isSunnahFastDay: Bool {
        isMondayOrThursday || isWhiteDay
    }

    private var primaryTextColor: Color {
        if hasEvent { return .orange }
        if isSunnahFastDay { return .blue }
        return item.isInDisplayedMonth ? .primary : .secondary
    }

    private var secondaryTextColor: Color {
        if hasEvent { return .orange.opacity(0.95) }
        if isSunnahFastDay { return .blue.opacity(0.82) }
        return .secondary
    }

    @ViewBuilder
    private var todayBackground: some View {
        if item.isToday {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                )
                .frame(width: 54, height: 58)
        } else if item.isSelected {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 54, height: 58)
        } else {
            Color.clear
        }
    }
}
