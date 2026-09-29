import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `NotificationScheduler.zakatCandidates` — the pure, testable
/// candidate builder (same convention `NotificationSchedulerCandidateTests`
/// uses for prayer/holiday candidates: no live `UNUserNotificationCenter`
/// needed here). Every Zakat entry is defined by a fixed Hijri (day,
/// month) rule and always recurs every Hijri year — there is no one-time
/// variant and no Gregorian-anchor-based repeat.
///
/// What `reschedule()` does with these candidates (removing every
/// previously-owned request before rebuilding, checking system
/// authorization, respecting the 64-notification budget) is shared,
/// unchanged machinery already exercised for prayer/holiday/fasting
/// candidates — extending `isOwnIdentifier`/`removeAllOwnPendingRequests`
/// with the Zakat prefix reuses that same guarantee rather than
/// duplicating it, so "no duplicates after repeated reschedule", "stale
/// requests removed when disabled or permission is revoked", and "other
/// categories untouched" aren't independently re-tested against a live
/// center here.
@MainActor
struct NotificationSchedulerZakatTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteNames: [String]) {
        for suite in suiteNames {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private func makeScheduler(
        personalCalendarSuite: String,
        timesStore: SharedPrayerTimesStore? = nil,
        settingsStore: SharedPrayerSettingsStore? = nil
    ) -> NotificationScheduler {
        NotificationScheduler(
            timesStore: timesStore ?? SharedPrayerTimesStore(suiteName: makeSuiteName()),
            settingsStore: settingsStore ?? SharedPrayerSettingsStore(suiteName: makeSuiteName()),
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: SharedIslamicCalendarStore(suiteName: makeSuiteName()),
            personalCalendarStore: PersonalCalendarStore(suiteName: personalCalendarSuite)
        )
    }

    private func zakatSettings(isEnabled: Bool, notifyDayBefore: Bool = false, hour: Int = 9, minute: Int = 0) -> NotificationSettings {
        var settings = NotificationSettings.zero
        settings.zakat = ZakatNotificationSetting(isEnabled: isEnabled, notifyDayBefore: notifyDayBefore, hour: hour, minute: minute)
        return settings
    }

    private var hijriCalendar: Calendar {
        HijriDateFormatting.calendar()
    }

    // MARK: - Disabled switch

    @Test func disabledZakatSwitchProducesNoCandidatesEvenWithEntries() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        store.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: false))
        #expect(candidates.isEmpty)
    }

    // MARK: - Plain notes are ignored

    @Test func plainNotesNeverProduceZakatCandidates() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        store.upsert(PersonalCalendarEntry(note: "Nur eine Notiz", isoDate: "2027-05-01"))

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true))
        #expect(candidates.isEmpty)
    }

    // MARK: - Every Zakat entry recurs — several years produce several on-day candidates

    @Test func zakatEntryProducesOneOnDayCandidatePerUpcomingHijriYear() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        let entry = PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9)
        store.upsert(entry)

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, hour: 8, minute: 30))

        // Default `ZakatOccurrenceCalculator` limit is 3 upcoming years.
        #expect(candidates.count == 3)
        #expect(candidates.allSatisfy { $0.identifier.hasSuffix(".onday") })
        #expect(candidates.allSatisfy { $0.identifier.hasPrefix(NotificationScheduler.zakatIdentifierPrefix) })
        #expect(candidates.allSatisfy { $0.identifier.contains(entry.id.uuidString) })

        // Distinct occurrence keys — never the same Gregorian date twice.
        #expect(Set(candidates.map(\.identifier)).count == 3)

        // Always the same fixed, neutral sentence — never the entry's own
        // note text (spec item 10).
        #expect(candidates.allSatisfy { $0.body == "Dein eingetragener Zakat-Stichtag ist heute. Prüfe deine Zakat-Berechnung." })
    }

    @Test func dayBeforeToggleAddsASecondCandidatePerOccurrence() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        store.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, notifyDayBefore: true))

        #expect(candidates.count == 6) // 3 onday + 3 before
        #expect(candidates.filter { $0.identifier.hasSuffix(".onday") }.count == 3)
        #expect(candidates.filter { $0.identifier.hasSuffix(".before") }.count == 3)

        for onday in candidates.filter({ $0.identifier.hasSuffix(".onday") }) {
            let before = try #require(candidates.first {
                $0.identifier == onday.identifier.replacingOccurrences(of: ".onday", with: ".before")
            })
            #expect(before.fireDate < onday.fireDate)
            let interval = onday.fireDate.timeIntervalSince(before.fireDate)
            #expect(abs(interval - 24 * 60 * 60) < 1)
        }
    }

    // MARK: - Stable identifiers across repeated calls (no duplicates)

    @Test func repeatedCallsProduceIdenticalCandidatesNeverDuplicates() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        store.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 15, hijriMonth: 6))

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let settings = zakatSettings(isEnabled: true, notifyDayBefore: true)

        let first = scheduler.zakatCandidates(settings: settings)
        let second = scheduler.zakatCandidates(settings: settings)

        #expect(first == second)
        #expect(Set(first.map(\.identifier)).count == first.count)
    }

    // MARK: - Editing/deleting reflects immediately in the next build

    @Test func deletingTheEntryRemovesItFromTheNextCandidateBuild() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        let entry = PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9)
        store.upsert(entry)

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        #expect(!scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).isEmpty)

        store.delete(id: entry.id)
        #expect(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).isEmpty)
    }

    @Test func changingTheHijriRuleChangesTheCandidatesIdentifiers() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        var entry = PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9)
        store.upsert(entry)

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let before = Set(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).map(\.identifier))

        entry.hijriDay = 20
        entry.hijriMonth = 12
        store.upsert(entry)

        let after = Set(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).map(\.identifier))
        #expect(before.isDisjoint(with: after))
    }

    @Test func changingTheReminderTimeChangesTheFireDateNotTheDay() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = PersonalCalendarStore(suiteName: suite)
        store.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(personalCalendarSuite: suite)
        let before = try #require(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, hour: 9, minute: 0)).first)
        let after = try #require(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, hour: 14, minute: 15)).first)

        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = .current
        let beforeComps = deviceCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: before.fireDate)
        let afterComps = deviceCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: after.fireDate)

        #expect(beforeComps.year == afterComps.year && beforeComps.month == afterComps.month && beforeComps.day == afterComps.day)
        #expect(afterComps.hour == 14 && afterComps.minute == 15)
    }

    // MARK: - Identifier-prefix isolation from other notification categories

    @Test func zakatPrefixNeverCollidesWithOtherCategoryPrefixes() async throws {
        let prefixes = [
            NotificationScheduler.prayerIdentifierPrefix,
            NotificationScheduler.holidayIdentifierPrefix,
            NotificationScheduler.fastingIdentifierPrefix,
            NotificationScheduler.zakatIdentifierPrefix,
        ]

        for a in prefixes {
            for b in prefixes where a != b {
                #expect(!a.hasPrefix(b))
                #expect(!b.hasPrefix(a))
            }
        }
    }

    // MARK: - Location timezone used for the reminder's clock time (spec item 7)

    @Test func usesTheConfiguredLocationsTimeZoneNotTheDevicesForTheFireTime() async throws {
        let personalSuite = makeSuiteName()
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([personalSuite, timesSuite, settingsSuite]) }

        let store = PersonalCalendarStore(suiteName: personalSuite)
        store.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9))

        // A location far from the device's own timezone (Tokyo, UTC+9),
        // via one cached prayer day carrying that timezone identifier —
        // the same source `fastingCandidates` reads from.
        let autoSettings = AutoPrayerSettings(
            address: "Tokyo, Japan",
            location: PrayerLocation(name: "Tokyo, Japan", coordinate: GeoCoordinate(latitude: 35.6762, longitude: 139.6503)),
            method: .ditib,
            adjustments: .zero
        )
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        settingsStore.saveAutoSettings(autoSettings)

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let times = PrayerTimes(
            fajr: "05:00", shuruk: "07:00", dhuhr: "12:00", asr: "15:00",
            maghrib: "18:00", isha: "20:00",
            readableDate: "Test", readableDay: "Test", hijriDate: "Test", hijriDay: "Test",
            timezone: "Asia/Tokyo"
        )
        let cache = PrayerTimesCache(
            locationKey: LocationKey.key(address: autoSettings.address, location: autoSettings.location),
            methodKey: String(describing: autoSettings.method),
            fetchedAt: Date(),
            days: [PrayerDay(isoDate: "2026-09-29", hijri: nil, times: times)]
        )
        timesStore.replaceCache(with: cache)

        let scheduler = makeScheduler(personalCalendarSuite: personalSuite, timesStore: timesStore, settingsStore: settingsStore)
        let candidate = try #require(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, hour: 9, minute: 0)).first)

        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let comps = tokyoCalendar.dateComponents([.hour, .minute], from: candidate.fireDate)

        // 09:00 in Asia/Tokyo, not 09:00 in whatever timezone the test
        // machine happens to run in.
        #expect(comps.hour == 9 && comps.minute == 0)
    }

    // MARK: - Isolation from the prayer-times cache / persistence (spec item 8)

    @Test func zakatEntriesAreReadFromThePersonalCalendarStoreOnlyNeverThePrayerCache() async throws {
        // Constructing the scheduler with an *empty*, separate prayer-times
        // suite (no cached days at all) and a personal-calendar suite that
        // does have a Zakat entry — candidates must still be produced
        // purely from the personal store, confirming no dependency on the
        // prayer/AlAdhan caches for this feature (only the fire-time's
        // timezone falls back to `.current` when nothing is cached).
        let personalSuite = makeSuiteName()
        defer { cleanup([personalSuite]) }
        let store = PersonalCalendarStore(suiteName: personalSuite)
        store.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(personalCalendarSuite: personalSuite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true))
        #expect(!candidates.isEmpty)
    }
}
