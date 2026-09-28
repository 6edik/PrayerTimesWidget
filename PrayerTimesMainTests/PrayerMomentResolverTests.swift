import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers "Berücksichtige Tageswechsel, Justierungen über Mitternacht,
/// Ortszeitzone und Sommerzeit" and "Unterschiedliche Geräte- und
/// Ortszeitzonen" from the notifications spec.
@MainActor
struct PrayerMomentResolverTests {
    private func utcComponents(of date: Date) -> DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test func plainTimeWithinSameDay() async throws {
        let date = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "05:12",
            adjustmentMinutes: 0,
            timezoneIdentifier: "Europe/Berlin"
        )

        let comps = utcComponents(of: date!)
        // Berlin is UTC+2 in September (CEST).
        #expect(comps.year == 2026 && comps.month == 9 && comps.day == 27)
        #expect(comps.hour == 3 && comps.minute == 12)
    }

    @Test func ishaAdjustmentPastMidnightLandsOnTheNextCalendarDay() async throws {
        let date = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "23:50",
            adjustmentMinutes: 20,
            timezoneIdentifier: "Europe/Berlin"
        )

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let comps = berlin.dateComponents([.year, .month, .day, .hour, .minute], from: date!)

        #expect(comps.day == 28) // rolled from the 27th to the 28th
        #expect(comps.hour == 0 && comps.minute == 10)
    }

    @Test func fajrAdjustmentBeforeMidnightLandsOnThePreviousCalendarDay() async throws {
        let date = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "00:05",
            adjustmentMinutes: -20,
            timezoneIdentifier: "Europe/Berlin"
        )

        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let comps = berlin.dateComponents([.year, .month, .day, .hour, .minute], from: date!)

        #expect(comps.day == 26)
        #expect(comps.hour == 23 && comps.minute == 45)
    }

    @Test func usesTheLocationTimezoneNotTheDeviceOne() async throws {
        // Tokyo is UTC+9 year-round (no DST) — same local time as Berlin's
        // input, but a different absolute instant.
        let tokyo = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "05:00",
            adjustmentMinutes: 0,
            timezoneIdentifier: "Asia/Tokyo"
        )
        let berlin = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "05:00",
            adjustmentMinutes: 0,
            timezoneIdentifier: "Europe/Berlin"
        )

        #expect(tokyo != berlin)
        // Tokyo (UTC+9) is 7 hours ahead of Berlin (UTC+2) in September.
        #expect(abs(tokyo!.timeIntervalSince(berlin!) - (-7 * 3600)) < 1)
    }

    @Test func respectsDaylightSavingTimeForTheLocation() async throws {
        // Same local wall-clock time, same timezone identifier, but one
        // date is in EST and the other in EDT — the resulting UTC instants
        // must differ by exactly the DST hour.
        let winter = PrayerMomentResolver.resolve(
            isoDate: "2026-01-15",
            rawTime: "12:00",
            adjustmentMinutes: 0,
            timezoneIdentifier: "America/New_York"
        )
        let summer = PrayerMomentResolver.resolve(
            isoDate: "2026-07-15",
            rawTime: "12:00",
            adjustmentMinutes: 0,
            timezoneIdentifier: "America/New_York"
        )

        let winterUTC = utcComponents(of: winter!)
        let summerUTC = utcComponents(of: summer!)

        #expect(winterUTC.hour == 17) // EST = UTC-5
        #expect(summerUTC.hour == 16) // EDT = UTC-4
    }

    @Test func invalidTimezoneIdentifierReturnsNil() async throws {
        let date = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "05:00",
            adjustmentMinutes: 0,
            timezoneIdentifier: "Not/ARealZone"
        )
        #expect(date == nil)
    }

    @Test func malformedTimeReturnsNil() async throws {
        let date = PrayerMomentResolver.resolve(
            isoDate: "2026-09-27",
            rawTime: "not-a-time",
            adjustmentMinutes: 0,
            timezoneIdentifier: "Europe/Berlin"
        )
        #expect(date == nil)
    }
}
