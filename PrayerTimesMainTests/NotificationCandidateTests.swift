import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers "Berücksichtige die Zahl ausstehender Mitteilungen und
/// priorisiere nahe Termine" and "Plane keine Benachrichtigung für
/// vergangene Zeitpunkte".
@MainActor
struct NotificationCandidateTests {
    private func candidate(id: String, minutesFromNow: Double, now: Date) -> NotificationCandidate {
        NotificationCandidate(
            identifier: id,
            fireDate: now.addingTimeInterval(minutesFromNow * 60),
            title: id,
            body: id
        )
    }

    @Test func pastCandidatesAreNeverScheduled() async throws {
        let now = Date()
        let candidates = [
            candidate(id: "past", minutesFromNow: -10, now: now),
            candidate(id: "future", minutesFromNow: 10, now: now)
        ]

        let result = NotificationCandidate.prioritized(from: candidates, budget: 64, now: now)

        #expect(result.map(\.identifier) == ["future"])
    }

    @Test func nearestCandidatesWinWhenOverBudget() async throws {
        let now = Date()
        let candidates = [
            candidate(id: "far", minutesFromNow: 300, now: now),
            candidate(id: "near", minutesFromNow: 5, now: now),
            candidate(id: "middle", minutesFromNow: 60, now: now)
        ]

        let result = NotificationCandidate.prioritized(from: candidates, budget: 2, now: now)

        #expect(result.map(\.identifier) == ["near", "middle"])
    }

    @Test func zeroBudgetSchedulesNothing() async throws {
        let now = Date()
        let candidates = [candidate(id: "a", minutesFromNow: 5, now: now)]

        let result = NotificationCandidate.prioritized(from: candidates, budget: 0, now: now)

        #expect(result.isEmpty)
    }

    @Test func budgetLargerThanCandidateCountKeepsAllFutureOnes() async throws {
        let now = Date()
        let candidates = [
            candidate(id: "a", minutesFromNow: 5, now: now),
            candidate(id: "b", minutesFromNow: 10, now: now)
        ]

        let result = NotificationCandidate.prioritized(from: candidates, budget: 64, now: now)

        #expect(result.count == 2)
    }
}
