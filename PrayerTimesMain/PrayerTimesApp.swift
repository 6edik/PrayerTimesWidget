import SwiftUI
import BackgroundTasks

@main
struct PrayerTimesApp: App {
    @Environment(\.scenePhase) private var scenePhase

    nonisolated private static let refreshIdentifier = "com.mertgedik.prayertimes.refresh"

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { task in
            Self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.serif)
                .task {
                    Self.scheduleAppRefresh()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Self.scheduleAppRefresh()
            }
        }
    }

    nonisolated private static func scheduleAppRefresh() {
        Task {
            let preferred = await MainActor.run {
                let settings = SharedPrayerSettingsStore().loadAutoSettings()
                let store = SharedPrayerTimesStore()

                return store.suggestedRefreshDate(
                    settings: settings,
                    refreshThresholdDays: 2
                )
            }

            let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
            request.earliestBeginDate = normalizedEarliestDate(preferred)

            do {
                try BGTaskScheduler.shared.submit(request)

                await MainActor.run {
                    RefreshStatsStore().setNextPlannedRefresh(request.earliestBeginDate)
                }
            } catch {
                #if DEBUG
                print("BG refresh scheduling failed:", error)
                #endif
            }
        }
    }

    nonisolated private static func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let operation = BlockOperation {
            let semaphore = DispatchSemaphore(value: 0)

            Task {
                // Same refresh policy as the app and the widget: one shared
                // "does this need a network refresh" check and one shared
                // set of post-refresh side effects (stats, widget reload).
                let autoSettings = await MainActor.run {
                    SharedPrayerSettingsStore().loadAutoSettings()
                }

                _ = await PrayerRefreshCoordinator().refreshIfNeeded(
                    settings: autoSettings,
                    source: .backgroundTask
                )

                semaphore.signal()
            }

            semaphore.wait()
        }

        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        queue.addOperation(operation)
    }
    nonisolated private static func normalizedEarliestDate(_ preferred: Date?) -> Date {
        let minimum = Date().addingTimeInterval(15 * 60)
        guard let preferred else { return minimum }
        return preferred > minimum ? preferred : minimum
    }
}
