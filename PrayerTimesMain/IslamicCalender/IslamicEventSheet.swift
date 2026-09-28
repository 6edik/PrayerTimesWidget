import SwiftUI

struct IslamicDayEventsSheet: View {
    let day: IslamicDaySheetData
    @StateObject private var dayViewModel: IslamicDaySheetViewModel

    init(day: IslamicDaySheetData, dayViewModel: @autoclosure @escaping () -> IslamicDaySheetViewModel) {
        self.day = day
        _dayViewModel = StateObject(wrappedValue: dayViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                prayerTimesSection
                eventsSection
            }
            .padding()
        }
        .task {
            dayViewModel.load()
        }
        .onDisappear {
            // Discards a still-in-flight single-day request (if any) so a
            // late result can never land back into this closed sheet.
            dayViewModel.cancel()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedGregorian(day.date))
                .font(.headline)

            Text(day.hijriText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var prayerTimesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gebetszeiten")
                    .font(.headline)
                Spacer()
                sourceBadge
            }

            switch dayViewModel.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Lade Gebetszeiten …")
                        .foregroundStyle(.secondary)
                }

            case .loaded(let raw, let adjusted, _):
                VStack(spacing: 8) {
                    prayerRow("Fajr", adjusted.fajr)
                    prayerRow("Shuruq", adjusted.shuruk)
                    prayerRow("Dhuhr", adjusted.dhuhr)
                    prayerRow("Asr", adjusted.asr)
                    prayerRow("Maghrib", adjusted.maghrib)
                    prayerRow("Isha", adjusted.isha)
                }

                if adjusted != raw {
                    Label("Persönliche Justierung angewendet", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

            case .offline:
                Label(
                    "Keine Internetverbindung. Für diesen Tag ist kein passender Cache-Eintrag vorhanden.",
                    systemImage: "wifi.slash"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Marks, next to the "Gebetszeiten" heading, whether the shown times
    /// came from the existing Auto-Cache or from a temporary single-day
    /// fetch — never persisted, so it's worth being explicit about it.
    @ViewBuilder
    private var sourceBadge: some View {
        if case .loaded(_, _, let source) = dayViewModel.state {
            switch source {
            case .cached:
                Label("Aus Cache", systemImage: "internaldrive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .fetched:
                Label("Einzelabfrage", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ereignisse")
                .font(.headline)

            if day.events.isEmpty {
                Text("Keine Ereignisse an diesem Tag")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(day.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline)

                        Text(event.gregorianReadable)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("\(event.hijriDay). \(event.hijriMonth) \(event.hijriYear)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func prayerRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func formattedGregorian(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
