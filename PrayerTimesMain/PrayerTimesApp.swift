import SwiftUI
import BackgroundTasks
import WidgetKit

@main
struct PrayerTimesApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private static let refreshIdentifier = "com.mertgedik.prayertimes.refresh"

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { task in
            Self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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

    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = nextDesiredRefreshDate()

        do {
            try BGTaskScheduler.shared.submit(request)
            RefreshStatsStore().setNextPlannedRefresh(request.earliestBeginDate)
        } catch {
            print("BG refresh scheduling failed:", error)
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        RefreshStatsStore().markAttempt(source: .backgroundTask)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let operation = BlockOperation {
            let semaphore = DispatchSemaphore(value: 0)

            Task {
                let settings = SharedPrayerSettingsStore().load()
                let service = PrayerTimesService()
                let store = SharedPrayerTimesStore()
                let statsStore = RefreshStatsStore()

                do {
                    let times = try await service.fetchPrayerTimes(settings: settings)
                    store.save(times)
                    UserDefaults(suiteName: AppGroup.id)?.set(Date(), forKey: "last_refresh")

                    statsStore.markSuccess(source: .backgroundTask)
                    statsStore.incrementWidgetReloadCount()

                    WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
                } catch {
                    statsStore.markFailure(source: .backgroundTask, error: error.localizedDescription)
                    print("Background refresh failed:", error)
                }

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

    private static func nextDesiredRefreshDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)
        return calendar.date(byAdding: .minute, value: 1, to: startOfTomorrow) ?? Date().addingTimeInterval(15 * 60)
    }
}
