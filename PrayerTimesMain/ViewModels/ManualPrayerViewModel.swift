import Foundation
import Combine

@MainActor
final class ManualPrayerViewModel: ObservableObject {
    @Published var query: ManualPrayerQuery
    @Published private(set) var result: ManualPrayerResult?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let settingsStore: SharedPrayerSettingsStore
    private let timesStore: SharedPrayerTimesStore
    private let service: PrayerTimesService

    init(
        settingsStore: SharedPrayerSettingsStore? = nil,
        timesStore: SharedPrayerTimesStore? = nil,
        service: PrayerTimesService? = nil
    ) {
        let resolvedSettingsStore = settingsStore ?? SharedPrayerSettingsStore()
        let resolvedTimesStore = timesStore ?? SharedPrayerTimesStore()
        let resolvedService = service ?? PrayerTimesService()

        self.settingsStore = resolvedSettingsStore
        self.timesStore = resolvedTimesStore
        self.service = resolvedService
        self.query = ManualPrayerQuery(seed: resolvedSettingsStore.loadAutoSettings())
    }

    /// - Parameter location: the coordinate confirmed by the city list or
    ///   GPS for `address`, if any. Pass `nil` for free-text addresses —
    ///   never guess a coordinate from the name here.
    func runQuery(address: String, location: PrayerLocation?) async {
        query.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        query.location = location
        await runQuery()
    }

    func runQuery() async {
        let trimmedAddress = query.address.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAddress.isEmpty else {
            errorMessage = "Bitte gib einen Ort ein."
            return
        }

        isLoading = true
        errorMessage = nil
        result = nil

        let autoSettings = settingsStore.loadAutoSettings()

        // Coordinate-aware: two queries only count as "the same place" as
        // the auto settings if they resolve to the same location key —
        // matching display names alone isn't reliable (the bundled city
        // list has 22 duplicate names, e.g. two different "Essen"s).
        let sameLocation = LocationKey.key(address: trimmedAddress, location: query.location)
            == LocationKey.key(address: autoSettings.address, location: autoSettings.location)
        let sameMethod = query.method == autoSettings.method

        if sameLocation,
           sameMethod,
           let cached = timesStore.load(for: query.date, settings: autoSettings) {
            result = ManualPrayerResult(
                address: trimmedAddress,
                method: query.method,
                date: query.date,
                rawTimes: cached,
                displayTimes: cached.applyingAdjustments(autoSettings.adjustments),
                appliedAdjustments: autoSettings.adjustments
            )
            isLoading = false
            return
        }

        do {
            let prepared = PrayerSettings(
                address: trimmedAddress,
                location: query.location,
                date: query.date,
                method: query.method
            )

            let times = try await service.fetchPrayerTimesForSingleDayUncached(settings: prepared)

            result = ManualPrayerResult(
                address: trimmedAddress,
                method: query.method,
                date: query.date,
                rawTimes: times,
                displayTimes: times.applyingAdjustments(autoSettings.adjustments),
                appliedAdjustments: autoSettings.adjustments
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func resetToAutoDefaults() {
        query = ManualPrayerQuery(seed: settingsStore.loadAutoSettings())
        result = nil
        errorMessage = nil
    }
}
