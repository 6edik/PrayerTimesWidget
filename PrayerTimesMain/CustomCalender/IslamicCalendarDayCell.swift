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
                    .overlay(combinedIndicatorRing)

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

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    // Same Umm-al-Qura source, locale and timezone recipe used everywhere
    // else in the app (Home/widget Hijri display, this cell's own Hijri day
    // number above) — see `HijriDateFormatting`.
    private var hijriCalendar: Calendar {
        HijriDateFormatting.calendar()
    }

    // Single shared definition (`VoluntaryFastingClassifier`) so this
    // highlight and the voluntary-fasting notification scheduler always
    // agree on which days are Monday/Thursday/White Days.
    private var isSunnahFastDay: Bool {
        !VoluntaryFastingClassifier.occasions(
            for: item.date,
            gregorianCalendar: gregorianCalendar,
            hijriCalendar: hijriCalendar
        ).isEmpty
    }

    // Only `isHighlightedHoliday` (one of the app's curated
    // MajorIslamicHoliday cases) may turn the date number orange — an
    // ordinary AlAdhan entry like "Urs of …" that isn't one of those never
    // does, even though it's still fully visible in the day sheet.
    private var primaryTextColor: Color {
        if item.isHighlightedHoliday { return .orange }
        if isSunnahFastDay { return .blue }
        return item.isInDisplayedMonth ? .primary : .secondary
    }

    private var secondaryTextColor: Color {
        if item.isHighlightedHoliday { return .orange.opacity(0.95) }
        if isSunnahFastDay { return .blue.opacity(0.82) }
        return .secondary
    }

    // Combination state: a selected/curated holiday that falls on a
    // Monday/Thursday/White Day keeps the orange date number (above) but
    // also gets a blue ring around it, so both facts stay visible at once
    // instead of one silently overriding the other. An unhighlighted
    // AlAdhan event must never trigger this ring on its own.
    private var showsCombinedHolidayAndFastDayRing: Bool {
        item.isHighlightedHoliday && isSunnahFastDay
    }

    @ViewBuilder
    private var combinedIndicatorRing: some View {
        if showsCombinedHolidayAndFastDayRing {
            Circle()
                .stroke(Color.blue.opacity(0.85), lineWidth: 1.5)
                .frame(width: 26, height: 26)
        }
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
