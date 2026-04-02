import Foundation
import Combine

@MainActor
final class IslamicCalendarViewModel: ObservableObject {
    @Published private(set) var specialDays: [IslamicSpecialDay] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: IslamicCalendarService
    private var loadedYear: Int?

    init(service: IslamicCalendarService? = nil) {
        self.service = service ?? IslamicCalendarService()
    }

    var sectionTitle: String {
        guard let first = specialDays.first else { return "Besondere Tage" }
        return "Besondere Tage \(first.gregorianYear)"
    }

    func loadYear(for date: Date) async {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        guard loadedYear != year else { return }

        isLoading = true
        errorMessage = nil

        do {
            specialDays = try await service.fetchSpecialDays(forGregorianYear: year)
            loadedYear = year
        } catch {
            specialDays = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func specialDays(for date: Date) -> [IslamicSpecialDay] {
        let calendar = Calendar(identifier: .gregorian)
        return specialDays
            .filter { calendar.isDate($0.sortDate, inSameDayAs: date) }
            .sorted { $0.title < $1.title }
    }
    
    func hijriDisplayText(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)

        if let event = specialDays.first(where: { calendar.isDate($0.sortDate, inSameDayAs: date) }) {
            return "\(event.hijriDay). \(event.hijriMonth) \(event.hijriYear)"
        }

        return "Kein Hijri-Ereignis geladen"
    }
}
