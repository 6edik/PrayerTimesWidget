import Foundation
import UserNotifications

/// One candidate notification with everything needed to schedule it.
/// Internal (not private) and `Equatable` so the pure selection logic below
/// is unit-testable without touching `UNUserNotificationCenter`.
struct NotificationCandidate: Equatable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
    let sound: NotificationSoundOption

    /// iOS caps an app at 64 pending local notifications. Given a pool of
    /// candidates (prayers + holidays together) and how much of that
    /// budget is actually available, keep only future ones, nearest first,
    /// up to the budget — exactly "priorisiere nahe Termine" from the spec.
    static func prioritized(from candidates: [NotificationCandidate], budget: Int, now: Date) -> [NotificationCandidate] {
        guard budget > 0 else { return [] }

        return candidates
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(budget)
            .map { $0 }
    }
}

/// Central place that owns every notification PrayerTimes ever schedules.
/// Rebuilds its own pending requests from scratch on every call — safe to
/// call often (app active, after a successful refresh, after a settings
/// change) since it never touches a request it didn't create itself.
struct NotificationScheduler {
    static let maxPendingNotifications = 64

    // Stable, app-owned identifier prefixes — used both to build request
    // IDs and to recognize (and only remove) PrayerTimes' own pending
    // requests among whatever else might be scheduled.
    static let prayerIdentifierPrefix = "com.mertgedik.prayertimes.notif.prayer."
    static let holidayIdentifierPrefix = "com.mertgedik.prayertimes.notif.holiday."
    static let fastingIdentifierPrefix = "com.mertgedik.prayertimes.notif.fasting."

    private let timesStore: SharedPrayerTimesStore
    private let settingsStore: SharedPrayerSettingsStore
    private let notificationSettingsStore: NotificationSettingsStore
    private let calendarStore: SharedIslamicCalendarStore
    private let calendarService: IslamicCalendarService
    private let center: UNUserNotificationCenter
    private let hijriCalendar: Calendar
    private let deviceCalendar: Calendar

    init(
        timesStore: SharedPrayerTimesStore = SharedPrayerTimesStore(),
        settingsStore: SharedPrayerSettingsStore = SharedPrayerSettingsStore(),
        notificationSettingsStore: NotificationSettingsStore = NotificationSettingsStore(),
        calendarStore: SharedIslamicCalendarStore = SharedIslamicCalendarStore(),
        calendarService: IslamicCalendarService = IslamicCalendarService(),
        center: UNUserNotificationCenter = .current()
    ) {
        self.timesStore = timesStore
        self.settingsStore = settingsStore
        self.notificationSettingsStore = notificationSettingsStore
        self.calendarStore = calendarStore
        self.calendarService = calendarService
        self.center = center

        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.locale = .autoupdatingCurrent
        hijri.timeZone = .autoupdatingCurrent
        self.hijriCalendar = hijri

        var device = Calendar(identifier: .gregorian)
        device.locale = .autoupdatingCurrent
        device.timeZone = .autoupdatingCurrent
        self.deviceCalendar = device
    }

    /// Removes every PrayerTimes-scheduled notification and rebuilds it
    /// from the current notification settings + whatever prayer/holiday
    /// data is actually cached right now. If the cache doesn't match the
    /// current location (address/method changed, or nothing cached yet),
    /// `loadAllDays` naturally returns nothing for it — so a stale time
    /// can never end up re-scheduled here.
    func reschedule(now: Date = Date()) async {
        await removeAllOwnPendingRequests()

        let notificationSettings = notificationSettingsStore.load()
        guard
            notificationSettings.hasAnyPrayerEnabled
                || notificationSettings.hasAnyHolidayEnabled
                || notificationSettings.hasAnyVoluntaryFastingEnabled
        else {
            return
        }

        let systemSettings = await center.notificationSettings()
        guard systemSettings.authorizationStatus == .authorized
            || systemSettings.authorizationStatus == .provisional else {
            return
        }

        var candidates: [NotificationCandidate] = []

        if notificationSettings.hasAnyPrayerEnabled {
            candidates += prayerCandidates(settings: notificationSettings)
        }

        if notificationSettings.hasAnyHolidayEnabled {
            candidates += await holidayCandidates(settings: notificationSettings, now: now)
        }

        if notificationSettings.hasAnyVoluntaryFastingEnabled {
            candidates += fastingCandidates(settings: notificationSettings)
        }

        let budget = await remainingBudget()
        let toSchedule = NotificationCandidate.prioritized(from: candidates, budget: budget, now: now)

        for candidate in toSchedule {
            await schedule(candidate)
        }
    }

    // MARK: - Prayer candidates

    func prayerCandidates(settings: NotificationSettings, now: Date = Date()) -> [NotificationCandidate] {
        let autoSettings = settingsStore.loadAutoSettings()
        let cachedDays = timesStore.loadAllDays(settings: autoSettings)
        guard !cachedDays.isEmpty else { return [] }

        var result: [NotificationCandidate] = []

        for kind in PrayerNotificationKind.allCases {
            let config = settings.setting(for: kind)
            guard config.isEnabled else { continue }

            let adjustmentMinutes = adjustmentMinutes(for: kind, in: autoSettings.adjustments)

            for (isoDate, day) in cachedDays {
                let rawTime = rawTime(for: kind, in: day.times)

                guard let fireDate = PrayerMomentResolver.resolve(
                    isoDate: isoDate,
                    rawTime: rawTime,
                    adjustmentMinutes: adjustmentMinutes,
                    timezoneIdentifier: day.times.timezone
                ) else { continue }

                result.append(NotificationCandidate(
                    identifier: "\(Self.prayerIdentifierPrefix)\(kind.rawValue).\(isoDate).start",
                    fireDate: fireDate,
                    title: kind.displayName,
                    body: "Es ist Zeit für \(kind.displayName).",
                    sound: config.sound
                ))

                if config.reminderLeadTime != .none {
                    let reminderDate = fireDate.addingTimeInterval(-Double(config.reminderLeadTime.rawValue * 60))

                    result.append(NotificationCandidate(
                        identifier: "\(Self.prayerIdentifierPrefix)\(kind.rawValue).\(isoDate).reminder",
                        fireDate: reminderDate,
                        title: kind.displayName,
                        body: "\(kind.displayName) beginnt in \(config.reminderLeadTime.rawValue) Minuten.",
                        sound: config.sound
                    ))
                }
            }
        }

        return result
    }

    private func rawTime(for kind: PrayerNotificationKind, in times: PrayerTimes) -> String {
        switch kind {
        case .fajr: return times.fajr
        case .dhuhr: return times.dhuhr
        case .asr: return times.asr
        case .maghrib: return times.maghrib
        case .isha: return times.isha
        }
    }

    private func adjustmentMinutes(for kind: PrayerNotificationKind, in adjustments: PrayerAdjustments) -> Int {
        switch kind {
        case .fajr: return adjustments.fajr
        case .dhuhr: return adjustments.dhuhr
        case .asr: return adjustments.asr
        case .maghrib: return adjustments.maghrib
        case .isha: return adjustments.isha
        }
    }

    // MARK: - Holiday candidates

    func holidayCandidates(settings: NotificationSettings, now: Date = Date()) async -> [NotificationCandidate] {
        let currentYear = deviceCalendar.component(.year, from: now)
        let years = [currentYear, currentYear + 1]

        var allDays: [IslamicSpecialDay] = []
        for year in years {
            // Migrates an already-cached year written before the curated-
            // holiday filter existed (e.g. still containing "Urs of …"/
            // "Birth of …" entries) the first time it's touched, purely
            // offline — never conflated with "nothing cached", which falls
            // through to a fresh fetch below.
            if let cached = IslamicHolidayClassifier.loadYearMigratingIfNeeded(year, store: calendarStore, hijriCalendar: hijriCalendar) {
                allDays += cached
            } else if let fetched = try? await calendarService.fetchSpecialDays(forGregorianYear: year) {
                // Filter to the curated holidays before persisting — never
                // store (or match candidates against) AlAdhan's raw,
                // unfiltered response.
                let relevant = IslamicHolidayClassifier.filterRelevant(fetched, hijriCalendar: hijriCalendar)
                calendarStore.saveYear(year, days: relevant)
                allDays += relevant
            }
        }

        var result: [NotificationCandidate] = []

        for holiday in MajorIslamicHoliday.allCases {
            let config = settings.setting(for: holiday)
            guard config.isEnabled, !config.isConfigurationUseless else { continue }

            // Same Gregorian-day attachment the calendar tab uses for this
            // holiday (`sortDate`, device-local Gregorian day) — never a
            // different day than what the app's calendar actually shows.
            let matches = allDays.filter {
                IslamicHolidayClassifier.hijriHolidayKey(for: $0, hijriCalendar: hijriCalendar) == holiday.hijriKey
            }

            for match in matches {
                let dayStart = deviceCalendar.startOfDay(for: match.sortDate)

                if config.notifyOnDay,
                   let fireDate = deviceCalendar.date(bySettingHour: config.hour, minute: config.minute, second: 0, of: dayStart) {
                    result.append(NotificationCandidate(
                        identifier: "\(Self.holidayIdentifierPrefix)\(holiday.rawValue).\(isoKey(dayStart)).onday",
                        fireDate: fireDate,
                        title: holiday.displayName,
                        body: "Heute: \(holiday.displayName).",
                        sound: .standard
                    ))
                }

                if config.notifyDayBefore,
                   let dayBefore = deviceCalendar.date(byAdding: .day, value: -1, to: dayStart),
                   let fireDate = deviceCalendar.date(bySettingHour: config.hour, minute: config.minute, second: 0, of: dayBefore) {
                    result.append(NotificationCandidate(
                        identifier: "\(Self.holidayIdentifierPrefix)\(holiday.rawValue).\(isoKey(dayBefore)).before",
                        fireDate: fireDate,
                        title: holiday.displayName,
                        body: "Morgen: \(holiday.displayName).",
                        sound: .standard
                    ))
                }
            }
        }

        return result
    }

    private func isoKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = deviceCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = deviceCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Voluntary-fasting candidates

    /// Cache-first, single-reminder-per-day scheduling for the app's three
    /// voluntary-fasting occasions (Monday, Thursday, White Days — see
    /// `VoluntaryFastingClassifier`).
    ///
    /// For every day cached in the shared Auto-Cache (already validated
    /// against the *current* `AutoPrayerSettings` by `loadAllDays`, so a
    /// stale cache from a previous city/method never contributes a
    /// candidate here either — same guarantee `prayerCandidates` relies
    /// on):
    /// - classify it using the *location's own* timezone (each cached day
    ///   carries its own `PrayerTimes.timezone` from the AlAdhan response),
    ///   never the device's, so a Monday/White-Day decision near local
    ///   midnight can't be shifted a day by an unrelated device timezone;
    /// - skip it entirely if fasting is religiously inappropriate that day
    ///   (Ramadan, the two Eids, or Tashriq — `isExcludedFromVoluntaryFasting`);
    /// - skip it if none of the *enabled* toggles match;
    /// - otherwise schedule exactly one reminder, at the previous calendar
    ///   day's (the "eve's") Maghrib plus the configured offset — a Monday
    ///   reminder is anchored to Sunday's Maghrib, never Monday's own,
    ///   which is the whole point of "the evening before". If the eve
    ///   itself isn't cached (no Maghrib to anchor to), this day is
    ///   skipped — there is no sane fallback fire time to invent.
    func fastingCandidates(settings: NotificationSettings, now: Date = Date()) -> [NotificationCandidate] {
        let fastingSettings = settings.voluntaryFasting
        guard fastingSettings.hasAnyEnabled else { return [] }

        let autoSettings = settingsStore.loadAutoSettings()
        let cachedDays = timesStore.loadAllDays(settings: autoSettings)
        guard !cachedDays.isEmpty else { return [] }

        var result: [NotificationCandidate] = []

        for (iso, day) in cachedDays {
            guard let dayStart = PrayerMomentResolver.dayStart(
                isoDate: iso,
                timezoneIdentifier: day.times.timezone
            ) else { continue }

            let locationTimeZone = TimeZone(identifier: day.times.timezone) ?? .current

            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = locationTimeZone
            let hijri = HijriDateFormatting.calendar(timeZone: locationTimeZone)

            guard !VoluntaryFastingClassifier.isExcludedFromVoluntaryFasting(date: dayStart, hijriCalendar: hijri) else {
                continue
            }

            let matched = VoluntaryFastingClassifier.occasions(for: dayStart, gregorianCalendar: gregorian, hijriCalendar: hijri)
            var occasions: VoluntaryFastingOccasions = []
            if fastingSettings.monday, matched.contains(.monday) { occasions.insert(.monday) }
            if fastingSettings.thursday, matched.contains(.thursday) { occasions.insert(.thursday) }
            if fastingSettings.whiteDays, matched.contains(.whiteDay) { occasions.insert(.whiteDay) }
            guard !occasions.isEmpty else { continue }

            guard
                let eveISO = previousISODate(iso),
                let eveDay = cachedDays[eveISO],
                let eveMaghrib = PrayerMomentResolver.resolve(
                    isoDate: eveISO,
                    rawTime: eveDay.times.maghrib,
                    adjustmentMinutes: autoSettings.adjustments.maghrib,
                    timezoneIdentifier: eveDay.times.timezone
                )
            else { continue }

            let fireDate = eveMaghrib.addingTimeInterval(Double(fastingSettings.minutesAfterMaghrib) * 60)

            // The "Fajr X bis Maghrib Y – Z Std." sentence is for the
            // fasting day itself, computed from full Dates (via
            // PrayerMomentResolver, so a midnight-crossing adjustment is
            // handled correctly) rather than a naive HH:mm string diff.
            // Both the displayed clock times *and* the duration come from
            // these same resolved Dates — if either fails to resolve (a
            // malformed stored time, an invalid timezone), the entire
            // sentence is omitted rather than showing a broken clock time
            // next to no duration, or inventing either one. The reminder
            // still fires with just the plain occasion sentence in that
            // case (documented in the settings UI's "Hinweis" section).
            let timesSentence: String?
            if
                let fajrDate = PrayerMomentResolver.resolve(
                    isoDate: iso, rawTime: day.times.fajr,
                    adjustmentMinutes: autoSettings.adjustments.fajr, timezoneIdentifier: day.times.timezone
                ),
                let maghribDate = PrayerMomentResolver.resolve(
                    isoDate: iso, rawTime: day.times.maghrib,
                    adjustmentMinutes: autoSettings.adjustments.maghrib, timezoneIdentifier: day.times.timezone
                ),
                maghribDate > fajrDate
            {
                let clockFormatter = DateFormatter()
                clockFormatter.calendar = gregorian
                clockFormatter.locale = Locale(identifier: "en_US_POSIX")
                clockFormatter.timeZone = locationTimeZone
                clockFormatter.dateFormat = "HH:mm"

                // `duration` already ends in "Std." or "Min." — no extra
                // trailing period, or the sentence would end in "..".
                let duration = Self.formattedDuration(from: fajrDate, to: maghribDate)
                timesSentence = "Voraussichtliche Fastenzeit: Fajr \(clockFormatter.string(from: fajrDate)) bis Maghrib \(clockFormatter.string(from: maghribDate)) – \(duration)"
            } else {
                timesSentence = nil
            }

            result.append(NotificationCandidate(
                identifier: "\(Self.fastingIdentifierPrefix)\(iso)",
                fireDate: fireDate,
                title: "Morgen: freiwilliges Fasten",
                body: Self.fastingBody(occasions: occasions, timesSentence: timesSentence),
                sound: fastingSettings.sound
            ))
        }

        return result
    }

    private static func fastingBody(occasions: VoluntaryFastingOccasions, timesSentence: String?) -> String {
        let occasionSentence = "Morgen ist \(occasions.displayLabel)."
        guard let timesSentence else { return occasionSentence }
        return "\(occasionSentence) \(timesSentence)"
    }

    /// "15 Std. 40 Min." — or just "15 Std." when there are no leftover
    /// minutes, matching the spec's own example text.
    private static func formattedDuration(from start: Date, to end: Date) -> String {
        let totalMinutes = Int((end.timeIntervalSince(start) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) Std." : "\(hours) Std. \(minutes) Min."
    }

    /// The ISO ("yyyy-MM-dd") date string one calendar day before `iso`,
    /// correctly handling month/year rollover. Pure calendar-component
    /// arithmetic on the date *label* itself — deliberately timezone-
    /// independent (any fixed zone works as long as parsing and formatting
    /// use the same one), unlike `PrayerMomentResolver`, which resolves a
    /// label to a real absolute instant in a specific location's timezone.
    private func previousISODate(_ iso: String) -> String? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        guard
            let date = formatter.date(from: iso),
            let previous = utc.date(byAdding: .day, value: -1, to: date)
        else { return nil }

        return formatter.string(from: previous)
    }

    // MARK: - UNUserNotificationCenter plumbing

    private func remainingBudget() async -> Int {
        let pending = await center.pendingNotificationRequests()
        let otherCount = pending.filter { !isOwnIdentifier($0.identifier) }.count
        return max(0, Self.maxPendingNotifications - otherCount)
    }

    private func removeAllOwnPendingRequests() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter(isOwnIdentifier)
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func isOwnIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(Self.prayerIdentifierPrefix)
            || identifier.hasPrefix(Self.holidayIdentifierPrefix)
            || identifier.hasPrefix(Self.fastingIdentifierPrefix)
    }

    private func schedule(_ candidate: NotificationCandidate) async {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = candidate.sound == .silent ? nil : .default

        let interval = max(1, candidate.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: candidate.identifier, content: content, trigger: trigger)

        try? await center.add(request)
    }
}
