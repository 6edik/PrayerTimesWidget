import SwiftUI

/// Shared row layout for a single personal note — used both inside the day
/// sheet (where the date is already shown by the sheet header, so
/// `showsDate` is `false`) and in the "Meine Notizen" overview (where it is
/// `true`, since entries from many different days are listed together).
///
/// `isCompact` shows only the note's first paragraph (up to the first
/// line break), truncated to one line, instead of the full text — used
/// everywhere a row sits in a list of several notes (the day sheet, the
/// "Meine Notizen" overview), so a long, multi-paragraph note can never
/// balloon that list; tapping the row is how you get to the full text.
struct PersonalCalendarEntryRow: View {
    let entry: PersonalCalendarEntry
    var showsDate: Bool = true
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsDate {
                let text = dateText
                if !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(previewText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(isCompact ? 1 : nil)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: !isCompact)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Only the note's first paragraph when `isCompact` — everything up
    /// to (not including) the first line break. A note without any line
    /// break is already just one paragraph, so this is a no-op for it.
    private var previewText: String {
        guard isCompact, let firstBreak = entry.note.firstIndex(of: "\n") else {
            return entry.note
        }
        return String(entry.note[entry.note.startIndex..<firstBreak])
    }

    private var dateText: String {
        guard let iso = entry.isoDate, let date = PersonalCalendarViewModel.date(from: iso) else { return "" }
        return formattedGregorian(date)
    }

    private func formattedGregorian(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private var accessibilityText: String {
        var parts: [String] = []

        if showsDate {
            let text = dateText
            if !text.isEmpty { parts.append(text) }
        }

        parts.append(entry.note)
        return parts.joined(separator: ", ")
    }
}
