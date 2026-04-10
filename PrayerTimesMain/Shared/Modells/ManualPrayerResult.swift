import Foundation

struct ManualPrayerResult: Equatable {
    let address: String
    let method: PrayerCalculationMethod
    let date: Date

    /// Unmodified API/cache values — never altered by the stored
    /// minute adjustments.
    let rawTimes: PrayerTimes

    /// `rawTimes` with the user's stored minute adjustments applied. This is
    /// what the result view displays.
    let displayTimes: PrayerTimes

    /// The adjustments that were applied to produce `displayTimes`, so the
    /// UI can show a "persönliche Justierung angewendet" indicator.
    let appliedAdjustments: PrayerAdjustments

    var hasAppliedAdjustments: Bool {
        appliedAdjustments != .zero
    }
}
