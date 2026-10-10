import SwiftUI

struct IslamicHolidayOverviewSheet: View {
    @ObservedObject var viewModel: IslamicCalendarViewModel
    let referenceDate: Date

    private let zakatStore = ZakatDueDateStore()

    @State private var zakatDueDate: ZakatDueDate?
    // Local editing state for the Hijri day/month pickers — seeded from
    // `zakatDueDate` on appear, or from today's own Hijri day/month when
    // nothing is configured yet, so the pickers never start on an
    // arbitrary placeholder.
    @State private var zakatHijriDay = 1
    @State private var zakatHijriMonth = 1
    @State private var showGregorianDatePicker = false
    @State private var gregorianDateSelection = Date()

    /// The single, centrally deduplicated and chronologically sorted
    /// "Besondere Tage" list — built once by `IslamicCalendarViewModel
    /// .visibleSpecialDays`, which merges the curated AlAdhan holidays
    /// with the user's own Zakat-due-date occurrences and removes exact
    /// duplicates. This view never merges or dedupes the two sources
    /// itself.
    private var mergedVisibleDays: [IslamicSpecialDay] {
        viewModel.visibleSpecialDays(from: referenceDate, limit: 10, zakatDueDate: zakatDueDate)
    }

    /// The single nearest upcoming special day across *both* sources — the
    /// 8 curated AlAdhan holidays and the user's own Zakat-due-date
    /// occurrences — so the hero card's "Nächstes Ereignis" never ignores
    /// a Zakat date that happens to fall sooner than the next holiday.
    private var featuredHoliday: IslamicSpecialDay? {
        viewModel.featuredSpecialDay(from: referenceDate, zakatDueDate: zakatDueDate)
    }

    var body: some View {
        IslamicCalendarPageContainer(title: "Besondere Tage") {
            heroCard

            if viewModel.isHolidayOverviewLoading {
                loadingCard
            } else if let error = viewModel.holidayOverviewErrorMessage {
                errorCard(error)
            } else {
                holidaysCard
            }

            // Deliberately last — after every AlAdhan-sourced holiday
            // content above, per spec ("nach allen vorhandenen
            // Ereignissen und Einstellungen"). The reminder/notification
            // setting itself lives only on the Notifications page now —
            // see `NotificationSettingsView`.
            zakatDueDateCard
        }
        .task {
            await viewModel.loadHolidayOverview(around: referenceDate)
        }
        .onAppear {
            loadZakatState()
        }
    }

    // MARK: - Zakat-Stichtag (always the last section on this page)

    /// Seeds the Hijri-day/month pickers from the stored rule, or from
    /// today's own Hijri day/month when nothing is configured yet — never
    /// an arbitrary placeholder like "1. Muharram".
    private func loadZakatState() {
        zakatDueDate = zakatStore.load()

        if let zakatDueDate {
            zakatHijriDay = zakatDueDate.hijriDay
            zakatHijriMonth = zakatDueDate.hijriMonth
        } else {
            let today = HijriDateFormatting.dayAndMonth(for: referenceDate)
            zakatHijriDay = today.day > 0 ? today.day : 1
            zakatHijriMonth = today.month > 0 ? today.month : 1
        }
    }

    private var isZakatActive: Bool {
        zakatDueDate?.isEnabled ?? false
    }

    private var zakatEnabledBinding: Binding<Bool> {
        Binding(
            get: { isZakatActive },
            set: { newValue in
                persistZakatDueDate(isEnabled: newValue)
            }
        )
    }

    private func persistZakatDueDate(isEnabled: Bool) {
        let updated = ZakatDueDate(hijriDay: zakatHijriDay, hijriMonth: zakatHijriMonth, isEnabled: isEnabled)
        zakatStore.save(updated)
        zakatDueDate = updated
        Task { await NotificationScheduler().reschedule() }
    }

    /// Converts the user's chosen *Gregorian* calendar day into the
    /// recurring Hijri (day, month) rule — the same Umm-al-Qura basis
    /// (`HijriDateFormatting.calendar()`) used everywhere else in the app
    /// — and persists it exactly like the two picker chips do. The
    /// Gregorian date itself is never stored; only the derived Hijri rule
    /// is, so the entry still recurs correctly every Hijri year.
    private func applyGregorianSelection() {
        let comps = HijriDateFormatting.calendar().dateComponents([.day, .month], from: gregorianDateSelection)
        guard let day = comps.day, let month = comps.month else { return }
        zakatHijriDay = day
        zakatHijriMonth = month
        persistZakatDueDate(isEnabled: isZakatActive)
    }

    /// Setup card: the activation toggle sits in the header, directly
    /// beside the "Zakat-Stichtag" title (as the card's accessory — see
    /// `IslamicCalendarSectionCard`), and the current-date display itself
    /// (same icon-badge row shape `holidayRow` uses, for visual consistency
    /// with the list above) is the single, fully tappable entry point into
    /// the Gregorian-day picker — there's no separate button anymore, and
    /// no manual Hijri day/month entry either; the Gregorian calendar
    /// picker is the only way to set the rule. That picker entry point only
    /// shows up once the toggle is actually on — while it's off, there's
    /// nothing to configure yet.
    private var zakatDueDateCard: some View {
        IslamicCalendarSectionCard(
            title: "Zakat-Stichtag",
            symbol: "banknote",
            content: {
                if isZakatActive {
                    currentZakatDateRow
                }
            },
            accessory: {
                Toggle("", isOn: zakatEnabledBinding)
                    .labelsHidden()
                    .tint(IslamicCalendarPageStyle.accentStrong)
                    .accessibilityLabel("Zakat-Stichtag aktiv")
            }
        )
        .sheet(isPresented: $showGregorianDatePicker) {
            NavigationStack {
                // A custom month grid instead of the native graphical
                // `DatePicker`: the native control has no way to show a
                // second number under each day, so it can't surface the
                // converted Hijri day the way the Islamic-calendar tab's
                // own grid does. This mirrors that same grid's layout
                // (Gregorian number, Hijri number beneath) for the exact
                // same at-a-glance conversion here.
                GregorianHijriCalendarGrid(selection: $gregorianDateSelection)
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showGregorianDatePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Übernehmen") {
                                applyGregorianSelection()
                                showGregorianDatePicker = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// The entire card is the tap target for opening the Gregorian-day
    /// picker — no separate "Gregorianischen Tag im Kalender wählen"
    /// button alongside it anymore. A plain `Button` (not `onTapGesture`)
    /// so it keeps standard button accessibility/hit-testing behavior.
    private var currentZakatDateRow: some View {
        Button {
            gregorianDateSelection = Date()
            showGregorianDatePicker = true
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(IslamicCalendarPageStyle.accentGradient)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "banknote")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jedes Hijri-Jahr am")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("\(zakatHijriDay). \(HijriDateFormatting.monthName(zakatHijriMonth))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IslamicCalendarPageStyle.accentStrong)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassBackground(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Jedes Hijri-Jahr am \(zakatHijriDay). \(HijriDateFormatting.monthName(zakatHijriMonth)). Gregorianisches Datum auswählen."
        )
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(IslamicCalendarPageStyle.accentGradient)

            Text("Nächstes Ereignis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(IslamicCalendarPageStyle.accentStrong)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                Text(featuredHoliday?.title ?? "Islamische Feiertage")
                    .font(.largeTitle.weight(.ultraLight))
                    .foregroundStyle(IslamicCalendarPageStyle.accentStrong)
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)

                if let featuredHoliday {
                    VStack(spacing: 8) {
                            Text(viewModel.holidayGregorianText(for: featuredHoliday))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            Text(viewModel.holidayHijriText(for: featuredHoliday))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Es sind aktuell keine kommenden besonderen Tage verfügbar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(IslamicCalendarPageStyle.cardPadding)
        .glassCard(cornerRadius: 24)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(IslamicCalendarPageStyle.accentStrong)

            Text("Besondere Tage werden geladen …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(cornerRadius: 22)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: "Fehler", symbol: "exclamationmark.triangle")

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    /// `mergedVisibleDays` partitioned into runs of entries that land on
    /// the exact same Gregorian calendar day — so two (or more) events on
    /// one day render together in a single block instead of as separate,
    /// visually disconnected rows. `mergedVisibleDays` is already
    /// chronologically sorted, so same-day entries are always adjacent;
    /// this only ever merges neighbors, never re-sorts or re-groups
    /// across the whole list.
    private var groupedVisibleDays: [[IslamicSpecialDay]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent

        var groups: [[IslamicSpecialDay]] = []
        for day in mergedVisibleDays {
            if let lastFirst = groups.last?.first,
               calendar.isDate(lastFirst.sortDate, inSameDayAs: day.sortDate) {
                groups[groups.count - 1].append(day)
            } else {
                groups.append([day])
            }
        }
        return groups
    }

    private var holidaysCard: some View {
        IslamicCalendarSectionCard(title: "Kommende Ereignisse", symbol: "calendar") {
            if mergedVisibleDays.isEmpty {
                Text("Keine Einträge verfügbar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(groupedVisibleDays.enumerated()), id: \.offset) { _, group in
                        if group.count == 1 {
                            holidayRow(group[0])
                        } else {
                            holidayGroupBlock(group)
                        }
                    }
                }
            }
        }
    }

    /// Two or more special days sharing one Gregorian calendar day,
    /// rendered as a single row — same shape as `holidayRow`, just with
    /// every event's title joined on one line ("Arafa, Hajj") and one
    /// shared Gregorian/Hijri date line underneath, instead of stacking
    /// each event's own title/date block vertically.
    private func holidayGroupBlock(_ group: [IslamicSpecialDay]) -> some View {
        let isFeatured = group.contains { $0.id == featuredHoliday?.id }
        let combinedTitle = group.map(\.title).joined(separator: ", ")

        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFeatured ? AnyShapeStyle(IslamicCalendarPageStyle.accentGradient) : AnyShapeStyle(IslamicCalendarPageStyle.accentTint))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isFeatured ? .white : IslamicCalendarPageStyle.accentStrong)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(combinedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFeatured ? IslamicCalendarPageStyle.accentStrong : .primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(viewModel.holidayGregorianText(for: group[0]))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(1)

                    Text("|")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(viewModel.holidayHijriText(for: group[0]))
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isFeatured {
                Text("Nächstes")
                    .font(.caption2.bold())
                    .foregroundStyle(IslamicCalendarPageStyle.accentStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .glassBackground(cornerRadius: 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassBackground(cornerRadius: 16)
    }

    private func holidayRow(_ holiday: IslamicSpecialDay) -> some View {
        let isFeatured = holiday.id == featuredHoliday?.id
        let isZakat = holiday.title == ZakatOccurrenceCalculator.specialDayTitle

        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFeatured ? AnyShapeStyle(IslamicCalendarPageStyle.accentGradient) : AnyShapeStyle(IslamicCalendarPageStyle.accentTint))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: isZakat ? "banknote" : (isFeatured ? "star.fill" : "moon.stars"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isFeatured ? .white : IslamicCalendarPageStyle.accentStrong)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(holiday.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFeatured ? IslamicCalendarPageStyle.accentStrong : .primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(viewModel.holidayGregorianText(for: holiday))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(1)

                    Text("|")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(viewModel.holidayHijriText(for: holiday))
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isFeatured {
                Text("Nächstes")
                    .font(.caption2.bold())
                    .foregroundStyle(IslamicCalendarPageStyle.accentStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .glassBackground(cornerRadius: 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassBackground(cornerRadius: 16)
    }

    private func headerRow(title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IslamicCalendarPageStyle.accentGradient)
                .background(IslamicCalendarPageStyle.accentTint, in: RoundedRectangle(cornerRadius: 12))
                .frame(width: 34, height: 34)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

/// A month-navigable Gregorian calendar grid that shows the converted
/// Hijri day number beneath every Gregorian day number — the same layout
/// idea as `IslamicCalendarDayCell` on the Islamic-calendar tab, scoped
/// down to just "pick a Gregorian day, see its Hijri equivalent at a
/// glance" (no events, prayer times, or personal-entry indicators here).
/// Used only to let the user pick the Zakat-due-date rule by a familiar
/// Gregorian day instead of the raw Hijri month/day pickers.
private struct GregorianHijriCalendarGrid: View {
    @Binding var selection: Date
    @State private var displayedMonth: Date

    init(selection: Binding<Date>) {
        _selection = selection
        _displayedMonth = State(initialValue: selection.wrappedValue)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = .autoupdatingCurrent
        cal.timeZone = .autoupdatingCurrent
        return cal
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text(monthHeaderText)
                        .font(.headline)

                    Text(hijriMonthHeaderText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                ForEach(daysInGrid, id: \.self) { date in
                    dayCell(date)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let isInMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return Button {
            selection = date
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text(HijriDateFormatting.dayText(for: date))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(IslamicCalendarPageStyle.accentGradient)
                            : (isToday ? AnyShapeStyle(Color.green.opacity(0.14)) : AnyShapeStyle(Color.clear))
                    )
            )
            .foregroundStyle(isSelected ? .white : (isInMonth ? .primary : .secondary))
            .opacity(isInMonth ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }

    private var monthHeaderText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth)
    }

    /// The Hijri month(s)/year(s) actually spanned by the currently
    /// displayed *Gregorian* month, shown right under the Gregorian header
    /// so a Hijri-minded due date is still easy to place at a glance even
    /// though the grid itself navigates by Gregorian month. A Gregorian
    /// month almost always spans two Hijri months (~29–30 days each), so
    /// this lists every distinct one actually present ("Rajab 1448 /
    /// Schaʿban 1448"), not just the first day's — mirroring
    /// `IslamicCalendarViewModel.hijriMonthSummary(for:)`'s exact
    /// behavior on the main calendar tab (this grid has no access to that
    /// view model, so the same logic is reproduced here against the
    /// shared `HijriDateFormatting` basis instead of duplicating state).
    private var hijriMonthHeaderText: String {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return ""
        }

        struct HijriMonthKey: Hashable {
            let year: Int
            let month: Int
        }

        let hijriCalendar = HijriDateFormatting.calendar()
        var current = monthInterval.start
        var orderedKeys: [HijriMonthKey] = []
        var seen = Set<HijriMonthKey>()

        while current < monthInterval.end {
            let comps = hijriCalendar.dateComponents([.month, .year], from: current)
            if let month = comps.month, let year = comps.year {
                let key = HijriMonthKey(year: year, month: month)
                if !seen.contains(key) {
                    seen.insert(key)
                    orderedKeys.append(key)
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return orderedKeys
            .map { "\(HijriDateFormatting.monthName($0.month)) \($0.year)" }
            .joined(separator: " / ")
    }

    private var daysInGrid: [Date] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastMoment = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastMoment)
        else {
            return []
        }

        var dates: [Date] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private func moveMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }
}
