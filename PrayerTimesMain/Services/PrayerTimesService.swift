import Foundation

enum PrayerTimesServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingRequestedDay
    case emptyCalendar

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige API-URL."
        case .invalidResponse:
            return "Ungültige API-Antwort."
        case .missingRequestedDay:
            return "Der gewünschte Tag fehlt im geladenen Kalender."
        case .emptyCalendar:
            return "Der Kalender enthält keine Daten."
        }
    }
}

struct PrayerTimesService {
    nonisolated init() {}

    nonisolated func fetchPrayerTimes(settings: PrayerSettings) async throws -> PrayerTimes {
        let fetchStart = PrayerCachePolicy.fetchStart(from: settings.date)

        let cache = try await fetchPrayerTimesCache(
            settings: settings,
            referenceDate: fetchStart,
            coverageDays: PrayerCachePolicy.totalDays
        )

        let requestedISO = isoDateString(from: settings.date)

        guard let today = cache.days.first(where: { $0.isoDate == requestedISO })?.times else {
            throw PrayerTimesServiceError.missingRequestedDay
        }

        return today
    }

    nonisolated func fetchPrayerTimesUncached(settings: PrayerSettings) async throws -> PrayerTimes {
        let fetchStart = PrayerCachePolicy.fetchStart(from: settings.date)

        let cache = try await fetchPrayerTimesCacheUncached(
            settings: settings,
            referenceDate: fetchStart,
            coverageDays: PrayerCachePolicy.totalDays
        )

        let requestedISO = isoDateString(from: settings.date)

        guard let today = cache.days.first(where: { $0.isoDate == requestedISO })?.times else {
            throw PrayerTimesServiceError.missingRequestedDay
        }

        return today
    }
    
    nonisolated func fetchPrayerTimesForSingleDayUncached(settings: PrayerSettings) async throws -> PrayerTimes {
        let baseURL = "https://api.aladhan.com/v1"
        let datePath = apiDateString(from: settings.date)

        guard var components = URLComponents(string: "\(baseURL)/timingsByAddress/\(datePath)") else {
            throw PrayerTimesServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "address", value: settings.address),
            URLQueryItem(name: "method", value: settings.method.apiValue)
        ]

        guard let url = components.url else {
            throw PrayerTimesServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil

        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw PrayerTimesServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(PrayerTimesResponse.self, from: data)
        let item = decoded.data

        return PrayerTimes(
            fajr: cleanTime(item.timings.fajr),
            shuruk: cleanTime(item.timings.sunrise),
            dhuhr: cleanTime(item.timings.dhuhr),
            asr: cleanTime(item.timings.asr),
            maghrib: cleanTime(item.timings.maghrib),
            isha: cleanTime(item.timings.isha),
            readableDate: item.date.readable,
            readableDay: item.date.gregorian.weekday.en,
            hijriDate: item.date.hijri.date,
            hijriDay: item.date.hijri.weekday.ar ?? item.date.hijri.weekday.en,
            timezone: item.meta.timezone
        )
    }
    
    nonisolated private func apiDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }

    nonisolated func fetchPrayerTimesCache(
        settings: PrayerSettings,
        referenceDate: Date = Date(),
        coverageDays: Int = PrayerCachePolicy.totalDays
    ) async throws -> PrayerTimesCache {
        try await fetchPrayerTimesCache(
            settings: settings,
            referenceDate: referenceDate,
            coverageDays: coverageDays,
            uncached: false
        )
    }

    nonisolated func fetchPrayerTimesCacheUncached(
        settings: PrayerSettings,
        referenceDate: Date = Date(),
        coverageDays: Int = PrayerCachePolicy.totalDays
    ) async throws -> PrayerTimesCache {
        try await fetchPrayerTimesCache(
            settings: settings,
            referenceDate: referenceDate,
            coverageDays: coverageDays,
            uncached: true
        )
    }

    nonisolated private func fetchPrayerTimesCache(
        settings: PrayerSettings,
        referenceDate: Date,
        coverageDays: Int,
        uncached: Bool
    ) async throws -> PrayerTimesCache {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: coverageDays - 1, to: start) ?? start

        let months = coveredMonths(from: start, to: end)

        var allDays: [PrayerDay] = []

        for month in months {
            let monthDays = try await fetchCalendarMonth(
                year: month.year,
                month: month.month,
                settings: settings,
                uncached: uncached
            )
            allDays.append(contentsOf: monthDays)
        }

        let startISO = isoDateString(from: start)
        let endISO = isoDateString(from: end)

        let filtered = allDays
            .filter { $0.isoDate >= startISO && $0.isoDate <= endISO }
            .sorted { $0.isoDate < $1.isoDate }

        guard !filtered.isEmpty else {
            throw PrayerTimesServiceError.emptyCalendar
        }

        return PrayerTimesCache(
            addressKey: normalizedAddress(settings.address),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: filtered
        )
    }

    nonisolated private func fetchCalendarMonth(
        year: Int,
        month: Int,
        settings: PrayerSettings,
        uncached: Bool
    ) async throws -> [PrayerDay] {
        let baseURL = "https://api.aladhan.com/v1"

        guard var components = URLComponents(string: "\(baseURL)/calendarByAddress/\(year)/\(month)") else {
            throw PrayerTimesServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "address", value: settings.address),
            URLQueryItem(name: "method", value: settings.method.apiValue)
        ]

        guard let url = components.url else {
            throw PrayerTimesServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = uncached ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        let session: URLSession
        if uncached {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            session = URLSession(configuration: configuration)
        } else {
            session = URLSession.shared
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw PrayerTimesServiceError.invalidResponse
        }

        let decoded: PrayerCalendarResponse

        do {
            decoded = try JSONDecoder().decode(PrayerCalendarResponse.self, from: data)
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(let type, let context):
                print("TYPE MISMATCH:", type)
                print("PATH:", context.codingPath.map(\.stringValue).joined(separator: "."))
                print("DEBUG:", context.debugDescription)

            case .valueNotFound(let type, let context):
                print("VALUE NOT FOUND:", type)
                print("PATH:", context.codingPath.map(\.stringValue).joined(separator: "."))
                print("DEBUG:", context.debugDescription)

            case .keyNotFound(let key, let context):
                print("KEY NOT FOUND:", key.stringValue)
                print("PATH:", context.codingPath.map(\.stringValue).joined(separator: "."))
                print("DEBUG:", context.debugDescription)

            case .dataCorrupted(let context):
                print("DATA CORRUPTED")
                print("PATH:", context.codingPath.map(\.stringValue).joined(separator: "."))
                print("DEBUG:", context.debugDescription)

            @unknown default:
                print("UNKNOWN DECODING ERROR:", error)
            }

            throw error
        } catch {
            print("OTHER DECODE ERROR:", error)
            throw error
        }

        return decoded.data.map { item in
            PrayerDay(
                isoDate: gregorianAPIToISO(item.date.gregorian.date),
                times: PrayerTimes(
                    fajr: cleanTime(item.timings.fajr),
                    shuruk: cleanTime(item.timings.sunrise),
                    dhuhr: cleanTime(item.timings.dhuhr),
                    asr: cleanTime(item.timings.asr),
                    maghrib: cleanTime(item.timings.maghrib),
                    isha: cleanTime(item.timings.isha),
                    readableDate: item.date.readable,
                    readableDay: item.date.gregorian.weekday.en,
                    hijriDate: item.date.hijri.date,
                    hijriDay: item.date.hijri.weekday.ar ?? item.date.hijri.weekday.en,
                    timezone: item.meta.timezone
                )
            )
        }
    }

    nonisolated private func coveredMonths(from start: Date, to end: Date) -> [(year: Int, month: Int)] {
        let calendar = Calendar(identifier: .gregorian)
        let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end

        var current = startMonth
        var result: [(year: Int, month: Int)] = []

        while current <= endMonth {
            let comps = calendar.dateComponents([.year, .month], from: current)
            result.append((year: comps.year ?? 0, month: comps.month ?? 1))
            current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
        }

        return result
    }

    nonisolated private func cleanTime(_ value: String) -> String {
        value
            .components(separatedBy: " ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? value
    }

    nonisolated private func gregorianAPIToISO(_ value: String) -> String {
        let calendar = Calendar(identifier: .gregorian)

        let input = DateFormatter()
        input.calendar = calendar
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = .current
        input.dateFormat = "dd-MM-yyyy"

        let output = DateFormatter()
        output.calendar = calendar
        output.locale = Locale(identifier: "en_US_POSIX")
        output.timeZone = .current
        output.dateFormat = "yyyy-MM-dd"

        guard let date = input.date(from: value) else { return value }
        return output.string(from: date)
    }

    nonisolated private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private func normalizedAddress(_ address: String) -> String {
        address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
