import SwiftUI

/// Read-only inspector for the local auto-refresh cache: shows exactly which
/// days are actually persisted, under which location/method, and lets the
/// user toggle between the personally-adjusted display (matching Home and
/// the widget) and the raw, unadjusted API values. Opening this view or
/// switching between days never triggers a network request and never
/// modifies the cache — `viewModel.load()` only reads local UserDefaults.
struct CachedPrayerTimesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CachedPrayerTimesViewModel()
    @State private var showRawTimes = false

    var body: some View {
        NavigationStack {
            AppPageHeader(title: "Gespeicherte Gebetszeiten")
                .fontDesign(nil)

            Form {
                if viewModel.hasCachedData {
                    Section("Cache-Details") {
                        detailRow("Ort", viewModel.cacheLocationDisplay)

                        if let coordinateDisplay = viewModel.cacheCoordinateDisplay {
                            Text(coordinateDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        detailRow("Methode", viewModel.cacheMethodDisplay)
                        detailRow("Gespeicherte Tage", "\(viewModel.days.count)")
                        detailRow("Letzter erfolgreicher Abruf", formattedFetchedAt)
                    }

                    if let notice = viewModel.noticeMessage {
                        Section {
                            Label(notice, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section {
                        Toggle("Rohzeiten ohne Justierung anzeigen", isOn: $showRawTimes)
                    } footer: {
                        Text(
                            showRawTimes
                            ? "Zeigt die unveränderten, gespeicherten API-Zeiten ohne deine persönliche Minuten-Justierung."
                            : "Zeigt die Zeiten inklusive deiner persönlichen Minuten-Justierung, konsistent mit Startseite und Widget."
                        )
                    }

                    Section("Gespeicherte Tage") {
                        ForEach(viewModel.days) { day in
                            NavigationLink {
                                CachedPrayerDayDetailView(
                                    day: day,
                                    displayTimes: viewModel.displayTimes(for: day, showRaw: showRawTimes),
                                    dayOffsets: viewModel.dayOffsets(for: day),
                                    showRaw: showRawTimes
                                )
                            } label: {
                                dayRow(day)
                            }
                        }
                    }
                } else {
                    Section {
                        emptyState
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // Re-reads the local cache from disk — never a network
                    // fetch — so this view reflects a refresh performed
                    // elsewhere (Home, widget, background task) while this
                    // sheet was already open.
                    Button {
                        viewModel.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Aus dem lokalen Cache neu laden")
                }
            }
            .task {
                viewModel.load()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Kein Cache vorhanden")
                .font(.headline)

            Text("Für die aktuellen Einstellungen sind noch keine Gebetszeiten im lokalen Auto-Cache gespeichert. Öffne die App mit Internetverbindung, damit die Zeiten automatisch geladen werden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func dayRow(_ day: CachedPrayerTimesViewModel.DayEntry) -> some View {
        let times = viewModel.displayTimes(for: day, showRaw: showRawTimes)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formattedDate(day))
                        .fontWeight(viewModel.isToday(day) ? .semibold : .regular)

                    if viewModel.isToday(day) {
                        Text("Heute")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                if let hijri = day.hijri {
                    Text(hijri.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Fajr \(times.fajr)")
                Text("Maghrib \(times.maghrib)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var formattedFetchedAt: String {
        guard let fetchedAt = viewModel.fetchedAt else { return "--" }
        return fetchedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedDate(_ day: CachedPrayerTimesViewModel.DayEntry) -> String {
        guard let date = viewModel.date(for: day) else { return day.isoDate }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Detail page for a single cached day — all six prayer times plus, for
/// adjusted (non-raw) times, a badge on any prayer whose adjustment wrapped
/// across midnight into the previous/next calendar day.
private struct CachedPrayerDayDetailView: View {
    let day: CachedPrayerTimesViewModel.DayEntry
    let displayTimes: PrayerTimes
    let dayOffsets: PrayerDayOffsets
    let showRaw: Bool

    /// This specific cached day's own calendar day, in its own timezone —
    /// never the device's — so the Friday/Jum'ah check below always
    /// matches the day actually being shown, not "today".
    private var dhuhrTitle: String {
        guard let dayStart = PrayerMomentResolver.dayStart(
            isoDate: day.isoDate, timezoneIdentifier: displayTimes.timezone
        ) else { return "Dhuhr" }
        return PrayerDisplayNaming.dhuhrLabel(date: dayStart, timezoneIdentifier: displayTimes.timezone)
    }

    var body: some View {
        Form {
            Section {
                row("Fajr", displayTimes.fajr, dayOffset: dayOffsets.fajr)
                row("Sonnenaufgang", displayTimes.shuruk, dayOffset: dayOffsets.shuruk)
                row(dhuhrTitle, displayTimes.dhuhr, dayOffset: dayOffsets.dhuhr)
                row("Asr", displayTimes.asr, dayOffset: dayOffsets.asr)
                row("Maghrib", displayTimes.maghrib, dayOffset: dayOffsets.maghrib)
                row("Isha", displayTimes.isha, dayOffset: dayOffsets.isha)
            } footer: {
                Text(
                    showRaw
                    ? "Unveränderte, gespeicherte API-Zeiten ohne Justierung."
                    : "Inklusive deiner persönlichen Minuten-Justierung."
                )
            }

            if let hijri = day.hijri {
                Section("Hijri-Datum") {
                    Text(hijri.displayText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground").ignoresSafeArea())
        .navigationTitle(day.isoDate)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String, dayOffset: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if dayOffset != 0 {
                Text(dayOffset > 0 ? "+1 Tag" : "-1 Tag")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

#Preview {
    CachedPrayerTimesView()
}
