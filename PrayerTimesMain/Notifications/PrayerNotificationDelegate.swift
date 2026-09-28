import Foundation
import UserNotifications

/// Decision (spec item 8): a prayer/holiday notification that fires while
/// the app is in the foreground still shows its banner, plays its sound
/// and updates the badge — exactly as if the app were backgrounded.
///
/// Reasoning: these are time-anchored reminders (a prayer starting, a
/// reminder minutes before it, a holiday today/tomorrow). Suppressing the
/// banner just because the user happens to have the app open would hide
/// the one piece of information the notification exists to deliver — the
/// user could easily be on the Qibla or Islamic-calendar tab, not looking
/// at a clock, when Isha starts. There's no benefit to silencing it here.
final class PrayerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PrayerNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
