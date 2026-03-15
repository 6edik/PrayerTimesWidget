import Foundation

enum PrayerTimesError: Error {
    case invalidURL
    case invalidResponse
}

struct PrayerTimesService {
    func fetchPrayerTimes(settings: PrayerSettings) async throws -> PrayerTimes {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        let dateString = dateFormatter.string(from: settings.date)

        var components = URLComponents(string: "https://api.aladhan.com/v1/timingsByAddress/\(dateString)")
        components?.queryItems = [
            URLQueryItem(name: "address", value: settings.address),
            URLQueryItem(name: "method", value: String(settings.method))
        ]

        guard let url = components?.url else {
            throw PrayerTimesError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw PrayerTimesError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(PrayerTimesResponse.self, from: data)

        return PrayerTimes(
            fajr: cleanTime(decoded.data.timings.fajr),
            dhuhr: cleanTime(decoded.data.timings.dhuhr),
            asr: cleanTime(decoded.data.timings.asr),
            maghrib: cleanTime(decoded.data.timings.maghrib),
            isha: cleanTime(decoded.data.timings.isha),
            readableDate: decoded.data.date.readable,
            hijriDate: decoded.data.date.hijri.date,
            timezone: decoded.data.meta.timezone
        )
    }

    private func cleanTime(_ value: String) -> String {
        if let first = value.split(separator: " ").first {
            return String(first)
        }
        return value
    }
}
