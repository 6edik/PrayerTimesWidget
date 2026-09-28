import Foundation
import Combine

@MainActor
final class IslamicCalendarViewModel: ObservableObject {
    @Published private(set) var specialDays: [IslamicSpecialDay] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    @Published private(set) var holidayOverviewDays: [IslamicSpecialDay] = []
    @Published private(set) var isHolidayOverviewLoading = false
    @Published var holidayOverviewErrorMessage: String?

    private let service: IslamicCalendarService
    private let prayerStore: SharedPrayerTimesStore
    private let calendarStore: SharedIslamicCalendarStore
    private let settingsProvider: () -> AutoPrayerSettings

    init(
        service: IslamicCalendarService,
        prayerStore: SharedPrayerTimesStore,
        calendarStore: SharedIslamicCalendarStore,
        settingsProvider: @escaping () -> AutoPrayerSettings
    ) {
        self.service = service
        self.prayerStore = prayerStore
        self.calendarStore = calendarStore
        self.settingsProvider = settingsProvider
    }

    convenience init(settingsProvider: @escaping () -> AutoPrayerSettings) {
        self.init(
            service: IslamicCalendarService(),
            prayerStore: SharedPrayerTimesStore(),
            calendarStore: SharedIslamicCalendarStore(),
            settingsProvider: settingsProvider
        )
    }

    private var calendar: Calendar {
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

    var sectionTitle: String {
        "Besondere Tage"
    }

    var weekdays: [String] {
        ["Mo", "Di", "Mi", "Do", "Fr", "Sa","So"]
    }

    func monthHeaderText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    func loadYear(for date: Date, force: Bool = false) async {
        let year = calendar.component(.year, from: date)

        if !force, let cached = IslamicHolidayClassifier.loadYearMigratingIfNeeded(year, store: calendarStore, hijriCalendar: hijriCalendar) {
            specialDays = cached
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await service.fetchSpecialDays(forGregorianYear: year)
            // Filtered immediately on arrival — `specialDays` (which feeds
            // the day sheet, the grid's orange highlight and the "X
            // Ereignisse" summary) must never even transiently hold an
            // irrelevant AlAdhan entry, not just the persisted copy.
            let relevant = IslamicHolidayClassifier.filterRelevant(fetched, hijriCalendar: hijriCalendar)
            specialDays = relevant
            calendarStore.saveYear(year, days: relevant)
        } catch {
            specialDays = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reloadYear(for date: Date) async {
        await loadYear(for: date, force: true)
    }

    func clearCalendarCache() {
        calendarStore.clear()
        specialDays = []
        holidayOverviewDays = []
        errorMessage = nil
        holidayOverviewErrorMessage = nil
        isLoading = false
        isHolidayOverviewLoading = false
    }

    /// Every AlAdhan special day attached to `date`, unfiltered — feeds the
    /// day sheet's event list. Includes entries like "Urs of …" or "Birth
    /// of …" that are not one of the app's selected major holidays; never
    /// used to decide the calendar grid's orange highlight (see
    /// `isHighlightedHoliday(for:)`).
    func allEventsForDay(_ date: Date) -> [IslamicSpecialDay] {
        specialDays
            .filter { calendar.isDate($0.sortDate, inSameDayAs: date) }
            .sorted { $0.sortDate < $1.sortDate }
    }

    func hasAnyEventForDay(_ date: Date) -> Bool {
        !allEventsForDay(date).isEmpty
    }

    /// True only when at least one of `date`'s AlAdhan special days is one
    /// of the app's own curated `MajorIslamicHoliday` cases — the exact
    /// same Umm-al-Qura-based definitions and AlAdhan-reported Hijri
    /// day/month (`IslamicHolidayClassifier`) the Feiertage-overview and
    /// the holiday-notification scheduler already use. Deliberately not a
    /// title search (no "Eid"/"Birth"/"Urs" string matching) and not just
    /// "does this day have any event at all" — an ordinary AlAdhan entry
    /// like "Urs of …" must never make this true.
    func isHighlightedHoliday(for date: Date) -> Bool {
        allEventsForDay(date).contains { IslamicHolidayClassifier.isMajorHoliday($0, hijriCalendar: hijriCalendar) }
    }

    /// Builds a fresh, per-day view model for the day sheet's cache-first,
    /// single-day prayer-times lookup. A new instance per presented day
    /// (never reused across taps) keeps rapid day switches and sheet
    /// dismissal race-free: each instance only ever holds/updates state for
    /// the one `date` it was created with.
    func makeDaySheetViewModel(for date: Date) -> IslamicDaySheetViewModel {
        IslamicDaySheetViewModel(
            date: date,
            prayerStore: prayerStore,
            settingsProvider: settingsProvider
        )
    }

    private struct HijriMonthKey: Hashable {
        let year: Int
        let month: Int
    }

    private func hijriComponents(for date: Date) -> DateComponents {
        hijriCalendar.dateComponents([.day, .month, .year], from: date)
    }

    private func hijriDayText(for date: Date) -> String? {
        hijriComponents(for: date).day.map(String.init)
    }

    private func hijriDisplayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = hijriCalendar
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
        return formatter
    }

    private func hijriMonthFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = hijriCalendar
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter
    }

    private func hijriMonthKey(for date: Date) -> HijriMonthKey? {
        let comps = hijriComponents(for: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        return HijriMonthKey(year: year, month: month)
    }

    private func hijriMonthYearDisplayText(for key: HijriMonthKey) -> String {
        var comps = DateComponents()
        comps.calendar = hijriCalendar
        comps.year = key.year
        comps.month = key.month
        comps.day = 1

        guard let date = hijriCalendar.date(from: comps) else {
            return "\(key.month). \(key.year)"
        }

        return hijriMonthFormatter().string(from: date)
    }

    func hijriDisplayText(for date: Date) -> String {
        hijriDisplayFormatter().string(from: date)
    }

    func monthGridDays(for monthDate: Date, selectedDate: Date) -> [IslamicCalendarDayItem] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthDate),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastMoment = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastMoment)
        else {
            return []
        }

        let visibleInterval = DateInterval(start: firstWeek.start, end: lastWeek.end)
        var dates: [Date] = []

        calendar.enumerateDates(
            startingAfter: visibleInterval.start.addingTimeInterval(-1),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) { date, _, stop in
            guard let date else { return }

            if date < visibleInterval.end {
                dates.append(date)
            } else {
                stop = true
            }
        }

        // Decode the prayer-times cache once for the whole visible grid
        // instead of once per day cell (a month view can have 35-42 cells).
        let cachedDays = prayerStore.loadAllDays(settings: settingsProvider())
        let isoFormatter = isoDateFormatter()

        return dates.map { date in
            let prayer = cachedDays[isoFormatter.string(from: date)]
            let dayEvents = allEventsForDay(date)
            let isHighlighted = dayEvents.contains { IslamicHolidayClassifier.isMajorHoliday($0, hijriCalendar: hijriCalendar) }

            return IslamicCalendarDayItem(
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: monthDate, toGranularity: .month),
                isToday: calendar.isDateInToday(date),
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                gregorianDayText: String(calendar.component(.day, from: date)),
                hijriText: hijriDayText(for: date),
                allEventsForDay: dayEvents,
                isHighlightedHoliday: isHighlighted,
                prayerDay: prayer
            )
        }
    }

    // Must match SharedPrayerTimesStore's internal ISO-date formatting exactly,
    // since the keys produced here are used to look up that store's cache.
    private func isoDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    func hijriMonthSummary(for monthDate: Date) -> String? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate) else {
            return nil
        }

        var current = monthInterval.start
        var orderedKeys: [HijriMonthKey] = []
        var seen = Set<HijriMonthKey>()

        while current < monthInterval.end {
            if let key = hijriMonthKey(for: current), !seen.contains(key) {
                seen.insert(key)
                orderedKeys.append(key)
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        guard !orderedKeys.isEmpty else { return nil }

        return orderedKeys
            .map(hijriMonthYearDisplayText(for:))
            .joined(separator: " / ")
    }
}

extension IslamicCalendarViewModel {
    private func isHolidayOverviewItem(_ day: IslamicSpecialDay) -> Bool {
        IslamicHolidayClassifier.isMajorHoliday(day, hijriCalendar: hijriCalendar)
    }

    private func mergedDays(for years: [Int]) -> [IslamicSpecialDay] {
        let merged = years
            .compactMap { IslamicHolidayClassifier.loadYearMigratingIfNeeded($0, store: calendarStore, hijriCalendar: hijriCalendar) }
            .flatMap { $0 }

        return deduplicated(days: merged)
    }

    private func deduplicated(days: [IslamicSpecialDay]) -> [IslamicSpecialDay] {
        var seen = Set<String>()

        return days
            .sorted { $0.sortDate < $1.sortDate }
            .filter { item in
                let gregorianDay = calendar.startOfDay(for: item.sortDate).timeIntervalSince1970
                let hijriKey = IslamicHolidayClassifier.hijriHolidayKey(for: item, hijriCalendar: hijriCalendar)
                let key = "\(gregorianDay)-\(hijriKey?.day ?? -1)-\(hijriKey?.month ?? -1)"
                return seen.insert(key).inserted
            }
    }

    private func missingYears(in years: [Int]) -> [Int] {
        years.filter { IslamicHolidayClassifier.loadYearMigratingIfNeeded($0, store: calendarStore, hijriCalendar: hijriCalendar) == nil }
    }

    private func fetchAndCache(year: Int) async throws -> [IslamicSpecialDay] {
        let fetched = try await service.fetchSpecialDays(forGregorianYear: year)
        let relevant = IslamicHolidayClassifier.filterRelevant(fetched, hijriCalendar: hijriCalendar)
        calendarStore.saveYear(year, days: relevant)
        return relevant
    }

    private func nextHoliday(after date: Date, in items: [IslamicSpecialDay]) -> IslamicSpecialDay? {
        let start = calendar.startOfDay(for: date)

        return items
            .sorted { $0.sortDate < $1.sortDate }
            .first { calendar.startOfDay(for: $0.sortDate) >= start }
    }

    private func visibleHolidayOverviewDays(
        in items: [IslamicSpecialDay],
        from referenceDate: Date,
        limit: Int = 8
    ) -> [IslamicSpecialDay] {
        let sortedItems = items.sorted { $0.sortDate < $1.sortDate }
        guard !sortedItems.isEmpty else { return [] }

        let start = calendar.startOfDay(for: referenceDate)

        guard let startIndex = sortedItems.firstIndex(where: {
            calendar.startOfDay(for: $0.sortDate) >= start
        }) else {
            return []
        }

        let endIndex = min(startIndex + limit, sortedItems.count)
        return Array(sortedItems[startIndex..<endIndex])
    }

    func loadHolidayOverview(around referenceDate: Date) async {
        let baseYear = calendar.component(.year, from: referenceDate)
        let requiredVisibleCount = 8
        let maxAdditionalYearsToLoad = 8

        var requestedYears = [baseYear - 1, baseYear, baseYear + 1]
        var merged: [IslamicSpecialDay] = []

        isHolidayOverviewLoading = true
        holidayOverviewErrorMessage = nil

        do {
            for year in missingYears(in: requestedYears) {
                _ = try await fetchAndCache(year: year)
            }

            merged = mergedDays(for: requestedYears)
                .filter(isHolidayOverviewItem(_:))
                .sorted { $0.sortDate < $1.sortDate }

            var nextYearToLoad = baseYear + 2
            let lastYearToLoad = baseYear + maxAdditionalYearsToLoad

            while (
                nextHoliday(after: referenceDate, in: merged) == nil ||
                visibleHolidayOverviewDays(
                    in: merged,
                    from: referenceDate,
                    limit: requiredVisibleCount
                ).count < requiredVisibleCount
            ) && nextYearToLoad <= lastYearToLoad {
                if !requestedYears.contains(nextYearToLoad) {
                    requestedYears.append(nextYearToLoad)
                }

                if IslamicHolidayClassifier.loadYearMigratingIfNeeded(nextYearToLoad, store: calendarStore, hijriCalendar: hijriCalendar) == nil {
                    _ = try await fetchAndCache(year: nextYearToLoad)
                }

                merged = mergedDays(for: requestedYears)
                    .filter(isHolidayOverviewItem(_:))
                    .sorted { $0.sortDate < $1.sortDate }

                nextYearToLoad += 1
            }

            holidayOverviewDays = merged
        } catch {
            holidayOverviewDays = merged
            holidayOverviewErrorMessage = error.localizedDescription
        }

        isHolidayOverviewLoading = false
    }

    func nextHoliday(after date: Date) -> IslamicSpecialDay? {
        nextHoliday(after: date, in: holidayOverviewDays)
    }

    func visibleHolidayOverviewDays(
        from referenceDate: Date,
        limit: Int = 8
    ) -> [IslamicSpecialDay] {
        visibleHolidayOverviewDays(in: holidayOverviewDays, from: referenceDate, limit: limit)
    }

    func featuredHoliday(for referenceDate: Date) -> IslamicSpecialDay? {
        visibleHolidayOverviewDays(from: referenceDate, limit: 1).first
    }

    func holidayFocusDays(around referenceDate: Date) -> [IslamicSpecialDay] {
        let items = holidayOverviewDays.sorted { $0.sortDate < $1.sortDate }
        guard !items.isEmpty else { return [] }

        let start = calendar.startOfDay(for: referenceDate)
        let upcomingIndex = items.firstIndex {
            calendar.startOfDay(for: $0.sortDate) >= start
        } ?? max(items.count - 1, 0)

        let candidateIndexes = [upcomingIndex - 1, upcomingIndex, upcomingIndex + 1]
            .filter { items.indices.contains($0) }

        var seen = Set<IslamicSpecialDay.ID>()
        return candidateIndexes.compactMap { index in
            let item = items[index]
            return seen.insert(item.id).inserted ? item : nil
        }
    }

    func isUpcomingHoliday(_ holiday: IslamicSpecialDay, referenceDate: Date) -> Bool {
        nextHoliday(after: referenceDate)?.id == holiday.id
    }

    func holidayGregorianText(for holiday: IslamicSpecialDay) -> String {
        holiday.gregorianReadable
    }

    func holidayHijriText(for holiday: IslamicSpecialDay) -> String {
        "\(holiday.hijriDay). \(holiday.hijriMonth) \(holiday.hijriYear)"
    }
}
