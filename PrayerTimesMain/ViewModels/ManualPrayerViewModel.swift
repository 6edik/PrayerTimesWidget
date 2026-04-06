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

    func runQuery(address: String) async {
        query.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let sameAddress = normalizedAddress(trimmedAddress) == normalizedAddress(autoSettings.address)
        let sameMethod = query.method == autoSettings.method

        if sameAddress,
           sameMethod,
           let cached = timesStore.load(for: query.date, settings: autoSettings) {
            result = ManualPrayerResult(
                address: trimmedAddress,
                method: query.method,
                date: query.date,
                times: cached
            )
            isLoading = false
            return
        }

        do {
            let prepared = PrayerSettings(
                address: trimmedAddress,
                date: query.date,
                method: query.method
            )

            let times = try await service.fetchPrayerTimesForSingleDayUncached(settings: prepared)

            result = ManualPrayerResult(
                address: trimmedAddress,
                method: query.method,
                date: query.date,
                times: times
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

    private func normalizedAddress(_ value: String) -> String {
        let collapsedWhitespace = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsedWhitespace
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
