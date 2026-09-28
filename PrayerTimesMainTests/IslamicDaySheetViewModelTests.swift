import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers the Islamic calendar day sheet's cache-first, single-day prayer
/// times lookup (`IslamicDaySheetViewModel`):
/// - a cache hit is served with zero network requests
/// - a cache miss triggers exactly one targeted single-day fetch
/// - a same-day entry cached under a different place/method is treated as a
///   miss, never served as-is
/// - offline behavior, with and without a matching cache entry
/// - rapid re-triggering (modeling a fast day switch) only lets the latest
///   attempt update state — a cancelled, slower attempt's late result never
///   lands
/// - cancelling while a request is in flight (modeling the sheet closing)
///   leaves state untouched
/// - the single-day fetch never writes to the persistent Auto-Cache
/// - display values carry the personal minute adjustments while the raw
///   values stay untouched, and the exact tapped `Date` is passed through
///   unchanged to the request (no incidental timezone conversion)
@MainActor
struct IslamicDaySheetViewModelTests {
    /// Test double for `SingleDayPrayerTimesFetching`: records how many
    /// times (and with what date) it was called, and can simulate either a
    /// slow request (via `Task.sleep`, which is itself cancellation-aware)
    /// or an instant one. Marked `@unchecked Sendable` rather than an actor
    /// — every test here drives the mock from a single `@MainActor` test
    /// function with no concurrent access, so the unsynchronized mutable
    /// state is safe in practice, and a plain class sidesteps the stricter
    /// actor-isolated-conformance checking for a test-only type.
    private final class MockFetcher: SingleDayPrayerTimesFetching, @unchecked Sendable {
        // `nonisolated(unsafe)`: this class isn't itself an actor, but
        // nested inside a @MainActor test struct its members would
        // otherwise infer @MainActor isolation, forcing every access to
        // go through the (nonisolated, protocol-required) fetch method
        // below via `await`. Every test drives this from a single
        // @MainActor test function with no concurrent access, so the
        // unsynchronized mutation is safe in practice (see class doc
        // comment above).
        nonisolated(unsafe) private(set) var callCount = 0
        nonisolated(unsafe) private(set) var capturedDates: [Date] = []
        nonisolated(unsafe) private var result: Result<PrayerTimes, Error>
        nonisolated(unsafe) private var delayNanoseconds: UInt64

        nonisolated init(result: Result<PrayerTimes, Error>, delayNanoseconds: UInt64 = 0) {
            self.result = result
            self.delayNanoseconds = delayNanoseconds
        }

        nonisolated func configure(result: Result<PrayerTimes, Error>, delayNanoseconds: UInt64 = 0) {
            self.result = result
            self.delayNanoseconds = delayNanoseconds
        }

        nonisolated func fetchPrayerTimesForSingleDayUncached(settings: PrayerSettings) async throws -> PrayerTimes {
            callCount += 1
            capturedDates.append(settings.date)

            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }

            switch result {
            case .success(let times): return times
            case .failure(let error): throw error
            }
        }
    }

    private func makeSuiteName() -> String {
        "com.mertgedik.prayertimes.tests.\(UUID().uuidString)"
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeTimes(fajr: String = "05:00") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: "07:00",
            dhuhr: "12:00",
            asr: "15:00",
            maghrib: "18:00",
            isha: "20:00",
            readableDate: "1 Jan 2026",
            readableDay: "Thursday",
            hijriDate: "01-01-1447",
            hijriDay: "Thursday",
            timezone: "Europe/Berlin"
        )
    }

    private func isoString(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func dateFromISO(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func makeCache(for settings: AutoPrayerSettings, days: [PrayerDay]) -> PrayerTimesCache {
        PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: days
        )
    }

    // MARK: - 1. Cache hit: zero network requests

    @Test func cachedDayIsServedWithoutAnyNetworkRequest() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes(fajr: "05:12"))]
        ))

        let mock = MockFetcher(result: .success(makeTimes(fajr: "99:99")))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()

        guard case .loaded(let raw, _, let source) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(source == .cached)
        #expect(raw.fajr == "05:12")
        #expect(mock.callCount == 0)
    }

    // MARK: - 2. Cache miss: exactly one targeted single-day fetch

    @Test func cacheMissTriggersExactlyOneSingleDayFetch() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        let mock = MockFetcher(result: .success(makeTimes(fajr: "06:30")))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        guard case .loaded(let raw, _, let source) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(source == .fetched)
        #expect(raw.fajr == "06:30")
        #expect(mock.callCount == 1)
    }

    // MARK: - 3. Same day, mismatched cache location/method falls back to fetch

    @Test func mismatchedCacheLocationFallsBackToSingleFetch() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let cachedSettings = AutoPrayerSettings(address: "Essen, DE", method: .ditib, adjustments: .zero)
        let currentSettings = AutoPrayerSettings(address: "Munich, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        store.replaceCache(with: makeCache(
            for: cachedSettings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes(fajr: "05:12"))]
        ))

        let mock = MockFetcher(result: .success(makeTimes(fajr: "07:45")))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { currentSettings },
            service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        guard case .loaded(let raw, _, let source) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(source == .fetched)
        #expect(raw.fajr == "07:45")
        #expect(mock.callCount == 1)
    }

    @Test func mismatchedCacheMethodFallsBackToSingleFetch() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let sameAddress = "Berlin, DE"
        let cachedSettings = AutoPrayerSettings(address: sameAddress, method: .ditib, adjustments: .zero)
        let currentSettings = AutoPrayerSettings(address: sameAddress, method: .muslimWorldLeague, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        store.replaceCache(with: makeCache(
            for: cachedSettings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes())]
        ))

        let mock = MockFetcher(result: .success(makeTimes(fajr: "04:59")))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { currentSettings },
            service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        guard case .loaded(let raw, _, let source) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(source == .fetched)
        #expect(raw.fajr == "04:59")
        #expect(mock.callCount == 1)
    }

    // MARK: - 4. Offline, with and without a matching cache

    @Test func offlineWithMatchingCacheStillNeverTouchesTheNetwork() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes())]
        ))

        // Configured to simulate "no internet" if it were ever called.
        let mock = MockFetcher(result: .failure(URLError(.notConnectedToInternet)))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()

        guard case .loaded(_, _, let source) = viewModel.state else {
            Issue.record("Expected .loaded from cache even though the network is unreachable, got \(viewModel.state)")
            return
        }
        #expect(source == .cached)
        #expect(mock.callCount == 0)
    }

    @Test func offlineWithoutMatchingCacheProducesOfflineState() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        let mock = MockFetcher(result: .failure(URLError(.notConnectedToInternet)))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        #expect(viewModel.state == .offline)
    }

    @Test func nonConnectivityErrorProducesGenericFailedStateNotOffline() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        let mock = MockFetcher(result: .failure(PrayerTimesServiceError.locationMismatch))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        guard case .failed = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
    }

    // MARK: - 5. Rapid re-trigger (fast day switch): only the latest wins

    /// Models rapidly tapping day A then day B: in production this creates
    /// two independent `IslamicDaySheetViewModel` instances (so there is no
    /// possible cross-contamination by construction), but the guard that
    /// makes that safe — cancelling a still-in-flight request before
    /// starting a new one, and discarding a cancelled request's result — is
    /// exercised here directly by calling `load()` twice on one instance
    /// while the first attempt is still sleeping.
    @Test func loadCalledAgainWhileInFlightCancelsThePreviousRequestSoOnlyTheLatestResultWins() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        let staleTimes = makeTimes(fajr: "01:11")
        let latestTimes = makeTimes(fajr: "02:22")

        // Long delay so the first attempt is still "in flight" when we
        // trigger the second one.
        let mock = MockFetcher(result: .success(staleTimes), delayNanoseconds: 300_000_000)
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()
        #expect(viewModel.state == .loading)

        // Give the first attempt a moment to actually start (increment
        // callCount) before superseding it.
        try await Task.sleep(nanoseconds: 20_000_000)

        mock.configure(result: .success(latestTimes), delayNanoseconds: 0)
        viewModel.load()

        try await waitUntilSettled(viewModel)

        // Wait past the first attempt's original delay window to prove its
        // late result never arrives even though enough time has passed.
        try await Task.sleep(nanoseconds: 350_000_000)

        guard case .loaded(let raw, _, let source) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(source == .fetched)
        #expect(raw.fajr == "02:22")
    }

    // MARK: - 6. Closing the sheet during a request

    @Test func cancelDuringInFlightRequestLeavesStateUnchangedAndDiscardsLateResult() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        let mock = MockFetcher(result: .success(makeTimes(fajr: "03:33")), delayNanoseconds: 200_000_000)
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()
        #expect(viewModel.state == .loading)

        // Simulate the sheet being dismissed while the request is in flight.
        viewModel.cancel()

        // Wait past the mock's delay window — if cancellation didn't work,
        // the state would have flipped to .loaded by now.
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(viewModel.state == .loading)
    }

    // MARK: - 7. Never writes to the persistent Auto-Cache

    @Test func singleDayFetchNeverWritesToThePersistentAutoCache() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        #expect(store.cacheDayCount(settings: settings) == 0)

        let mock = MockFetcher(result: .success(makeTimes(fajr: "06:30")))
        let viewModel = IslamicDaySheetViewModel(
            date: date,
            prayerStore: store,
            settingsProvider: { settings },
            service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        guard case .loaded(_, _, let source) = viewModel.state, source == .fetched else {
            Issue.record("Expected a .fetched result, got \(viewModel.state)")
            return
        }

        // The successfully fetched day must still be completely absent
        // from the shared, persistent store — Home, widget and
        // notification scheduling must never see it.
        #expect(store.cacheDayCount(settings: settings) == 0)
        #expect(store.loadPrayerDay(for: date, settings: settings) == nil)
    }

    // MARK: - 8. Adjustment applied on display only; requested date passed through unchanged

    @Test func adjustmentsAppliedOnDisplayOnlyRawStaysUnchangedForCachedDay() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let adjustments = PrayerAdjustments(fajr: 10, shuruk: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: 0)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)
        let date = dateFromISO(isoString(2026, 1, 1))

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: isoString(2026, 1, 1), hijri: nil, times: makeTimes(fajr: "05:00"))]
        ))

        let mock = MockFetcher(result: .success(makeTimes()))
        let viewModel = IslamicDaySheetViewModel(
            date: date, prayerStore: store, settingsProvider: { settings }, service: mock
        )

        viewModel.load()

        guard case .loaded(let raw, let adjusted, _) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(raw.fajr == "05:00")
        #expect(adjusted.fajr == "05:10")
    }

    @Test func adjustmentsAppliedOnDisplayOnlyRawStaysUnchangedForFetchedDay() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let adjustments = PrayerAdjustments(fajr: 0, shuruk: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: -15)
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)
        let date = dateFromISO(isoString(2026, 1, 1))

        let mock = MockFetcher(result: .success(makeTimes()))
        let viewModel = IslamicDaySheetViewModel(
            date: date, prayerStore: store, settingsProvider: { settings }, service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        guard case .loaded(let raw, let adjusted, _) = viewModel.state else {
            Issue.record("Expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(raw.isha == "20:00")
        #expect(adjusted.isha == "19:45")
    }

    @Test func requestedDateIsPassedThroughUnchangedAvoidingTimezoneShift() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        // A date very close to local midnight, where a naive UTC/device
        // timezone mix-up would be most likely to shift the requested
        // calendar day by one.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 0
        components.minute = 15
        let calendar = Calendar(identifier: .gregorian)
        let nearMidnightDate = calendar.date(from: components)!

        let mock = MockFetcher(result: .success(makeTimes()))
        let viewModel = IslamicDaySheetViewModel(
            date: nearMidnightDate, prayerStore: store, settingsProvider: { settings }, service: mock
        )

        viewModel.load()
        try await waitUntilSettled(viewModel)

        let captured = mock.capturedDates
        #expect(captured.count == 1)
        #expect(captured.first == nearMidnightDate)
    }

    // MARK: - 9. Fasting duration (adjusted Fajr to adjusted Maghrib)

    @Test func fastingDurationReflectsAdjustedFajrAndMaghribForCachedDay() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        var adjustments = PrayerAdjustments.zero
        adjustments.fajr = -10
        adjustments.maghrib = 10
        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: adjustments)
        let iso = isoString(2026, 1, 1)
        let date = dateFromISO(iso)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "05:00"))]
        ))

        let mock = MockFetcher(result: .success(makeTimes()))
        let viewModel = IslamicDaySheetViewModel(
            date: date, prayerStore: store, settingsProvider: { settings }, service: mock
        )

        viewModel.load()

        let duration = try #require(viewModel.fastingDuration)
        let expectedFajr = PrayerMomentResolver.resolve(
            isoDate: iso, rawTime: "05:00", adjustmentMinutes: -10, timezoneIdentifier: "Europe/Berlin"
        )!
        let expectedMaghrib = PrayerMomentResolver.resolve(
            isoDate: iso, rawTime: "18:00", adjustmentMinutes: 10, timezoneIdentifier: "Europe/Berlin"
        )!

        #expect(duration.fajrDate == expectedFajr)
        #expect(duration.maghribDate == expectedMaghrib)
    }

    @Test func fastingDurationIsNilForMalformedTimesRatherThanAGuess() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let iso = isoString(2026, 1, 1)
        let date = dateFromISO(iso)

        store.replaceCache(with: makeCache(
            for: settings,
            days: [PrayerDay(isoDate: iso, hijri: nil, times: makeTimes(fajr: "not-a-time"))]
        ))

        let mock = MockFetcher(result: .success(makeTimes()))
        let viewModel = IslamicDaySheetViewModel(
            date: date, prayerStore: store, settingsProvider: { settings }, service: mock
        )

        viewModel.load()

        #expect(viewModel.fastingDuration == nil)
    }

    @Test func fastingDurationIsClearedWhileANewLoadIsInFlight() async throws {
        let suite = makeSuiteName()
        defer { cleanup(suite) }
        let store = SharedPrayerTimesStore(suiteName: suite)

        let settings = AutoPrayerSettings(address: "Berlin, DE", method: .ditib, adjustments: .zero)
        let date = dateFromISO(isoString(2026, 1, 1))

        let mock = MockFetcher(result: .success(makeTimes()), delayNanoseconds: 200_000_000)
        let viewModel = IslamicDaySheetViewModel(
            date: date, prayerStore: store, settingsProvider: { settings }, service: mock
        )

        viewModel.load()
        #expect(viewModel.state == .loading)
        #expect(viewModel.fastingDuration == nil)

        try await waitUntilSettled(viewModel)
        #expect(viewModel.fastingDuration != nil)
    }

    // MARK: - Helper

    /// Polls `viewModel.state` until it leaves `.loading`/`.idle`, with a
    /// generous timeout — avoids a fixed sleep racing against the mock's
    /// own (possibly zero) delay.
    private func waitUntilSettled(_ viewModel: IslamicDaySheetViewModel, timeoutNanoseconds: UInt64 = 2_000_000_000) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while true {
            switch viewModel.state {
            case .idle, .loading:
                if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                    Issue.record("Timed out waiting for state to settle")
                    return
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            default:
                return
            }
        }
    }
}
