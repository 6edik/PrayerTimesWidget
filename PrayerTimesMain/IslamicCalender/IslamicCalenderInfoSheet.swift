import SwiftUI

// MARK: - Main Info Sheet

struct IslamicCalendarInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showHadithSheet = false

    private let cardPadding = EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18)
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.58, blue: 0.20), Color.orange.opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    heroCard
                    colorLegendCard
                    sunnahFastingCard
                    notesCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .navigationTitle("Kalender-Hinweise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        ZStack {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
                }
            }
            .sheet(isPresented: $showHadithSheet) {
                IslamicCalendarHadithSheet(items: IslamicCalendarInfoData.hadithItems)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentStrong.opacity(0.10))
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(.white.opacity(0.75))
                    .frame(width: 44, height: 44)

                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentGradient)
            }

            VStack(spacing: 8) {
                Text("Islamischer Kalender")
                    .font(.largeTitle.weight(.ultraLight))
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)

                Text("Farben, Markierungen und Sunnah-Fastentage auf einen Blick.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(cardPadding)
        .glassCard(cornerRadius: 24)
    }

    private var colorLegendCard: some View {
        infoCard(title: "Farb-Legende", symbol: "paintpalette") {
            VStack(spacing: 14) {
                ForEach(IslamicCalendarInfoData.legendItems) { item in
                    legendRow(item)
                }
            }
        }
    }

    private var sunnahFastingCard: some View {
        infoCard(title: "Sunnah-Fasten", symbol: "moon.stars") {
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

                Button {
                    showHadithSheet = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(accentStrong.opacity(0.12))
                                .frame(width: 32, height: 32)

                            Image(systemName: "book.closed")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(accentGradient)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ahadith anzeigen")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("Mit Quellen zu Sunnah-Fasten")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassBackground(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesCard: some View {
        infoCard(title: "Hinweise", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                bulletRow("Kalenderdaten und Ereignisse können je nach Berechnungsmethode leicht variieren.")
                bulletRow("Sunnah-Fasten ist empfohlen, aber nicht verpflichtend.")
                bulletRow("Die Detailansicht eines Tages zeigt zusätzliche Ereignisse und Datumsangaben.")
                bulletRow("Lokale Sichtung und regionale Praxis können von tabellarischen Berechnungen abweichen.")
            }
        }
    }

    // MARK: - Components

    private func infoCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(title: title, symbol: symbol)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private func cardHeader(title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentStrong.opacity(0.12))
                    .frame(width: 34, height: 34)

                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 24, height: 24)

                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentGradient)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

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
                .fill(accentStrong.opacity(0.9))
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var accentStrong: Color {
        Color(red: 0.73, green: 0.55, blue: 0.20)
    }
}
