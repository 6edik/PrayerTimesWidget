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

        let parseFormatter = DateFormatter()
        parseFormatter.locale = Locale(identifier: "en_US_POSIX")
        parseFormatter.dateFormat = "dd-MM-yyyy"

        // AlAdhan's own `month.en` is always English ("January", never
        // "Januar") — every Gregorian display string for a special day is
        // built locally from the already-parsed `sortDate` with a German
        // formatter instead, so "Besondere Tage" never shows an English
        // month name.
        let readableFormatter = DateFormatter()
        readableFormatter.locale = Locale(identifier: "de_DE")
        readableFormatter.dateFormat = "d. MMMM yyyy"

        let monthNameFormatter = DateFormatter()
        monthNameFormatter.locale = Locale(identifier: "de_DE")
        monthNameFormatter.dateFormat = "MMMM"

        return decoded.data.flatMap { day in
            let holidays = day.hijri.holidays
            let sortDate = parseFormatter.date(from: day.gregorian.date) ?? .distantPast

            return holidays.map { holiday in
                IslamicSpecialDay(
                    title: holiday,
                    gregorianReadable: readableFormatter.string(from: sortDate),
                    gregorianMonthName: monthNameFormatter.string(from: sortDate),
                    gregorianYear: day.gregorian.year,
                    hijriDay: day.hijri.day,
                    hijriMonth: day.hijri.month.en,
                    hijriYear: day.hijri.year,
                    hijriWeekday: day.hijri.weekday.ar ?? day.hijri.weekday.en,
                    sortDate: sortDate,
                    hijriMonthNumber: day.hijri.month.number
                )
            }
        }
    }
}
