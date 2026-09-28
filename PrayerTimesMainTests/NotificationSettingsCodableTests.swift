import Testing
import Foundation
@testable import PrayerTimesMain

@MainActor
struct NotificationSettingsCodableTests {
    @Test func roundTripsThroughJSON() async throws {
        var settings = NotificationSettings.zero
        settings.fajr = PrayerNotificationSetting(isEnabled: true, reminderLeadTime: .fifteenMinutes, sound: .silent)
        settings.setSetting(
            HolidayNotificationSetting(isEnabled: true, notifyDayBefore: true, notifyOnDay: false, hour: 21, minute: 30),
            for: .ramadanStart
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: data)

        #expect(decoded == settings)
        #expect(decoded.setting(for: .fajr).reminderLeadTime == .fifteenMinutes)
        #expect(decoded.setting(for: .ramadanStart).hour == 21)
    }

    @Test func emptyHolidaysDictionaryBehavesAsAllDisabled() async throws {
        let settings = NotificationSettings.zero
        #expect(!settings.hasAnyHolidayEnabled)
        #expect(settings.setting(for: .eidAlAdha) == HolidayNotificationSetting())
    }

    @Test func hasAnyPrayerEnabledReflectsAnySinglePrayer() async throws {
        var settings = NotificationSettings.zero
        #expect(!settings.hasAnyPrayerEnabled)

        settings.isha.isEnabled = true
        #expect(settings.hasAnyPrayerEnabled)
    }

    @Test func holidayWithBothTogglesOffCountsAsNotEnabled() async throws {
        var settings = NotificationSettings.zero
        settings.setSetting(
            HolidayNotificationSetting(isEnabled: true, notifyDayBefore: false, notifyOnDay: false),
            for: .ashura
        )
        // isEnabled alone isn't enough — spec requires at least one of
        // "Vortag"/"Feiertag" to actually mean something.
        #expect(!settings.hasAnyHolidayEnabled)
    }

    @Test func decodingLegacyDataWithoutHolidaysKeyStillWorks() async throws {
        let legacyJSON = """
        {
            "fajr": {"isEnabled": true, "reminderLeadTime": 0, "sound": "standard"},
            "dhuhr": {"isEnabled": false, "reminderLeadTime": 0, "sound": "standard"},
            "asr": {"isEnabled": false, "reminderLeadTime": 0, "sound": "standard"},
            "maghrib": {"isEnabled": false, "reminderLeadTime": 0, "sound": "standard"},
            "isha": {"isEnabled": false, "reminderLeadTime": 0, "sound": "standard"}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: legacyJSON)
        #expect(decoded.fajr.isEnabled)
        #expect(decoded.holidays.isEmpty)
    }
}
