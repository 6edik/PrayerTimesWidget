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
    static let zakatIdentifierPrefix = "com.mertgedik.prayertimes.notif.zakat."
    static let qiratIdentifierPrefix = "com.mertgedik.prayertimes.notif.qirat."

    private let timesStore: SharedPrayerTimesStore
    private let settingsStore: SharedPrayerSettingsStore
    private let notificationSettingsStore: NotificationSettingsStore
    private let calendarStore: SharedIslamicCalendarStore
    private let calendarService: IslamicCalendarService
    private let personalCalendarStore: PersonalCalendarStore
    private let center: UNUserNotificationCenter
    private let hijriCalendar: Calendar
    private let deviceCalendar: Calendar

    init(
        timesStore: SharedPrayerTimesStore = SharedPrayerTimesStore(),
        settingsStore: SharedPrayerSettingsStore = SharedPrayerSettingsStore(),
        notificationSettingsStore: NotificationSettingsStore = NotificationSettingsStore(),
        calendarStore: SharedIslamicCalendarStore = SharedIslamicCalendarStore(),
        calendarService: IslamicCalendarService = IslamicCalendarService(),
        personalCalendarStore: PersonalCalendarStore = PersonalCalendarStore(),
        center: UNUserNotificationCenter = .current()
    ) {
        self.timesStore = timesStore
        self.settingsStore = settingsStore
        self.notificationSettingsStore = notificationSettingsStore
        self.calendarStore = calendarStore
        self.calendarService = calendarService
        self.personalCalendarStore = personalCalendarStore
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
                || notificationSettings.hasAnyZakatEnabled
                || notificationSettings.hasAnyQiratEnabled
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

        if notificationSettings.hasAnyZakatEnabled {
            candidates += zakatCandidates(settings: notificationSettings, now: now)
        }

        if notificationSettings.hasAnyQiratEnabled {
            candidates += qiratCandidates(settings: notificationSettings)
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

                let displayName = self.displayName(for: kind, isoDate: isoDate, timezoneIdentifier: day.times.timezone)

                result.append(NotificationCandidate(
                    identifier: "\(Self.prayerIdentifierPrefix)\(kind.rawValue).\(isoDate).start",
                    fireDate: fireDate,
                    title: displayName,
                    body: "Es ist Zeit für \(displayName).",
                    sound: config.sound
                ))

                if config.reminderLeadTime != .none {
                    let reminderDate = fireDate.addingTimeInterval(-Double(config.reminderLeadTime.rawValue * 60))

                    result.append(NotificationCandidate(
                        identifier: "\(Self.prayerIdentifierPrefix)\(kind.rawValue).\(isoDate).reminder",
                        fireDate: reminderDate,
                        title: displayName,
                        body: "\(displayName) beginnt in \(config.reminderLeadTime.rawValue) Minuten.",
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

    /// The name shown in the actual fired notification for `kind` on this
    /// specific `isoDate` — "Jum'ah" instead of "Dhuhr" on a Friday, judged
    /// by the cached day's own location timezone. `PrayerNotificationKind
    /// .displayName` itself (used generically in the settings toggle list,
    /// not tied to any specific occurrence) stays untouched.
    private func displayName(for kind: PrayerNotificationKind, isoDate: String, timezoneIdentifier: String) -> String {
        guard kind == .dhuhr, let dayStart = PrayerMomentResolver.dayStart(isoDate: isoDate, timezoneIdentifier: timezoneIdentifier) else {
            return kind.displayName
        }
        return PrayerDisplayNaming.dhuhrLabel(date: dayStart, timezoneIdentifier: timezoneIdentifier)
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

    private func isoKey(_ date: Date, calendar: Calendar? = nil) -> String {
        let cal = calendar ?? deviceCalendar
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = cal.timeZone
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

            // Only the occasion and the estimated duration — no Fajr/
            // Maghrib clock times in the notification body. The duration
            // is still computed from the fasting day's own adjusted Fajr
            // and Maghrib (via the shared `FastingDurationCalculator`,
            // full Dates through `PrayerMomentResolver`, so a midnight-
            // crossing adjustment is handled correctly, never a naive
            // HH:mm string diff) — the same calculation the calendar day
            // sheet uses, so the two can never quietly disagree. If either
            // time fails to resolve (a malformed stored time, an invalid
            // timezone), the duration sentence is omitted entirely rather
            // than inventing one. The reminder still fires with just the
            // plain occasion sentence in that case (documented in the
            // settings UI's "Hinweis" section).
            let duration: String?
            if let fastingResult = FastingDurationCalculator.result(
                isoDate: iso, times: day.times, adjustments: autoSettings.adjustments
            ) {
                duration = FastingDurationCalculator.formattedDuration(fastingResult.duration)
            } else {
                duration = nil
            }

            result.append(NotificationCandidate(
                identifier: "\(Self.fastingIdentifierPrefix)\(iso)",
                fireDate: fireDate,
                title: "Morgen: freiwilliges Fasten",
                body: Self.fastingBody(occasions: occasions, duration: duration),
                sound: fastingSettings.sound
            ))
        }

        return result
    }

    private static func fastingBody(occasions: VoluntaryFastingOccasions, duration: String?) -> String {
        let occasionSentence = "Morgen ist \(occasions.displayLabel)."
        guard let duration else { return occasionSentence }
        return "\(occasionSentence) Fastendauer: ca. \(duration)."
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

    // MARK: - Zakat candidates

    /// Reminders for the user's own Zakat-due-date entries
    /// (`PersonalCalendarEntry` with `kind == .zakatDueDate`). Never
    /// computes or checks whether Zakat is actually owed — purely a
    /// personal reminder for a Hijri day/month the user chose themselves.
    /// The note text itself is never included in the notification body
    /// (spec item 10): the body is always the same neutral sentence.
    ///
    /// Every Zakat entry recurs every Hijri year — there is no one-time
    /// variant. `ZakatOccurrenceCalculator.upcomingOccurrences` expands
    /// the entry's fixed (day, month) rule into several upcoming concrete
    /// dates (already bounded and gap-safe — see that type). Each
    /// candidate's identifier is keyed by the entry's stable `id` plus
    /// that specific occurrence's ISO date, so editing an entry's rule and
    /// calling `reschedule()` again (which always removes every
    /// previously-owned request first) can never leave a stale or
    /// duplicate Zakat reminder behind.
    ///
    /// Uses the *configured prayer location's* own timezone — not the
    /// device's — for both the day boundary and the reminder's clock time,
    /// taken from whatever prayer data is already cached for the current
    /// location (same source `fastingCandidates` uses); falls back to the
    /// device's timezone only if nothing is cached yet, rather than
    /// inventing one.
    func zakatCandidates(settings: NotificationSettings, now: Date = Date()) -> [NotificationCandidate] {
        let zakatSettings = settings.zakat
        guard zakatSettings.isEnabled else { return [] }

        let zakatEntries = personalCalendarStore.loadAll().filter { $0.kind == .zakatDueDate }
        guard !zakatEntries.isEmpty else { return [] }

        let autoSettings = settingsStore.loadAutoSettings()
        let cachedDays = timesStore.loadAllDays(settings: autoSettings)
        let locationTimeZone = cachedDays.values.first.flatMap { TimeZone(identifier: $0.times.timezone) } ?? .current

        var locationCalendar = Calendar(identifier: .gregorian)
        locationCalendar.timeZone = locationTimeZone
        let locationHijriCalendar = HijriDateFormatting.calendar(timeZone: locationTimeZone)

        var result: [NotificationCandidate] = []

        for entry in zakatEntries {
            guard let day = entry.hijriDay, let month = entry.hijriMonth else { continue }

            let occurrences = ZakatOccurrenceCalculator.upcomingOccurrences(
                hijriDay: day,
                hijriMonth: month,
                now: now,
                hijriCalendar: locationHijriCalendar
            )

            for occurrence in occurrences {
                let dayStart = locationCalendar.startOfDay(for: occurrence)
                let occurrenceKey = isoKey(dayStart, calendar: locationCalendar)

                if let fireDate = locationCalendar.date(bySettingHour: zakatSettings.hour, minute: zakatSettings.minute, second: 0, of: dayStart) {
                    result.append(NotificationCandidate(
                        identifier: "\(Self.zakatIdentifierPrefix)\(entry.id.uuidString).\(occurrenceKey).onday",
                        fireDate: fireDate,
                        title: "Zakat-Stichtag",
                        body: "Dein eingetragener Zakat-Stichtag ist heute. Prüfe deine Zakat-Berechnung.",
                        sound: .standard
                    ))
                }

                if zakatSettings.notifyDayBefore,
                   let dayBefore = locationCalendar.date(byAdding: .day, value: -1, to: dayStart),
                   let fireDate = locationCalendar.date(bySettingHour: zakatSettings.hour, minute: zakatSettings.minute, second: 0, of: dayBefore) {
                    result.append(NotificationCandidate(
                        identifier: "\(Self.zakatIdentifierPrefix)\(entry.id.uuidString).\(occurrenceKey).before",
                        fireDate: fireDate,
                        title: "Zakat-Stichtag",
                        body: "Morgen ist dein eingetragener Zakat-Stichtag. Prüfe deine Zakat-Berechnung.",
                        sound: .standard
                    ))
                }
            }
        }

        return result
    }

    // MARK: - Karāha candidates

    /// One candidate per cached day for the Sonnenaufgangs-Karāha window
    /// (starts exactly at Shuruk, never Fajr), and one for the Karāha-vor-
    /// Maghrib **approximation** (see `QiratTimeResolver`'s doc comment)
    /// — firing right at each window's own start. Both bodies are
    /// deliberately short (no fiqh explanation in the push banner — that
    /// belongs in the settings' info view instead). The pre-Maghrib body
    /// never claims Asr itself is impermissible: Asr remains valid until
    /// Maghrib; it only encourages not postponing it, and only where the
    /// approximation is latitude-plausible. A day with no resolvable
    /// window (missing/malformed cached times, or an out-of-range
    /// latitude) simply contributes nothing for that day, never a guessed
    /// time.
    ///
    /// Identifiers are stable across reschedules (`isoDate` + which
    /// window), and `reschedule()` always removes every previously-owned
    /// request under `qiratIdentifierPrefix` before rebuilding — so a
    /// stale "afterFajr"/"beforeMaghrib"-suffixed request from an earlier
    /// version of this feature (when the sunrise window was wrongly
    /// anchored to Fajr instead of Shuruk, or the pre-Maghrib window to
    /// Asr) is cleaned up the exact same way as any other request under
    /// this prefix, without touching prayer/holiday/fasting/zakat
    /// requests, which live under entirely separate prefixes.
    func qiratCandidates(settings: NotificationSettings, now: Date = Date()) -> [NotificationCandidate] {
        guard settings.qirat.isEnabled else { return [] }

        let autoSettings = settingsStore.loadAutoSettings()
        let cachedDays = timesStore.loadAllDays(settings: autoSettings)
        guard !cachedDays.isEmpty else { return [] }

        let latitude = autoSettings.location?.coordinate.latitude

        var result: [NotificationCandidate] = []

        for (isoDate, day) in cachedDays {
            guard let dayStart = PrayerMomentResolver.dayStart(isoDate: isoDate, timezoneIdentifier: day.times.timezone) else {
                continue
            }

            let windows = QiratTimeResolver.windows(
                base: dayStart,
                times: day.times,
                adjustments: autoSettings.adjustments,
                latitude: latitude,
                lateKerahetOffsetMinutes: autoSettings.lateKerahetOffsetMinutes,
                sunriseKarahaOffsetMinutes: autoSettings.sunriseKarahaOffsetMinutes
            )

            if let sunrise = windows.sunriseKaraha {
                let endClock = FastingDurationCalculator.clockString(sunrise.end, timezoneIdentifier: sunrise.timezoneIdentifier)
                result.append(NotificationCandidate(
                    identifier: "\(Self.qiratIdentifierPrefix)sunriseKaraha.\(isoDate)",
                    fireDate: sunrise.start,
                    title: "Karāha",
                    body: "Sonnenaufgang: Gebetspause bis ca. \(endClock).",
                    sound: settings.qirat.sound
                ))
            }

            if let lateMaghrib = windows.lateMaghribKaraha {
                result.append(NotificationCandidate(
                    identifier: "\(Self.qiratIdentifierPrefix)lateMaghribKaraha.\(isoDate)",
                    fireDate: lateMaghrib.start,
                    title: "Karāha vor Maghrib",
                    body: "Maghrib nähert sich. Asr nicht aufschieben.",
                    sound: settings.qirat.sound
                ))
            }
        }

        return result
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
            || identifier.hasPrefix(Self.zakatIdentifierPrefix)
            || identifier.hasPrefix(Self.qiratIdentifierPrefix)
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
