import Foundation

struct IslamicDayEvents: Identifiable {
    let id = UUID()
    let date: Date
    let events: [IslamicSpecialDay]
}
