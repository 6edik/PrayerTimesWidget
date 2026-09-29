import SwiftUI

/// Shared row layout for a single personal note or Zakat-due-date entry —
/// used both inside the day sheet (where the date is already shown by the
/// sheet header, so `showsDate` is `false`) and in the "Meine Notizen"
/// overview (where it is `true`, since entries from many different days
/// are listed together).
struct PersonalCalendarEntryRow: View {
    let entry: PersonalCalendarEntry
    var showsDate: Bool = true

    private let hijriCalendar = HijriDateFormatting.calendar()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            zakatBadge

            if showsDate {
                let text = dateText
                if !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.note)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // Subtle, deliberately not orange (AlAdhan-holiday) or blue
    // (Sunnah-fasting) — just a small secondary-colored tag so a Zakat
    // entry reads differently from a plain note. Shows the fixed Hijri
    // rule itself (e.g. "jedes Hijri-Jahr am 27. Ramadan"), never a single
    // Gregorian date, since that's what actually recurs — shown wherever
    // this row appears, not just in the overview, so the rule is visible
    // regardless of `showsDate`.
    @ViewBuilder
    private var zakatBadge: some View {
        if let day = entry.hijriDay, let month = entry.hijriMonth {
            HStack(spacing: 4) {
                Label("Zakat-Stichtag", systemImage: "banknote")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("· jedes Hijri-Jahr am \(day). \(HijriDateFormatting.monthName(month))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // For a note: the plain Gregorian day. For a Zakat entry: the current
    // representative occurrence, Gregorian *and* Hijri shown together
    // (spec item 7) — a computed Umm-al-Qura mapping, not a claim of
    // religious certainty.
    private var dateText: String {
        switch entry.kind {
        case .note:
            guard let iso = entry.isoDate, let date = PersonalCalendarViewModel.date(from: iso) else { return "" }
            return formattedGregorian(date)

        case .zakatDueDate:
            guard
                let day = entry.hijriDay, let month = entry.hijriMonth,
                let occurrence = ZakatOccurrenceCalculator.nextOccurrence(hijriDay: day, hijriMonth: month, hijriCalendar: hijriCalendar)
            else { return "" }
            return "\(formattedGregorian(occurrence)) · \(HijriDateFormatting.displayText(for: occurrence))"
        }
    }

    private func formattedGregorian(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private var accessibilityText: String {
        var parts: [String] = []

        if let day = entry.hijriDay, let month = entry.hijriMonth {
            parts.append("Zakat-Stichtag, jedes Hijri-Jahr am \(day). \(HijriDateFormatting.monthName(month))")
        }

        if showsDate {
            let text = dateText
            if !text.isEmpty { parts.append(text) }
        }

        parts.append(entry.note)
        return parts.joined(separator: ", ")
    }
}
