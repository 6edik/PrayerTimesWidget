import Foundation

struct IslamicCalendarYearCache: Codable, Equatable {
    let year: Int
    let fetchedAt: Date
    let specialDays: [IslamicSpecialDay]
}
