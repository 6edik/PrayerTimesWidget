import Foundation

enum PrayerCalculationMethod: Int, CaseIterable, Identifiable, Codable {
    case muslimWorldLeague = 3
    case diyanet = 13

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .muslimWorldLeague:
            return "MWL"
        case .diyanet:
            return "Diyanet"
        }
    }
}

struct PrayerSettings: Codable {
    let address: String
    let date: Date
    let method: Int
}
