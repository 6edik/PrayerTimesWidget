import Foundation

struct PrayerTimesResponse: Codable {
    let code: Int
    let status: String
    let data: PrayerData
}

struct PrayerData: Codable {
    let timings: PrayerTimings
    let date: PrayerDate
    let meta: PrayerMeta
}

struct PrayerTimings: Codable {
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

struct PrayerDate: Codable {
    let readable: String
    let timestamp: String
    let hijri: HijriDate
    let gregorian: GregorianDate
}

struct HijriDate: Codable {
    let date: String
    let format: String
    let day: String
    let weekday: HijriWeekday
    let month: HijriMonth
    let year: String
    let designation: DateDesignation
    let holidays: [String]?
    let adjustedHolidays: [String]?
    let method: String?
}

struct HijriWeekday: Codable {
    let en: String
    let ar: String
}

struct HijriMonth: Codable {
    let number: Int
    let en: String
    let ar: String
    let days: Int
}

struct GregorianDate: Codable {
    let date: String
    let format: String
    let day: String
    let weekday: GregorianWeekday
    let month: GregorianMonth
    let year: String
    let designation: DateDesignation
    let lunarSighting: Bool
}

struct GregorianWeekday: Codable {
    let en: String
}

struct GregorianMonth: Codable {
    let number: Int
    let en: String
}

struct DateDesignation: Codable {
    let abbreviated: String
    let expanded: String
}

struct PrayerMeta: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let method: PrayerMethod
    let latitudeAdjustmentMethod: String
    let midnightMode: String
    let school: String
    let offset: PrayerOffset
}

struct PrayerMethod: Codable {
    let id: Int
    let name: String
    let params: PrayerMethodParams
    let location: PrayerMethodLocation?
}

struct PrayerMethodParams: Codable {
    let fajr: Int
    let isha: Int

    enum CodingKeys: String, CodingKey {
        case fajr = "Fajr"
        case isha = "Isha"
    }
}

struct PrayerMethodLocation: Codable {
    let latitude: Double
    let longitude: Double
}

struct PrayerOffset: Codable {
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
