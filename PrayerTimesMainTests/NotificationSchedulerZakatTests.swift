import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `NotificationScheduler.zakatCandidates` — the pure, testable
/// candidate builder (same convention `NotificationSchedulerCandidateTests`
/// uses for prayer/holiday candidates: no live `UNUserNotificationCenter`
/// needed here). The Zakat due date is a single fixed Hijri (day, month)
/// rule, stored in its own `ZakatDueDateStore` under "Besondere Tage" —
/// entirely separate from "Meine Notizen" (`PersonalCalendarStore`) — and
/// always recurs every Hijri year; there is no one-time variant and no
/// Gregorian-anchor-based repeat.
///
/// What `reschedule()` does with these candidates (removing every
/// previously-owned request before rebuilding, checking system
/// authorization, respecting the 64-notification budget) is shared,
/// unchanged machinery already exercised for prayer/holiday/fasting
/// candidates — extending `isOwnIdentifier`/`removeAllOwnPendingRequests`
/// with the Zakat prefix reuses that same guarantee rather than
/// duplicating it.
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
        zakatSuite: String,
        timesStore: SharedPrayerTimesStore? = nil,
        settingsStore: SharedPrayerSettingsStore? = nil
    ) -> NotificationScheduler {
        NotificationScheduler(
            timesStore: timesStore ?? SharedPrayerTimesStore(suiteName: makeSuiteName()),
            settingsStore: settingsStore ?? SharedPrayerSettingsStore(suiteName: makeSuiteName()),
            notificationSettingsStore: NotificationSettingsStore(suiteName: makeSuiteName()),
            calendarStore: SharedIslamicCalendarStore(suiteName: makeSuiteName()),
            zakatDueDateStore: ZakatDueDateStore(suiteName: zakatSuite)
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

    @Test func disabledZakatSwitchProducesNoCandidatesEvenWithADueDate() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: false))
        #expect(candidates.isEmpty)
    }

    // MARK: - No due date configured

    @Test func noConfiguredDueDateProducesNoCandidates() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }

        let scheduler = makeScheduler(zakatSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true))
        #expect(candidates.isEmpty)
    }

    // MARK: - Independence from "Meine Notizen"

    @Test func personalNotesNeverProduceZakatCandidatesEvenWithLegacyZakatShapedEntries() async throws {
        let zakatSuite = makeSuiteName()
        let personalSuite = makeSuiteName()
        defer { cleanup([zakatSuite, personalSuite]) }

        // Simulates a not-yet-migrated legacy entry sitting in the old
        // "Meine Notizen" store — `zakatCandidates` must never read that
        // store at all, only the dedicated `ZakatDueDateStore`.
        PersonalCalendarStore(suiteName: personalSuite).upsert(
            PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 9)
        )

        let scheduler = makeScheduler(zakatSuite: zakatSuite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true))
        #expect(candidates.isEmpty)
    }

    // MARK: - The rule recurs — several years produce several on-day candidates

    @Test func dueDateProducesOneOnDayCandidatePerUpcomingHijriYear() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, hour: 8, minute: 30))

        // Default `ZakatOccurrenceCalculator` limit is 3 upcoming years.
        #expect(candidates.count == 3)
        #expect(candidates.allSatisfy { $0.identifier.hasSuffix(".onday") })
        #expect(candidates.allSatisfy { $0.identifier.hasPrefix(NotificationScheduler.zakatIdentifierPrefix) })

        // Distinct occurrence keys — never the same Gregorian date twice.
        #expect(Set(candidates.map(\.identifier)).count == 3)

        // Always the same fixed, neutral sentence — never a claim that
        // Zakat is actually due.
        #expect(candidates.allSatisfy { $0.body == "Dein Zakat-Stichtag ist heute." })
    }

    @Test func dayBeforeToggleAddsASecondCandidatePerOccurrence() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
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
        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 15, hijriMonth: 6))

        let scheduler = makeScheduler(zakatSuite: suite)
        let settings = zakatSettings(isEnabled: true, notifyDayBefore: true)

        let first = scheduler.zakatCandidates(settings: settings)
        let second = scheduler.zakatCandidates(settings: settings)

        #expect(first == second)
        #expect(Set(first.map(\.identifier)).count == first.count)
    }

    // MARK: - Editing/deleting reflects immediately in the next build

    @Test func clearingTheDueDateRemovesItFromTheNextCandidateBuild() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = ZakatDueDateStore(suiteName: suite)
        store.save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
        #expect(!scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).isEmpty)

        store.clear()
        #expect(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).isEmpty)
    }

    @Test func changingTheHijriRuleChangesTheCandidatesIdentifiers() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = ZakatDueDateStore(suiteName: suite)
        store.save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
        let before = Set(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).map(\.identifier))

        store.save(ZakatDueDate(hijriDay: 20, hijriMonth: 12))

        let after = Set(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true)).map(\.identifier))
        #expect(before.isDisjoint(with: after))
    }

    @Test func changingTheReminderTimeChangesTheFireDateNotTheDay() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
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

    // MARK: - Location timezone used for the reminder's clock time

    @Test func usesTheConfiguredLocationsTimeZoneNotTheDevicesForTheFireTime() async throws {
        let zakatSuite = makeSuiteName()
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([zakatSuite, timesSuite, settingsSuite]) }

        ZakatDueDateStore(suiteName: zakatSuite).save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

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

        let scheduler = makeScheduler(zakatSuite: zakatSuite, timesStore: timesStore, settingsStore: settingsStore)
        let candidate = try #require(scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true, hour: 9, minute: 0)).first)

        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let comps = tokyoCalendar.dateComponents([.hour, .minute], from: candidate.fireDate)

        // 09:00 in Asia/Tokyo, not 09:00 in whatever timezone the test
        // machine happens to run in.
        #expect(comps.hour == 9 && comps.minute == 0)
    }

    // MARK: - Isolation from the prayer-times cache / persistence

    @Test func zakatIsReadFromItsOwnStoreOnlyNeverThePrayerCache() async throws {
        // Constructing the scheduler with an *empty*, separate prayer-times
        // suite (no cached days at all) and a Zakat suite that does have a
        // configured due date — candidates must still be produced purely
        // from `ZakatDueDateStore`, confirming no dependency on the
        // prayer/AlAdhan caches for this feature (only the fire-time's
        // timezone falls back to `.current` when nothing is cached).
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 1, hijriMonth: 9))

        let scheduler = makeScheduler(zakatSuite: suite)
        let candidates = scheduler.zakatCandidates(settings: zakatSettings(isEnabled: true))
        #expect(!candidates.isEmpty)
    }
}
