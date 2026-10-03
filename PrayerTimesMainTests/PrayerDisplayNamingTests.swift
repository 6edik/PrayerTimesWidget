import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers Block 1 (Jum'ah on Fridays): weekday must be judged in the
/// *prayer location's* own timezone, never the device's, and must stay
/// correct across a DST transition.
@MainActor
struct PrayerDisplayNamingTests {

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, timezone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    @Test func fridayInLocationTimezoneIsJumuah() async throws {
        // 2026-01-02 is a Friday.
        let friday = date(year: 2026, month: 1, day: 2, hour: 12, minute: 0, timezone: "Europe/Berlin")
        #expect(PrayerDisplayNaming.isJumuahDhuhr(date: friday, timezoneIdentifier: "Europe/Berlin"))
        #expect(PrayerDisplayNaming.dhuhrLabel(date: friday, timezoneIdentifier: "Europe/Berlin") == "Jum'ah")
        #expect(PrayerDisplayNaming.dhuhrShortLabel(date: friday, timezoneIdentifier: "Europe/Berlin") == "JUM")
    }

    @Test func saturdayInLocationTimezoneIsNotJumuah() async throws {
        // 2026-01-03 is a Saturday.
        let saturday = date(year: 2026, month: 1, day: 3, hour: 12, minute: 0, timezone: "Europe/Berlin")
        #expect(!PrayerDisplayNaming.isJumuahDhuhr(date: saturday, timezoneIdentifier: "Europe/Berlin"))
        #expect(PrayerDisplayNaming.dhuhrLabel(date: saturday, timezoneIdentifier: "Europe/Berlin") == "Dhuhr")
        #expect(PrayerDisplayNaming.dhuhrShortLabel(date: saturday, timezoneIdentifier: "Europe/Berlin") == "DHR")
    }

    @Test func weekdayIsJudgedByLocationTimezoneNotDeviceTimezone() async throws {
        // A single absolute instant: 2026-01-01 23:30 UTC (a Thursday).
        // In Pacific/Kiritimati (UTC+14) this same instant already falls on
        // Friday 2026-01-02; in America/Los_Angeles (UTC-8) it's still
        // Thursday 2026-01-01. Neither check touches the device's own
        // timezone at all — only the passed-in location identifier.
        let instant = date(year: 2026, month: 1, day: 1, hour: 23, minute: 30, timezone: "UTC")

        #expect(PrayerDisplayNaming.isJumuahDhuhr(date: instant, timezoneIdentifier: "Pacific/Kiritimati"))
        #expect(!PrayerDisplayNaming.isJumuahDhuhr(date: instant, timezoneIdentifier: "America/Los_Angeles"))
    }

    @Test func fridayJustBeforeDSTTransitionIsStillCorrectlyJumuah() async throws {
        // Europe/Berlin springs forward on 2026-03-29 (last Sunday of
        // March). The preceding Friday, 2026-03-27, must still resolve
        // correctly despite the impending clock change two days later.
        let friday = date(year: 2026, month: 3, day: 27, hour: 13, minute: 0, timezone: "Europe/Berlin")
        let saturday = date(year: 2026, month: 3, day: 28, hour: 13, minute: 0, timezone: "Europe/Berlin")

        #expect(PrayerDisplayNaming.isJumuahDhuhr(date: friday, timezoneIdentifier: "Europe/Berlin"))
        #expect(!PrayerDisplayNaming.isJumuahDhuhr(date: saturday, timezoneIdentifier: "Europe/Berlin"))
    }

    @Test func invalidTimezoneIdentifierNeverClaimsJumuah() async throws {
        let friday = date(year: 2026, month: 1, day: 2, hour: 12, minute: 0, timezone: "Europe/Berlin")
        #expect(!PrayerDisplayNaming.isJumuahDhuhr(date: friday, timezoneIdentifier: "Not/AZone"))
        #expect(PrayerDisplayNaming.dhuhrLabel(date: friday, timezoneIdentifier: "Not/AZone") == "Dhuhr")
    }

    /// The Jum'ah caption must be exactly this one line — no parenthetical,
    /// no mention of a specific mosque's Khutba time, nothing appended.
    @Test func khutbaClarificationCaptionIsExactlyThisOneLine() async throws {
        #expect(PrayerDisplayNaming.khutbaClarificationCaption == "Berechnete Dhuhr Zeit")
    }
}
