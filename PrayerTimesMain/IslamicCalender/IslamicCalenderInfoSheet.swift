import SwiftUI

// MARK: - Main Info Sheet

struct IslamicCalendarInfoSheet: View {
    @State private var showHadithSheet = false

    var body: some View {
        IslamicCalendarPageContainer(title: "Kalender-Hinweise") {
            IslamicCalendarHeroCard(
                symbol: "calendar",
                title: "Islamischer Kalender",
                subtitle: "Farben, Markierungen und Sunnah-Fastentage auf einen Blick."
            )

            colorLegendCard
            sunnahFastingCard
            notesCard
        }
        .sheet(isPresented: $showHadithSheet) {
            IslamicCalendarHadithSheet(items: IslamicCalendarInfoData.hadithItems)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var colorLegendCard: some View {
        IslamicCalendarSectionCard(title: "Farb-Legende", symbol: "paintpalette") {
            VStack(spacing: 14) {
                ForEach(IslamicCalendarInfoData.legendItems) { item in
                    legendRow(item)
                }
            }
        }
    }

    private var sunnahFastingCard: some View {
        IslamicCalendarSectionCard(title: "Sunnah-Fasten", symbol: "moon.stars") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Die blauen Markierungen weisen auf empfohlene Fasttage hin.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    fastHint("Montage")
                    fastHint("Donnerstage")
                    fastHint("Weiße Tage: 13, 14, 15")
                    fastHint("Besondere Fasttage wie Arafah, Ashura, Shawwal oder Sha'ban erscheinen in der Hadith-Übersicht")
                }

                IslamicCalendarActionButton(
                    symbol: "book.closed",
                    title: "Ahadith anzeigen",
                    subtitle: "Mit Quellen zu Sunnah-Fasten"
                ) {
                    showHadithSheet = true
                }
            }
        }
    }

    private var notesCard: some View {
        IslamicCalendarSectionCard(title: "Hinweise", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                bulletRow("Kalenderdaten und Ereignisse können je nach Berechnungsmethode leicht variieren.")
                bulletRow("Sunnah-Fasten ist empfohlen, aber nicht verpflichtend.")
                bulletRow("Die Detailansicht eines Tages zeigt zusätzliche Ereignisse und Datumsangaben.")
                bulletRow("Lokale Sichtung und regionale Praxis können von tabellarischen Berechnungen abweichen.")
            }
        }
    }

    // MARK: - Components

    private func legendRow(_ item: CalendarLegendItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.14))
                    .frame(width: 42, height: 42)

                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func fastHint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.blue.opacity(0.85))
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(IslamicCalendarPageStyle.accentStrong.opacity(0.9))
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
