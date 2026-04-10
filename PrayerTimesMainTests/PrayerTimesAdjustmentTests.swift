import Testing
@testable import PrayerTimesMain

/// Covers N2/N8 end-to-end at the `PrayerTimes` level: applying a full
/// `PrayerAdjustments` set must produce day offsets per prayer, and the
/// display-only `applyingAdjustments` must stay in sync with
/// `applyingAdjustmentsWithDayOffsets` (single source of truth — see R5).
@MainActor
struct PrayerTimesAdjustmentTests {
    private func makeTimes(isha: String = "22:00", fajr: String = "05:00") -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: "07:00",
            dhuhr: "12:00",
            asr: "15:00",
            maghrib: "18:00",
            isha: isha,
            readableDate: "1 Jan 2026",
            readableDay: "Thursday",
            hijriDate: "01-01-1447",
            hijriDay: "Thursday",
            timezone: "Europe/Berlin"
        )
    }

    @Test func zeroAdjustmentsLeaveEverythingUnchangedWithZeroOffsets() async throws {
        let times = makeTimes()
        let adjusted = times.applyingAdjustmentsWithDayOffsets(.zero)

        #expect(adjusted.times == times)
        #expect(adjusted.dayOffsets == .zero)
    }

    @Test func ishaAdjustmentPastMidnightSetsOnlyIshaDayOffset() async throws {
        let times = makeTimes(isha: "23:50")
        var adjustments = PrayerAdjustments.zero
        adjustments.isha = 20

        let adjusted = times.applyingAdjustmentsWithDayOffsets(adjustments)

        #expect(adjusted.times.isha == "00:10")
        #expect(adjusted.dayOffsets.isha == 1)
        // Every other prayer stayed on the same day.
        #expect(adjusted.dayOffsets.fajr == 0)
        #expect(adjusted.dayOffsets.shuruk == 0)
        #expect(adjusted.dayOffsets.dhuhr == 0)
        #expect(adjusted.dayOffsets.asr == 0)
        #expect(adjusted.dayOffsets.maghrib == 0)
    }

    @Test func fajrAdjustmentBeforeMidnightSetsOnlyFajrDayOffset() async throws {
        let times = makeTimes(fajr: "00:05")
        var adjustments = PrayerAdjustments.zero
        adjustments.fajr = -20

        let adjusted = times.applyingAdjustmentsWithDayOffsets(adjustments)

        #expect(adjusted.times.fajr == "23:45")
        #expect(adjusted.dayOffsets.fajr == -1)
        #expect(adjusted.dayOffsets.isha == 0)
    }

    @Test func applyingAdjustmentsMatchesWithDayOffsetsVariant() async throws {
        let times = makeTimes(isha: "23:55")
        var adjustments = PrayerAdjustments.zero
        adjustments.isha = 10
        adjustments.fajr = -15

        let displayOnly = times.applyingAdjustments(adjustments)
        let withOffsets = times.applyingAdjustmentsWithDayOffsets(adjustments)

        // Same computation under the hood — the two must never disagree.
        #expect(displayOnly == withOffsets.times)
    }
}
