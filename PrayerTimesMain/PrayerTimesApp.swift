import SwiftUI
import BackgroundTasks
import WidgetKit

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
                print("BG refresh scheduling failed:", error)
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
                let service = PrayerTimesService()

                let (store, statsStore, autoSettings, prayerSettings) = await MainActor.run {
                    let store = SharedPrayerTimesStore()
                    let settingsStore = SharedPrayerSettingsStore()
                    let statsStore = RefreshStatsStore()
                    let autoSettings = settingsStore.loadAutoSettings()
                    let prayerSettings = settingsStore.loadPrayerSettings(for: Date())
                    return (store, statsStore, autoSettings, prayerSettings)
                }

                let shouldFetch = await MainActor.run {
                    !store.hasToday(for: autoSettings, referenceDate: Date()) ||
                    store.needsRefresh(
                        settings: autoSettings,
                        referenceDate: Date(),
                        refreshThresholdDays: 2
                    )
                }

                if !shouldFetch {
                    await MainActor.run {
                        statsStore.setNextPlannedRefresh(
                            store.suggestedRefreshDate(
                                settings: autoSettings,
                                refreshThresholdDays: 2
                            )
                        )
                    }
                    semaphore.signal()
                    return
                }

                await MainActor.run {
                    statsStore.markAttempt(source: .backgroundTask)
                }

                do {
                    let fetchStart = PrayerCachePolicy.fetchStart(from: prayerSettings.date)

                    let cache = try await service.fetchPrayerTimesCache(
                        settings: prayerSettings,
                        referenceDate: fetchStart,
                        coverageDays: PrayerCachePolicy.totalDays
                    )

                    await MainActor.run {
                        store.replaceCache(with: cache)
                        UserDefaults(suiteName: AppGroup.id)?.set(Date(), forKey: "last_refresh")

                        statsStore.markSuccess(source: .backgroundTask)
                        statsStore.incrementWidgetReloadCount()
                        statsStore.setNextPlannedRefresh(
                            store.suggestedRefreshDate(
                                settings: autoSettings,
                                refreshThresholdDays: 2
                            )
                        )
                    }

                    WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
                } catch {
                    await MainActor.run {
                        statsStore.markFailure(
                            source: .backgroundTask,
                            error: error.localizedDescription
                        )
                    }
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
    nonisolated private static func normalizedEarliestDate(_ preferred: Date?) -> Date {
        let minimum = Date().addingTimeInterval(15 * 60)
        guard let preferred else { return minimum }
        return preferred > minimum ? preferred : minimum
    }
}
