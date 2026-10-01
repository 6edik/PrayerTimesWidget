import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `NotificationScheduler.qiratCandidates` after the Karāha
/// correction (short push texts, Shuruk-anchored sunrise window, Asr
/// never presented as impermissible) — same convention
/// `NotificationSchedulerZakatTests`/`NotificationSchedulerCandidateTests`
/// use: no live `UNUserNotificationCenter` needed here.
@MainActor
struct NotificationSchedulerQiratTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteNames: [String]) {
        for suite in suiteNames {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private func makeTimes(fajr: String, shuruk: String, asr: String, maghrib: String) -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: shuruk,
            dhuhr: "12:00",
            asr: asr,
            maghrib: maghrib,
            isha: "20:00",
            readableDate: "--",
            readableDay: "--",
            hijriDate: "--",
            hijriDay: "--",
            timezone: "Europe/Berlin"
        )
    }

    private func makeCache(for settings: AutoPrayerSettings, days: [PrayerDay]) -> PrayerTimesCache {
        PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: days
        )
    }

    private func berlinSettings(
        lateKerahetOffsetMinutes: Int? = nil,
        sunriseKarahaOffsetMinutes: Int? = nil
    ) -> AutoPrayerSettings {
        AutoPrayerSettings(
            address: "Berlin, DE",
            location: PrayerLocation(name: "Berlin, DE", coordinate: GeoCoordinate(latitude: 52.52, longitude: 13.405)),
            method: .ditib,
            adjustments: .zero,
            lateKerahetOffsetMinutesOverride: lateKerahetOffsetMinutes,
            sunriseKarahaOffsetMinutesOverride: sunriseKarahaOffsetMinutes
        )
    }

    private func qiratSettings(isEnabled: Bool) -> NotificationSettings {
        var settings = NotificationSettings.zero
        settings.qirat = QiratTimesNotificationSetting(isEnabled: isEnabled)
        return settings
    }

    @Test func disabledSwitchProducesNoCandidatesEvenWithCachedDays() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = berlinSettings()
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: false))
        #expect(candidates.isEmpty)
    }

    @Test func noCachedDataProducesNoCandidates() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))
        #expect(candidates.isEmpty)
    }

    @Test func enabledSwitchProducesSunriseAndLateMaghribCandidatesWithShortBodies() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = berlinSettings()
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))

        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.identifier.contains("sunriseKaraha") })
        #expect(candidates.contains { $0.identifier.contains("lateMaghribKaraha") })

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Sunrise fires exactly at Shuruk (07:15), never Fajr (05:45).
        let expectedSunriseStart = berlin.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7, minute: 15))!
        // Default 45-minute approximation before 18:00 Maghrib.
        let expectedApproxStart = berlin.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 17, minute: 15))!

        let sunrise = try #require(candidates.first { $0.identifier.contains("sunriseKaraha") })
        let lateMaghrib = try #require(candidates.first { $0.identifier.contains("lateMaghribKaraha") })

        #expect(sunrise.fireDate == expectedSunriseStart)
        #expect(lateMaghrib.fireDate == expectedApproxStart)

        // Short, concrete push texts — no fiqh explanation in the banner.
        #expect(sunrise.title == "Karāha")
        #expect(sunrise.body == "Sonnenaufgang: Gebetspause bis ca. 07:35.")
        #expect(lateMaghrib.title == "Karāha vor Maghrib")
        #expect(lateMaghrib.body == "Maghrib nähert sich. Asr nicht aufschieben.")
    }

    @Test func lateMaghribBodyNeverClaimsAsrIsImpermissible() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = berlinSettings()
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))

        let lateMaghrib = try #require(candidates.first { $0.identifier.contains("lateMaghribKaraha") })
        #expect(!lateMaghrib.body.localizedCaseInsensitiveContains("Asr ist nicht erlaubt"))
        #expect(!lateMaghrib.body.localizedCaseInsensitiveContains("Asr darf nicht"))
    }

    @Test func customSunriseOffsetMinutesFromSettingsShiftsTheEndTimeInTheBody() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = berlinSettings(sunriseKarahaOffsetMinutes: 15)
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))

        let sunrise = try #require(candidates.first { $0.identifier.contains("sunriseKaraha") })
        #expect(sunrise.body == "Sonnenaufgang: Gebetspause bis ca. 07:30.")
    }

    @Test func customLateMaghribOffsetMinutesFromSettingsIsUsed() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = berlinSettings(lateKerahetOffsetMinutes: 20)
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let expectedApproxStart = berlin.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 17, minute: 40))!

        #expect(candidates.first { $0.identifier.contains("lateMaghribKaraha") }?.fireDate == expectedApproxStart)
    }

    @Test func highLatitudeSuppressesBothApproximations() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = AutoPrayerSettings(
            address: "Tromsø, NO",
            location: PrayerLocation(name: "Tromsø, NO", coordinate: GeoCoordinate(latitude: 69.6, longitude: 18.96)),
            method: .ditib,
            adjustments: .zero
        )
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "07:15", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))

        // Both are fixed-minute approximations and both are suppressed at
        // this latitude — the exact afterFajrVoluntaryRestriction window
        // is never surfaced as a notification either way, so no
        // candidates at all for this day.
        #expect(candidates.isEmpty)
    }

    @Test func malformedShurukContributesNoSunriseCandidateForThatDayOnly() async throws {
        let timesSuite = makeSuiteName()
        let settingsSuite = makeSuiteName()
        defer { cleanup([timesSuite, settingsSuite]) }

        let timesStore = SharedPrayerTimesStore(suiteName: timesSuite)
        let settingsStore = SharedPrayerSettingsStore(suiteName: settingsSuite)
        let autoSettings = berlinSettings()
        settingsStore.saveAutoSettings(autoSettings)

        timesStore.replaceCache(with: makeCache(for: autoSettings, days: [
            PrayerDay(isoDate: "2026-01-02", hijri: nil, times: makeTimes(fajr: "05:45", shuruk: "not-a-time", asr: "15:00", maghrib: "18:00"))
        ]))

        let scheduler = NotificationScheduler(timesStore: timesStore, settingsStore: settingsStore)
        let candidates = scheduler.qiratCandidates(settings: qiratSettings(isEnabled: true))

        // "sunriseKaraha" can't be resolved from a malformed Shuruk
        // string, but the late-Maghrib approximation (Maghrib is still
        // valid) must still be produced.
        #expect(candidates.count == 1)
        #expect(candidates.first?.identifier.contains("lateMaghribKaraha") == true)
    }

    // MARK: - Old-style requests are replaced, other categories untouched

    @Test func stableQiratPrefixCatchesBothOldAndNewSuffixesButNeverOtherCategories() async throws {
        // `reschedule()` always calls `removeAllOwnPendingRequests()`
        // before rebuilding, which removes anything matching
        // `isOwnIdentifier` (prefix-based, not suffix-exact) — this must
        // catch a stale identifier from an earlier version of this
        // feature (when the sunrise window was wrongly anchored to Fajr,
        // suffix "afterFajr", or the pre-Maghrib window to Asr, suffix
        // "beforeMaghrib"/"lateKerahetApproximation") exactly like the
        // current "sunriseKaraha"/"lateMaghribKaraha" suffixes, since all
        // of them share the same `qiratIdentifierPrefix`, while never
        // matching a prayer/holiday/fasting/zakat identifier. No code
        // change was needed to guarantee this — the prefix itself was
        // deliberately left unrenamed.
        let prefix = NotificationScheduler.qiratIdentifierPrefix
        let staleAfterFajr = "\(prefix)afterFajr.2026-01-02"
        let staleBeforeMaghrib = "\(prefix)beforeMaghrib.2026-01-02"
        let staleLateApprox = "\(prefix)lateKerahetApproximation.2026-01-02"
        let currentSunrise = "\(prefix)sunriseKaraha.2026-01-02"
        let currentLateMaghrib = "\(prefix)lateMaghribKaraha.2026-01-02"
        let unrelatedPrayer = "\(NotificationScheduler.prayerIdentifierPrefix)fajr.2026-01-02.start"

        for identifier in [staleAfterFajr, staleBeforeMaghrib, staleLateApprox, currentSunrise, currentLateMaghrib] {
            #expect(identifier.hasPrefix(prefix))
        }
        #expect(!unrelatedPrayer.hasPrefix(prefix))
    }
}
