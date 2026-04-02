import Foundation

struct IslamicCalendarService {
    func fetchSpecialDays(forGregorianYear year: Int) async throws -> [IslamicSpecialDay] {
        try await withThrowingTaskGroup(of: [IslamicSpecialDay].self) { group in
            for month in 1...12 {
                group.addTask {
                    try await fetchSpecialDays(forGregorianMonth: month, year: year)
                }
            }

            var allDays: [IslamicSpecialDay] = []

            for try await monthDays in group {
                allDays.append(contentsOf: monthDays)
            }

            return allDays.sorted { $0.sortDate < $1.sortDate }
        }
    }

    private func fetchSpecialDays(forGregorianMonth month: Int, year: Int) async throws -> [IslamicSpecialDay] {
        guard let url = URL(string: "https://api.aladhan.com/v1/gToHCalendar/\(month)/\(year)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(CalendarResponse.self, from: data)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"

        return decoded.data.flatMap { day in
            let holidays = day.hijri.holidays

            return holidays.map { holiday in
                IslamicSpecialDay(
                    title: holiday,
                    gregorianReadable: formattedGregorianReadable(from: day.gregorian),
                    gregorianMonthName: day.gregorian.month.en,
                    gregorianYear: day.gregorian.year,
                    hijriDay: day.hijri.day,
                    hijriMonth: day.hijri.month.en,
                    hijriYear: day.hijri.year,
                    hijriWeekday: day.hijri.weekday.ar ?? day.hijri.weekday.en,
                    sortDate: formatter.date(from: day.gregorian.date) ?? .distantPast
                )
            }
        }
    }

    private func formattedGregorianReadable(from gregorian: GregorianDate) -> String {
        "\(gregorian.day). \(gregorian.month.en) \(gregorian.year)"
    }
}
