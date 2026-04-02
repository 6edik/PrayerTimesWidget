import Foundation

// MARK: - Generic API Response

nonisolated struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let status: String
    let data: T
}

// MARK: - Typealiases

typealias PrayerTimesResponse = APIResponse<PrayerData>
typealias CalendarResponse = APIResponse<[CalendarDay]>
typealias PrayerCalendarResponse = APIResponse<[PrayerData]>

// MARK: - Prayer Times

nonisolated struct PrayerData: Decodable {
    let timings: PrayerTimings
    let date: PrayerDate
    let meta: PrayerMeta
}

nonisolated struct PrayerTimings: Decodable {
    let fajr: String
    let sunrise: String
    let dhuhr: String
    let asr: String
    let sunset: String
    let maghrib: String
    let isha: String
    let imsak: String
    let midnight: String
    let firstthird: String
    let lastthird: String

    enum CodingKeys: String, CodingKey {
        case fajr = "Fajr"
        case sunrise = "Sunrise"
        case dhuhr = "Dhuhr"
        case asr = "Asr"
        case sunset = "Sunset"
        case maghrib = "Maghrib"
        case isha = "Isha"
        case imsak = "Imsak"
        case midnight = "Midnight"
        case firstthird = "Firstthird"
        case lastthird = "Lastthird"
    }
}

nonisolated struct PrayerDate: Decodable {
    let readable: String
    let timestamp: String
    let hijri: HijriDate
    let gregorian: GregorianDate
}

nonisolated struct PrayerMeta: Decodable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let method: PrayerMethod
    let latitudeAdjustmentMethod: String
    let midnightMode: String
    let school: String
    let offset: PrayerOffset
}

nonisolated struct PrayerMethod: Decodable {
    let id: Int
    let name: String
    let params: [String: FlexibleValue]?
    let location: PrayerMethodLocation?
}

enum FlexibleValue: Decodable {
    case int(Int)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported value type"
        )
    }
}

nonisolated struct PrayerMethodLocation: Decodable {
    let latitude: Double
    let longitude: Double
}

nonisolated struct PrayerOffset: Decodable {
    let imsak: Int
    let fajr: Int
    let sunrise: Int
    let dhuhr: Int
    let asr: Int
    let sunset: Int
    let maghrib: Int
    let isha: Int
    let midnight: Int

    enum CodingKeys: String, CodingKey {
        case imsak = "Imsak"
        case fajr = "Fajr"
        case sunrise = "Sunrise"
        case dhuhr = "Dhuhr"
        case asr = "Asr"
        case sunset = "Sunset"
        case maghrib = "Maghrib"
        case isha = "Isha"
        case midnight = "Midnight"
    }
}

// MARK: - Calendar

nonisolated struct CalendarDay: Decodable {
    let hijri: HijriDate
    let gregorian: GregorianDate
}

// MARK: - Shared Date Models

nonisolated struct HijriDate: Decodable {
    let date: String
    let format: String?
    let day: String
    let weekday: HijriWeekday
    let month: HijriMonth
    let year: String
    let designation: DateDesignation?
    let holidays: [String]
    let adjustedHolidays: [String]?
    let method: String?

    enum CodingKeys: String, CodingKey {
        case date
        case format
        case day
        case weekday
        case month
        case year
        case designation
        case holidays
        case adjustedHolidays
        case method
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        day = try container.decode(String.self, forKey: .day)
        weekday = try container.decode(HijriWeekday.self, forKey: .weekday)
        month = try container.decode(HijriMonth.self, forKey: .month)
        year = try container.decode(String.self, forKey: .year)
        designation = try container.decodeIfPresent(DateDesignation.self, forKey: .designation)
        holidays = try container.decodeIfPresent([String].self, forKey: .holidays) ?? []
        adjustedHolidays = try container.decodeIfPresent([String].self, forKey: .adjustedHolidays)
        method = try container.decodeIfPresent(String.self, forKey: .method)
    }
}

nonisolated struct GregorianDate: Decodable {
    let date: String
    let format: String?
    let day: String
    let weekday: GregorianWeekday
    let month: GregorianMonth
    let year: String
    let designation: DateDesignation?
    let lunarSighting: Bool?
}

nonisolated struct HijriWeekday: Decodable {
    let en: String
    let ar: String?
}

nonisolated struct HijriMonth: Decodable {
    let number: Int?
    let en: String
    let ar: String?
    let days: Int?
}

nonisolated struct GregorianWeekday: Decodable {
    let en: String
}

nonisolated struct GregorianMonth: Decodable {
    let number: Int?
    let en: String
}

nonisolated struct DateDesignation: Decodable {
    let abbreviated: String
    let expanded: String
}

// MARK: - App Model

nonisolated struct IslamicSpecialDay: Identifiable {
    let id = UUID()
    let title: String
    let gregorianReadable: String
    let gregorianMonthName: String
    let gregorianYear: String
    let hijriDay: String
    let hijriMonth: String
    let hijriYear: String
    let hijriWeekday: String
    let sortDate: Date
}
