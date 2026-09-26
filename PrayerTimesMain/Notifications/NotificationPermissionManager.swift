import Foundation
import Combine
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Wraps `UNUserNotificationCenter` authorization. Deliberately does *not*
/// request authorization on its own — callers must only invoke
/// `requestAuthorizationIfNeeded()` in direct response to the user enabling
/// a notification toggle, never automatically on launch or on screen
/// appearance.
@MainActor
final class NotificationPermissionManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Call only from an explicit user action (a toggle turning on). A
    /// no-op (returns the existing status) if the user has already been
    /// asked — `requestAuthorization` itself would silently do nothing in
    /// that case, but we still want a clear true/false result for the
    /// caller to react to (e.g. point to Settings on `.denied`).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let current = await center.notificationSettings()

        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationStatus = current.authorizationStatus
            return true

        case .denied:
            authorizationStatus = .denied
            return false

        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshStatus()
                return granted
            } catch {
                await refreshStatus()
                return false
            }

        @unknown default:
            await refreshStatus()
            return false
        }
    }

    func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
