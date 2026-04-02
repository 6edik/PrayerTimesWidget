import Foundation

enum PrayerCalculationMethod: Int, CaseIterable, Codable, Identifiable {
    case karachi = 1
    case muslimWorldLeague = 3
    case ummAlQura = 4
    case egyptian = 5
    case dubai = 8
    case ditib = 13

    nonisolated var id: Int { rawValue }

    nonisolated var title: String {
        switch self {
        case .karachi: return "Karachi"
        case .muslimWorldLeague: return "Muslim World League"
        case .ummAlQura: return "Umm Al-Qura"
        case .egyptian: return "Egyptian"
        case .dubai: return "Dubai"
        case .ditib: return "DITIB"
        }
    }

    nonisolated var apiValue: String {
        String(rawValue)
    }
}
