import Foundation

enum QiblaSheet: Identifiable {
    case info

    var id: String {
        switch self {
        case .info:
            return "info"
        }
    }
}
