import SwiftUI

struct IslamicDayEventsSheet: View {
    let day: IslamicDaySheetData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if let prayerDay = day.prayerDay {
                    prayerTimesSection(prayerDay)
                }

                eventsSection
            }
            .padding()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedGregorian(day.date))
                .font(.headline)

            if let prayerDay = day.prayerDay {
                Text(prayerDay.hijri?.displayText ?? "Kein Hijri-Datum geladen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prayerTimesSection(_ prayerDay: PrayerDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gebetszeiten")
                .font(.headline)

            VStack(spacing: 8) {
                prayerRow("Fajr", prayerDay.times.fajr)
                prayerRow("Shuruq", prayerDay.times.shuruk)
                prayerRow("Dhuhr", prayerDay.times.dhuhr)
                prayerRow("Asr", prayerDay.times.asr)
                prayerRow("Maghrib", prayerDay.times.maghrib)
                prayerRow("Isha", prayerDay.times.isha)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
