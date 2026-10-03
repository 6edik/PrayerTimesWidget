import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `ZakatDueDateStore`: its own dedicated persistence for the
/// Zakat-due-date rule configured under "Besondere Tage", independence
/// from "Meine Notizen" / the prayer-times cache / the AlAdhan holiday
/// cache, and the one-time migration away from the previous design (a
/// Zakat entry mixed into `PersonalCalendarEntry`).
@MainActor
struct ZakatDueDateStoreTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteNames: [String]) {
        for suite in suiteNames {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    // MARK: - Basic persistence

    @Test func savedValuePersistsAcrossASimulatedAppRestart() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }

        ZakatDueDateStore(suiteName: suite).save(ZakatDueDate(hijriDay: 27, hijriMonth: 9))

        // A brand-new store instance reading the same on-disk suite —
        // simulates an app relaunch.
        let reread = ZakatDueDateStore(suiteName: suite).load()
        #expect(reread == ZakatDueDate(hijriDay: 27, hijriMonth: 9))
    }

    @Test func noValueSavedYetLoadsNil() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        #expect(ZakatDueDateStore(suiteName: suite).load() == nil)
    }

    @Test func clearRemovesTheSavedValue() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = ZakatDueDateStore(suiteName: suite)
        store.save(ZakatDueDate(hijriDay: 5, hijriMonth: 3))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func savingAgainReplacesThePreviousValue() async throws {
        let suite = makeSuiteName()
        defer { cleanup([suite]) }
        let store = ZakatDueDateStore(suiteName: suite)
        store.save(ZakatDueDate(hijriDay: 1, hijriMonth: 1))
        store.save(ZakatDueDate(hijriDay: 27, hijriMonth: 9))
        #expect(store.load() == ZakatDueDate(hijriDay: 27, hijriMonth: 9))
    }

    // MARK: - Independence from the prayer-times cache and the holiday cache

    @Test func clearingThePrayerAndHolidayCachesNeverTouchesTheZakatDueDate() async throws {
        // Same suite for all three stores, mirroring a single real App
        // Group — the exact stores/keys `CacheResetService.clearAllCaches()`
        // clears, plus the Zakat store, which it deliberately never
        // references.
        let suite = makeSuiteName()
        defer { cleanup([suite]) }

        let zakatStore = ZakatDueDateStore(suiteName: suite)
        zakatStore.save(ZakatDueDate(hijriDay: 27, hijriMonth: 9))

        SharedPrayerTimesStore(suiteName: suite).clear()
        SharedIslamicCalendarStore(suiteName: suite).clear()

        #expect(ZakatDueDateStore(suiteName: suite).load() == ZakatDueDate(hijriDay: 27, hijriMonth: 9))
    }

    // MARK: - Migration from the previous "Meine Notizen"-based design

    @Test func migrationCarriesForwardTheFirstLegacyEntryAndRemovesItFromPersonalNotes() async throws {
        let personalSuite = makeSuiteName()
        let zakatSuite = makeSuiteName()
        defer { cleanup([personalSuite, zakatSuite]) }

        let personalStore = PersonalCalendarStore(suiteName: personalSuite)
        personalStore.upsert(PersonalCalendarEntry(note: "Notiz", isoDate: "2026-09-29"))
        personalStore.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 27, hijriMonth: 9))

        let zakatStore = ZakatDueDateStore(suiteName: zakatSuite)
        ZakatDueDateStore.migrateFromPersonalCalendarIfNeeded(personalStore: personalStore, zakatStore: zakatStore)

        #expect(zakatStore.load() == ZakatDueDate(hijriDay: 27, hijriMonth: 9))

        // The legacy Zakat entry is gone from "Meine Notizen"; the plain
        // note is untouched.
        let remaining = personalStore.loadAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.kind == .note)
        #expect(remaining.first?.note == "Notiz")
    }

    @Test func migrationRemovesAllLegacyEntriesEvenIfThereWereDuplicates() async throws {
        let personalSuite = makeSuiteName()
        let zakatSuite = makeSuiteName()
        defer { cleanup([personalSuite, zakatSuite]) }

        let personalStore = PersonalCalendarStore(suiteName: personalSuite)
        personalStore.upsert(PersonalCalendarEntry(note: "Zakat 1", kind: .zakatDueDate, hijriDay: 27, hijriMonth: 9))
        personalStore.upsert(PersonalCalendarEntry(note: "Zakat 2", kind: .zakatDueDate, hijriDay: 1, hijriMonth: 1))

        ZakatDueDateStore.migrateFromPersonalCalendarIfNeeded(
            personalStore: personalStore,
            zakatStore: ZakatDueDateStore(suiteName: zakatSuite)
        )

        #expect(personalStore.loadAll().isEmpty)
    }

    @Test func migrationIsANoOpWhenAValueIsAlreadySaved() async throws {
        let personalSuite = makeSuiteName()
        let zakatSuite = makeSuiteName()
        defer { cleanup([personalSuite, zakatSuite]) }

        let zakatStore = ZakatDueDateStore(suiteName: zakatSuite)
        zakatStore.save(ZakatDueDate(hijriDay: 5, hijriMonth: 5))

        let personalStore = PersonalCalendarStore(suiteName: personalSuite)
        personalStore.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 27, hijriMonth: 9))

        ZakatDueDateStore.migrateFromPersonalCalendarIfNeeded(personalStore: personalStore, zakatStore: zakatStore)

        // Already-configured value wins; the legacy entry is left alone
        // since migration only ever runs once.
        #expect(zakatStore.load() == ZakatDueDate(hijriDay: 5, hijriMonth: 5))
        #expect(personalStore.loadAll().count == 1)
    }

    @Test func migrationIsANoOpWhenThereIsNoLegacyEntry() async throws {
        let personalSuite = makeSuiteName()
        let zakatSuite = makeSuiteName()
        defer { cleanup([personalSuite, zakatSuite]) }

        let personalStore = PersonalCalendarStore(suiteName: personalSuite)
        personalStore.upsert(PersonalCalendarEntry(note: "Nur eine Notiz", isoDate: "2026-09-29"))

        let zakatStore = ZakatDueDateStore(suiteName: zakatSuite)
        ZakatDueDateStore.migrateFromPersonalCalendarIfNeeded(personalStore: personalStore, zakatStore: zakatStore)

        #expect(zakatStore.load() == nil)
        #expect(personalStore.loadAll().count == 1)
    }

    // MARK: - After migration, "Meine Notizen" never surfaces a Zakat entry

    @Test func afterMigrationThePersonalCalendarViewModelNeverSurfacesTheZakatEntry() async throws {
        let personalSuite = makeSuiteName()
        let zakatSuite = makeSuiteName()
        defer { cleanup([personalSuite, zakatSuite]) }

        let personalStore = PersonalCalendarStore(suiteName: personalSuite)
        personalStore.upsert(PersonalCalendarEntry(note: "Zakat", kind: .zakatDueDate, hijriDay: 27, hijriMonth: 9))

        ZakatDueDateStore.migrateFromPersonalCalendarIfNeeded(
            personalStore: personalStore,
            zakatStore: ZakatDueDateStore(suiteName: zakatSuite)
        )

        let viewModel = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: personalSuite))
        #expect(viewModel.allEntriesSortedByDate.isEmpty)
    }
}
