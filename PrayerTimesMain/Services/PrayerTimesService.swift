import Foundation

enum PrayerTimesServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingRequestedDay
    case emptyCalendar
    case locationMismatch
    case missingTimezone
    case missingCoordinate

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
        case .locationMismatch:
            return "Die Antwort bezieht sich auf einen anderen Ort als angefragt. Bitte erneut versuchen."
        case .missingTimezone:
            return "Die Antwort enthält keine gültige Zeitzone."
        case .missingCoordinate:
            return "Für diesen Ort liegen keine bestätigten Koordinaten vor. Bitte Ort in den Einstellungen erneut bestätigen."
        }
    }
}

/// Narrow seam around the single-day AlAdhan lookup so callers that need a
/// temporary, non-persisted fetch for one specific day (e.g. the Islamic
/// calendar's day sheet) can depend on this instead of the concrete
/// `PrayerTimesService`, and tests can substitute a fake implementation
/// instead of making a real network call.
protocol SingleDayPrayerTimesFetching: Sendable {
    nonisolated func fetchPrayerTimesForSingleDayUncached(settings: PrayerSettings) async throws -> PrayerTimes
}

struct PrayerTimesService: SingleDayPrayerTimesFetching {
    // Requested coordinate vs. the coordinate AlAdhan's response metadata
    // actually reports back must agree closely — we always send an exact
    // coordinate (never an address for AlAdhan to geocode itself), so any
    // real deviation means something went wrong rather than "a nearby
    // match". This margin (~5.5km) is generous enough for rounding but
    // tight enough to catch a genuinely wrong location.
    nonisolated private static let maxPlausibleCoordinateDeviation = 0.05

    nonisolated init() {}

    nonisolated func fetchPrayerTimesForSingleDayUncached(settings: PrayerSettings) async throws -> PrayerTimes {
        guard let location = settings.location, location.coordinate.isPlausible else {
            throw PrayerTimesServiceError.missingCoordinate
        }

        let baseURL = "https://api.aladhan.com/v1"
        let datePath = apiDateString(from: settings.date)

        guard var components = URLComponents(string: "\(baseURL)/timings/\(datePath)") else {
            throw PrayerTimesServiceError.invalidURL
        }

        components.queryItems = queryItems(location: location, method: settings.method)

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

        try validate(meta: item.meta, against: location)

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
            timezone: item.meta.timezone,
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
        guard let location = settings.location, location.coordinate.isPlausible else {
            throw PrayerTimesServiceError.missingCoordinate
        }

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: coverageDays - 1, to: start) ?? start

        let months = coveredMonths(from: start, to: end)

        var allDays: [PrayerDay] = []

        for month in months {
            let monthDays = try await fetchCalendarMonth(
                year: month.year,
                month: month.month,
                location: location,
                method: settings.method
            )
            allDays.append(contentsOf: monthDays)
        }

        let startISO = isoDateString(from: start)
        let endISO = isoDateString(from: end)

        // The calendar endpoint always returns whole months, so days
        // outside the required [start, end] window are already paid for
        // by the same requests — keep all of them instead of discarding
        // them. That extends the widget/app's future coverage (and
        // therefore delays the next refetch) "for free", and never costs
        // an extra request: the set of months fetched above is unchanged.
        let deduplicatedDays = Dictionary(grouping: allDays, by: \.isoDate)
            .compactMap { $0.value.first }
            .sorted { $0.isoDate < $1.isoDate }

        let coversRequiredWindow = deduplicatedDays.contains {
            $0.isoDate >= startISO && $0.isoDate <= endISO
        }

        guard coversRequiredWindow else {
            throw PrayerTimesServiceError.emptyCalendar
        }

        return PrayerTimesCache(
            locationKey: LocationKey.key(address: settings.address, location: settings.location),
            methodKey: String(describing: settings.method),
            fetchedAt: Date(),
            days: deduplicatedDays
        )
    }

    nonisolated private func fetchCalendarMonth(
        year: Int,
        month: Int,
        location: PrayerLocation,
        method: PrayerCalculationMethod
    ) async throws -> [PrayerDay] {
        let baseURL = "https://api.aladhan.com/v1"

        guard var components = URLComponents(string: "\(baseURL)/calendar/\(year)/\(month)") else {
            throw PrayerTimesServiceError.invalidURL
        }

        components.queryItems = queryItems(location: location, method: method)

        guard let url = components.url else {
            throw PrayerTimesServiceError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw PrayerTimesServiceError.invalidResponse
        }

        let decoded: PrayerCalendarResponse

        do {
            decoded = try JSONDecoder().decode(PrayerCalendarResponse.self, from: data)
        } catch let error as DecodingError {
            #if DEBUG
            // Structural decode diagnostics only (coding path, expected
            // type) — never the request address/settings. Gated behind
            // DEBUG so it doesn't spam the console in release builds.
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
            #endif

            throw error
        } catch {
            #if DEBUG
            print("OTHER DECODE ERROR:", error)
            #endif
            throw error
        }

        if let firstDay = decoded.data.first {
            try validate(meta: firstDay.meta, against: location)
        }

        return await withTaskGroup(of: PrayerDay.self) { group in
            for item in decoded.data {
                group.addTask {

                    return PrayerDay(
                        isoDate: self.gregorianAPIToISO(item.date.gregorian.date),
                        hijri: HijriDay(
                            day: item.date.hijri.day,
                            month: item.date.hijri.month.en,
                            year: item.date.hijri.year
                        ),
                        times: PrayerTimes(
                            fajr: self.cleanTime(item.timings.fajr),
                            shuruk: self.cleanTime(item.timings.sunrise),
                            dhuhr: self.cleanTime(item.timings.dhuhr),
                            asr: self.cleanTime(item.timings.asr),
                            maghrib: self.cleanTime(item.timings.maghrib),
                            isha: self.cleanTime(item.timings.isha),
                            readableDate: item.date.readable,
                            readableDay: item.date.gregorian.weekday.en,
                            hijriDate: item.date.hijri.date,
                            hijriDay: item.date.hijri.weekday.ar ?? item.date.hijri.weekday.en,
                            timezone: item.meta.timezone
                        )
                    )                }
            }

            return await group.reduce(into: [PrayerDay]()) { result, day in
                result.append(day)
            }
        }
    }

    nonisolated private func queryItems(location: PrayerLocation, method: PrayerCalculationMethod) -> [URLQueryItem] {
        [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "method", value: method.apiValue)
        ]
    }

    /// Decision 6: never silently trust AlAdhan for a place name, but do
    /// verify its response metadata actually corresponds to the coordinate
    /// we asked for — if it clearly doesn't (or the timezone is missing),
    /// treat that as an error instead of quietly showing wrong times.
    nonisolated private func validate(meta: PrayerMeta, against location: PrayerLocation) throws {
        guard meta.timezone.trimmingCharacters(in: .whitespaces).isEmpty == false else {
            throw PrayerTimesServiceError.missingTimezone
        }

        let latDelta = abs(meta.latitude - location.coordinate.latitude)
        let lonDelta = abs(meta.longitude - location.coordinate.longitude)

        guard latDelta <= Self.maxPlausibleCoordinateDeviation,
              lonDelta <= Self.maxPlausibleCoordinateDeviation else {
            throw PrayerTimesServiceError.locationMismatch
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
}
