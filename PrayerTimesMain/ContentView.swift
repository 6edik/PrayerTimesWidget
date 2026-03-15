import SwiftUI
import WidgetKit

struct ContentView: View {
    private let service = PrayerTimesService()
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()

    @State private var prayerTimes = PrayerTimes(
        fajr: "--:--",
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
        hijriDate: "--",
        timezone: "--"
    )

    @State private var currentAddress = "--"
    @State private var currentMethod = "--"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Gebetszeiten")
                    .font(.largeTitle.bold())

                HStack(spacing: 8) {
                    Text(prayerTimes.readableDate)
                    Text("•")
                    Text(prayerTimes.hijriDate)
                }
                .font(.subheadline)
                
                HStack(spacing: 8) {
                  Text(currentAddress)
                    Text("•")
                    Text(prayerTimes.timezone)
                }
                    .font(.subheadline)
                
                Text(currentMethod)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                ForEach(PrayerTimesMapper.rows(from: prayerTimes)) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(row.time)
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if isLoading {
                    ProgressView()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Neu laden") {
                    Task { await loadPrayerTimes() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Heute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") {
                        showSettings = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                PrayerSettingsView {
                    Task { await loadPrayerTimes() }
                }
            }
        }
        .task {
            await loadPrayerTimes()
        }
    }

    @MainActor
    private func loadPrayerTimes() async {
        isLoading = true
        errorMessage = nil

        do {
            let settings = settingsStore.load()
            currentAddress = settings.address
            currentMethod = PrayerCalculationMethod(rawValue: settings.method)?.title ?? "Unbekannt"
            
            let times = try await service.fetchPrayerTimes(settings: settings)
            prayerTimes = times
            store.save(times)

            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
        } catch {
            let settings = settingsStore.load()
            currentAddress = settings.address
            currentMethod = PrayerCalculationMethod(rawValue: settings.method)?.title ?? "Unbekannt"
            errorMessage = "API konnte nicht geladen werden."
        }

        isLoading = false
    }
}

#Preview {
    ContentView()
}
