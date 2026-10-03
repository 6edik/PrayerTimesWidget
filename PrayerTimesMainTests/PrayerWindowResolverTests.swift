import Testing
import Foundation
@testable import PrayerTimesMain

/// Covers `PrayerWindowResolver`: the single current/next-prayer-window
/// resolver shared by every widget family (and, via the same chaining
/// logic as `LastThirdOfNightResolver`/`QiratTimeResolver`, conceptually
/// consistent with the rest of the app's day-boundary handling). Focused on
/// day-change correctness (before Fajr, after Isha, across midnight),
/// location-timezone-vs-device-timezone, midnight-wrapping adjustments via
/// `dayOffsets`, and the honest-nil empty state.
@MainActor
struct PrayerWindowResolverTests {

    private func makeTimes(
        fajr: String = "05:30",
        shuruk: String = "07:00",
        dhuhr: String = "12:15",
        asr: String = "14:45",
        maghrib: String = "17:15",
        isha: String = "18:45",
        timezone: String = "Europe/Berlin"
    ) -> PrayerTimes {
        PrayerTimes(
            fajr: fajr,
            shuruk: shuruk,
            dhuhr: dhuhr,
            asr: asr,
            maghrib: maghrib,
            isha: isha,
            readableDate: "--",
            readableDay: "--",
            hijriDate: "--",
            hijriDay: "--",
            timezone: timezone
        )
    }

    private func adjusted(_ times: PrayerTimes, dayOffsets: PrayerDayOffsets = .zero) -> AdjustedPrayerTimes {
        AdjustedPrayerTimes(times: times, dayOffsets: dayOffsets)
    }

    private func berlinDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Ordinary midday window, no neighboring days needed

    @Test func middayWindowResolvesCurrentAndNextFromTodayAlone() async throws {
        let now = berlinDate(2026, 1, 2, 13, 0) // between Dhuhr (12:15) and Asr (14:45)
        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(makeTimes()),
            previousDayTimes: nil,
            nextDayTimes: nil
        )

        let result = try #require(window)
        #expect(result.currentName == "Dhuhr")
        #expect(result.nextName == "Asr")
        #expect(result.start == berlinDate(2026, 1, 2, 12, 15))
        #expect(result.end == berlinDate(2026, 1, 2, 14, 45))
    }

    // MARK: - After Isha, before midnight: window crosses into tomorrow

    @Test func afterIshaUsesTomorrowsFajrAsTheWindowEnd() async throws {
        let now = berlinDate(2026, 1, 2, 20, 0) // after today's Isha (18:45)
        let tomorrow = makeTimes(fajr: "05:28")

        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(makeTimes()),
            previousDayTimes: nil,
            nextDayTimes: adjusted(tomorrow)
        )

        let result = try #require(window)
        #expect(result.currentName == "Isha")
        #expect(result.nextName == "Fajr")
        #expect(result.start == berlinDate(2026, 1, 2, 18, 45))
        #expect(result.end == berlinDate(2026, 1, 3, 5, 28))
    }

    @Test func afterIshaWithoutTomorrowsDataReturnsNilRatherThanAFabricatedWindow() async throws {
        let now = berlinDate(2026, 1, 2, 20, 0)

        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(makeTimes()),
            previousDayTimes: nil,
            nextDayTimes: nil
        )

        #expect(window == nil)
    }

    // MARK: - After midnight, before Fajr: window carries over from yesterday's Isha

    @Test func afterMidnightBeforeFajrUsesYesterdaysIshaAsTheWindowStart() async throws {
        let now = berlinDate(2026, 1, 2, 1, 0) // after midnight, before today's Fajr (05:30)
        let yesterday = makeTimes(isha: "18:40")

        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(makeTimes()),
            previousDayTimes: adjusted(yesterday),
            nextDayTimes: nil
        )

        let result = try #require(window)
        #expect(result.currentName == "Isha")
        #expect(result.nextName == "Fajr")
        // Start is on the *previous* calendar day, end on today — the exact
        // day-change case this resolver exists to get right.
        #expect(result.start == berlinDate(2026, 1, 1, 18, 40))
        #expect(result.end == berlinDate(2026, 1, 2, 5, 30))
    }

    @Test func beforeFajrWithoutYesterdaysDataFallsBackToTodaysFajrAsCurrent() async throws {
        // No previous-day Isha available at all: the resolver has no
        // moment <= `now`, so it falls back to the earliest known moment
        // (today's own Fajr) as "current" rather than crashing or
        // fabricating an earlier instant.
        let now = berlinDate(2026, 1, 2, 1, 0)

        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(makeTimes()),
            previousDayTimes: nil,
            nextDayTimes: nil
        )

        let result = try #require(window)
        #expect(result.currentName == "Fajr")
        #expect(result.nextName == "Shuruk")
    }

    // MARK: - Midnight-wrapping adjustment via dayOffsets

    @Test func midnightWrappingIshaAdjustmentPlacesTheMomentOnTheCorrectDayViaDayOffset() async throws {
        // Yesterday's raw Isha (23:50) + 20 min adjustment -> "00:10" with
        // dayOffset == 1 — exactly the scenario `PrayerTimeAdjuster`
        // documents. `now` is just after midnight on "today", inside that
        // just-started window, so `previousDayTimes` (anchored to
        // yesterday's calendar day) is what must carry the wrapped moment
        // onto *today's* date, not `todayTimes` itself.
        var yesterdayOffsets = PrayerDayOffsets.zero
        yesterdayOffsets.isha = 1
        let yesterday = adjusted(makeTimes(isha: "00:10"), dayOffsets: yesterdayOffsets)
        let today = adjusted(makeTimes(fajr: "05:28"))

        let now = berlinDate(2026, 1, 3, 0, 20)

        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: today,
            previousDayTimes: yesterday,
            nextDayTimes: nil
        )

        let result = try #require(window)
        #expect(result.currentName == "Isha")
        // The wrapped Isha instant landed on day 3 (today) at 00:10, not
        // day 2 (where its *unadjusted* clock time would nominally sit).
        #expect(result.start == berlinDate(2026, 1, 3, 0, 10))
        #expect(result.nextName == "Fajr")
        #expect(result.end == berlinDate(2026, 1, 3, 5, 28))
    }

    // MARK: - Honest empty state: not enough resolvable moments

    @Test func fewerThanTwoResolvableMomentsReturnsNilNotAFabricatedWindow() async throws {
        // Every prayer except Maghrib fails to parse as "HH:mm" — only one
        // moment is resolvable today, and there's no neighboring data to
        // supply a second one, so no real window can be formed.
        let garbled = makeTimes(
            fajr: "--:--",
            shuruk: "--:--",
            dhuhr: "--:--",
            asr: "--:--",
            maghrib: "17:15",
            isha: "--:--"
        )

        let window = PrayerWindowResolver.resolve(
            now: berlinDate(2026, 1, 2, 12, 0),
            todayTimes: adjusted(garbled),
            previousDayTimes: nil,
            nextDayTimes: nil
        )

        #expect(window == nil)
    }

    // MARK: - Location timezone governs, never the device's ambient timezone

    @Test func locationTimezoneGovernsRegardlessOfAmbientDeviceTimezone() async throws {
        let tokyoTimes = makeTimes(
            fajr: "05:31", shuruk: "06:50", dhuhr: "11:45",
            asr: "14:30", maghrib: "17:05", isha: "18:30",
            timezone: "Asia/Tokyo"
        )

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = tokyo.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 13, minute: 0))!

        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(tokyoTimes),
            previousDayTimes: nil,
            nextDayTimes: nil
        )

        let result = try #require(window)
        #expect(result.timezoneIdentifier == "Asia/Tokyo")
        #expect(result.currentName == "Dhuhr")
        #expect(result.nextName == "Asr")

        let endComponents = tokyo.dateComponents([.hour, .minute], from: result.end)
        #expect(endComponents.hour == 14)
        #expect(endComponents.minute == 30)
    }

    // MARK: - currentTime/nextTime always mirror the actual display strings

    @Test func currentTimeAndNextTimeMirrorTheAdjustedDisplayStrings() async throws {
        let now = berlinDate(2026, 1, 2, 13, 0)
        let window = PrayerWindowResolver.resolve(
            now: now,
            todayTimes: adjusted(makeTimes(dhuhr: "12:17", asr: "14:47")),
            previousDayTimes: nil,
            nextDayTimes: nil
        )

        let result = try #require(window)
        #expect(result.currentTime == "12:17")
        #expect(result.nextTime == "14:47")
    }
}
