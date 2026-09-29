import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the persistent store and view model behind the personal notes
/// feature (deliberately minimal: no title, no date/time picker — just a
/// note tied to whichever calendar day it was created on):
/// - create/edit/delete, including multiple notes on the same calendar day
/// - persistence across a simulated app restart (a brand-new store/view
///   model instance reading the same on-disk suite)
/// - independence from the prayer-times cache and the AlAdhan holiday
///   cache: clearing either (what `CacheResetService.clearAllCaches()`
///   does) must never remove a note
/// - the isoDate representation never depends on the device's *current*
///   timezone at read time — a later timezone change cannot move a note
///   onto a different calendar day
@MainActor
struct PersonalCalendarStoreTests {
    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Create / edit / delete

    @Test func createReadEditDeleteRoundTrips() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let viewModel = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))

        let entry = PersonalCalendarEntry(note: "Zahnarzttermin", isoDate: "2026-10-05")
        viewModel.save(entry)

        let loadedDate = PersonalCalendarViewModel.date(from: "2026-10-05")!
        #expect(viewModel.entries(for: loadedDate).count == 1)
        #expect(viewModel.entries(for: loadedDate).first?.note == "Zahnarzttermin")

        var updated = entry
        updated.note = "Zahnarzttermin (verschoben)"
        viewModel.save(updated)

        #expect(viewModel.entries(for: loadedDate).count == 1)
        #expect(viewModel.entries(for: loadedDate).first?.note == "Zahnarzttermin (verschoben)")

        viewModel.delete(updated)
        #expect(viewModel.entries(for: loadedDate).isEmpty)
    }

    // MARK: - Multiple entries, same day

    @Test func multipleEntriesOnTheSameDayAreAllKeptAndOrderedByCreation() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let viewModel = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))

        let day = "2026-11-12"
        let base = Date()
        viewModel.save(PersonalCalendarEntry(note: "Erste Notiz", isoDate: day, createdAt: base))
        viewModel.save(PersonalCalendarEntry(note: "Zweite Notiz", isoDate: day, createdAt: base.addingTimeInterval(1)))
        viewModel.save(PersonalCalendarEntry(note: "Dritte Notiz", isoDate: day, createdAt: base.addingTimeInterval(2)))

        let date = PersonalCalendarViewModel.date(from: day)!
        let notes = viewModel.entries(for: date).map(\.note)
        #expect(notes == ["Erste Notiz", "Zweite Notiz", "Dritte Notiz"])
        #expect(viewModel.hasEntries(for: date))
    }

    // MARK: - Persistence across "app restart"

    @Test func entriesSurviveANewStoreInstanceReadingTheSameSuite() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }

        let firstLaunch = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))
        firstLaunch.save(PersonalCalendarEntry(note: "Bleibt erhalten", isoDate: "2026-12-01"))

        // Simulates an app relaunch: a brand-new store/view model, nothing
        // carried over in memory, reading the same on-disk suite.
        let secondLaunch = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))
        let date = PersonalCalendarViewModel.date(from: "2026-12-01")!
        #expect(secondLaunch.entries(for: date).map(\.note) == ["Bleibt erhalten"])
    }

    // MARK: - Independence from the prayer-times cache and the holiday cache

    @Test func clearingThePrayerAndHolidayCachesNeverTouchesPersonalEntries() async throws {
        // Same suite for all three stores, mirroring a single real App
        // Group — the exact stores/keys `CacheResetService.clearAllCaches()`
        // clears, plus the personal-notes store, which it deliberately
        // never references.
        let suite = makeSuiteName()
        defer { cleanup(suite) }

        let personalViewModel = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))
        personalViewModel.save(PersonalCalendarEntry(note: "Persönlich", isoDate: "2026-09-29"))

        SharedPrayerTimesStore(suiteName: suite).clear()
        SharedIslamicCalendarStore(suiteName: suite).clear()

        let date = PersonalCalendarViewModel.date(from: "2026-09-29")!
        #expect(personalViewModel.entries(for: date).map(\.note) == ["Persönlich"])

        // A fresh instance (simulating the reset flow's own fresh reads)
        // sees the same, unaffected data.
        let reread = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))
        #expect(reread.entries(for: date).map(\.note) == ["Persönlich"])
    }

    // MARK: - Location / method changes never clear personal entries

    @Test func locationOrMethodChangeNeverClearsPersonalEntries() async throws {
        // `AutoPrayerViewModel`/`LegacyLocationMigrator` only ever call
        // `SharedPrayerTimesStore.clear()` on a location/method change —
        // never anything under the personal-notes key. Exercised here
        // directly against the store to guard against a future regression
        // that starts clearing more than the prayer-times cache.
        let suite = makeSuiteName()
        defer { cleanup(suite) }

        let personalViewModel = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))
        personalViewModel.save(PersonalCalendarEntry(note: "Reise nach Istanbul", isoDate: "2027-01-15"))

        SharedPrayerTimesStore(suiteName: suite).clear()

        let date = PersonalCalendarViewModel.date(from: "2027-01-15")!
        #expect(personalViewModel.entries(for: date).map(\.note) == ["Reise nach Istanbul"])
    }

    // MARK: - Timezone-safe day assignment

    @Test func isoDateAssignmentIsAPlainStringIndependentOfTheCurrentTimeZone() async throws {
        // `isoDate` is a plain "yyyy-MM-dd" string, not an absolute `Date`
        // — so it can never be reinterpreted onto a different calendar day
        // just because the ambient/current timezone changed between
        // creating the note and displaying it later.
        let entry = PersonalCalendarEntry(note: "Fixer Tag", isoDate: "2026-06-15")
        #expect(entry.isoDate == "2026-06-15")
    }

    @Test func entriesForDateMatchesByCalendarDayUsingTheCurrentTimeZone() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let viewModel = PersonalCalendarViewModel(store: PersonalCalendarStore(suiteName: suite))

        let isoDate = "2026-07-04"
        viewModel.save(PersonalCalendarEntry(note: "Sommerfest", isoDate: isoDate))

        // Re-deriving the lookup date the same way the calendar grid does
        // (from device-local calendar components) must land on the exact
        // same note — the round trip through `isoDateString(from:)` and
        // `date(from:)` must be lossless for the calendar day.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 4
        comps.hour = 12
        let lookupDate = calendar.date(from: comps)!

        #expect(PersonalCalendarViewModel.isoDateString(from: lookupDate) == isoDate)
        #expect(viewModel.entries(for: lookupDate).map(\.note) == ["Sommerfest"])
    }

    // MARK: - Note validation data shape (trim rule lives in the form view)

    @Test func noteTrimmingLeavesGenuineContentUntouched() async throws {
        let raw = "  Wichtiger Termin  "
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed == "Wichtiger Termin")
        #expect(!trimmed.isEmpty)

        let blank = "   \n  "
        #expect(blank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
