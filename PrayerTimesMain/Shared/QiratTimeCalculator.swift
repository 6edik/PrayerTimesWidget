import Foundation

/// Pure validity check for a Karāha window (periods traditionally
/// considered disliked for *voluntary* prayer): `start`/`end` must both be
/// resolved and `end` strictly after `start` — never fabricates a window
/// from missing or malformed input.
nonisolated enum QiratTimeCalculator {
    struct Window: Equatable {
        let start: Date
        let end: Date
    }

    static func window(start: Date?, end: Date?) -> Window? {
        guard let start, let end, end > start else { return nil }
        return Window(start: start, end: end)
    }
}
