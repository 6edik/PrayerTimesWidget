import Foundation

/// What a personal calendar entry represents.
nonisolated enum PersonalCalendarEntryKind: String, Codable, CaseIterable, Identifiable {
    case note
    case zakatDueDate

    nonisolated var id: String { rawValue }
}

/// A simple, user-authored note attached to one calendar day — or a
/// personal Zakat-due-date rule — persisted only in `PersonalCalendarStore`.
/// Entirely separate from the AlAdhan holiday cache
/// (`SharedIslamicCalendarStore`) and the prayer-times cache
/// (`SharedPrayerTimesStore`). Never transferred to Apple Calendar, iCloud,
/// or any network request.
///
/// `.zakatDueDate` entries always recur every Hijri year — this is a fixed
/// business decision, not a per-entry toggle: there is no one-time Zakat
/// entry and no option to repeat by a fixed Gregorian date instead. The
/// authoritative rule is `hijriDay`/`hijriMonth` (`isoDate` stays `nil` for
/// this kind); a Gregorian date is, at most, a *computed* display
/// equivalent for one particular year, never a stored repeat rule — see
/// `ZakatOccurrenceCalculator`.
nonisolated struct PersonalCalendarEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var note: String
    var kind: PersonalCalendarEntryKind

    /// Only meaningful for `.note` entries: the calendar day as a
    /// timezone-agnostic "yyyy-MM-dd" label — deliberately not an absolute
    /// `Date`/timestamp, so a device timezone change can never shift this
    /// entry onto a different calendar day. Always `nil` for
    /// `.zakatDueDate` entries.
    var isoDate: String?

    /// Only meaningful for `.zakatDueDate` entries: the Hijri day (1...30)
    /// that recurs every Hijri year under `Calendar(identifier:
    /// .islamicUmmAlQura)` — the same calendar basis the rest of the app's
    /// Islamic calendar uses. This is the rule itself, never a value
    /// derived from a Gregorian date. `nil` for `.note` entries.
    var hijriDay: Int?
    /// Only meaningful for `.zakatDueDate` entries: the Hijri month
    /// (1...12) — see `hijriDay`.
    var hijriMonth: Int?

    var createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        note: String,
        kind: PersonalCalendarEntryKind = .note,
        isoDate: String? = nil,
        hijriDay: Int? = nil,
        hijriMonth: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.note = note
        self.kind = kind
        self.isoDate = isoDate
        self.hijriDay = hijriDay
        self.hijriMonth = hijriMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, note, kind, isoDate, hijriDay, hijriMonth, createdAt, updatedAt
    }

    // Custom decode:
    // - Notes persisted before `kind` existed still decode as `.note`
    //   (unchanged behavior from earlier versions of this feature).
    // - Zakat entries saved by the *previous* version of this feature
    //   (a Gregorian anchor date + an optional recurrence toggle, no
    //   `hijriDay`/`hijriMonth` at all) are migrated here: the Hijri
    //   (day, month) is derived once from that stored `isoDate`, using the
    //   exact same `Calendar(identifier: .islamicUmmAlQura)` basis the
    //   rest of the app uses, and `isoDate` itself is dropped (`nil`)
    //   since the Hijri rule is now authoritative and a Gregorian date is
    //   never persisted as a repeat rule.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        note = try container.decode(String.self, forKey: .note)
        kind = try container.decodeIfPresent(PersonalCalendarEntryKind.self, forKey: .kind) ?? .note
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        let decodedIsoDate = try container.decodeIfPresent(String.self, forKey: .isoDate)
        let decodedHijriDay = try container.decodeIfPresent(Int.self, forKey: .hijriDay)
        let decodedHijriMonth = try container.decodeIfPresent(Int.self, forKey: .hijriMonth)

        switch kind {
        case .note:
            isoDate = decodedIsoDate
            hijriDay = nil
            hijriMonth = nil

        case .zakatDueDate:
            isoDate = nil

            if let day = decodedHijriDay, let month = decodedHijriMonth {
                hijriDay = day
                hijriMonth = month
            } else if let legacyIso = decodedIsoDate, let legacyDate = PersonalCalendarViewModel.date(from: legacyIso) {
                let hijriCalendar = HijriDateFormatting.calendar()
                let comps = hijriCalendar.dateComponents([.day, .month], from: legacyDate)
                hijriDay = comps.day
                hijriMonth = comps.month
            } else {
                hijriDay = nil
                hijriMonth = nil
            }
        }
    }
}
