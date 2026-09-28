import SwiftUI

struct IslamicHolidayOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: IslamicCalendarViewModel
    let referenceDate: Date

    private let cardPadding = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.58, blue: 0.20), Color.orange.opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )

    private var visibleDays: [IslamicSpecialDay] {
        viewModel.visibleHolidayOverviewDays(from: referenceDate, limit: 8)
    }

    private var featuredHoliday: IslamicSpecialDay? {
        visibleDays.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    heroCard

                    if viewModel.isHolidayOverviewLoading {
                        loadingCard
                    } else if let error = viewModel.holidayOverviewErrorMessage {
                        errorCard(error)
                    } else {
                        holidaysCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color("AppBackground").ignoresSafeArea())
            .navigationTitle("Besondere Tage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .task {
                await viewModel.loadHolidayOverview(around: referenceDate)
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(accentGradient)
            
            Text("Nächstes Ereignis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentStrong)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                Text(featuredHoliday?.title ?? "Islamische Feiertage")
                    .font(.title2.weight(.ultraLight))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentStrong)
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)

                if let featuredHoliday {
                    VStack(spacing: 8) {
                            Text(viewModel.holidayGregorianText(for: featuredHoliday))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            Text(viewModel.holidayHijriText(for: featuredHoliday))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Es sind aktuell keine kommenden besonderen Tage verfügbar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .glassCard(cornerRadius: 22)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(accentStrong)

            Text("Besondere Tage werden geladen …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(cornerRadius: 22)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: "Fehler", symbol: "exclamationmark.triangle")

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var holidaysCard: some View {
        VStack(alignment: .leading, spacing: 8) {  // ← spacing: 16 → 12
            headerRow(title: "Kommende Ereignisse", symbol: "calendar")
                .font(.headline.bold())  // ← explizit bold für kompakteres Layout

            if visibleDays.isEmpty {
                Text("Keine Einträge verfügbar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 4) {  // ← spacing: 12 → 8
                    ForEach(visibleDays) { holiday in
                        holidayRow(holiday)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)  // ← 18 → 16
        .padding(.horizontal, 16)  // ← 18 → 16
        .glassCard(cornerRadius: 20)  // ← 22 → 20
    }

    private func holidayRow(_ holiday: IslamicSpecialDay) -> some View {
        let isFeatured = holiday.id == featuredHoliday?.id

        return HStack(alignment: .center, spacing: 10) {  // ← .top, 12 → .center, 10
            RoundedRectangle(cornerRadius: 10, style: .continuous)  // ← 12 → 10
                .fill(isFeatured ? AnyShapeStyle(accentGradient) : AnyShapeStyle(accentTint))
                .frame(width: 30, height: 30)  // ← 34 → 30
                .overlay {
                    Image(systemName: isFeatured ? "star.fill" : "moon.stars")
                        .font(.system(size: 12, weight: .semibold))  // ← 14 → 12
                        .foregroundStyle(isFeatured ? .white : accentStrong)
                }

            VStack(alignment: .leading, spacing: 2) {  // ← 6 → 2
                Text(holiday.title)
                    .font(.subheadline.weight(.semibold))  // ← .headline → .subheadline
                    .foregroundStyle(isFeatured ? accentStrong : .primary)
                    .lineLimit(1)

                HStack(spacing: 4) {  // ← vertikal → horizontal
                    Text(viewModel.holidayGregorianText(for: holiday))
                        .font(.caption2.weight(.medium))  // ← .subheadline → .caption2
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(1)

                    Text(viewModel.holidayHijriText(for: holiday))
                        .font(.caption2)  // ← .caption → .caption2
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isFeatured {
                Text("Nächstes")  // ← kürzer
                    .font(.caption2.bold())  // ← .caption → .caption2
                    .foregroundStyle(accentStrong)
                    .padding(.horizontal, 8)  // ← 10 → 8
                    .padding(.vertical, 6)  // ← 8 → 6
                    .glassBackground(cornerRadius: 10)  // ← 12 → 10
            }
        }
        .padding(.horizontal, 12)  // ← 14 → 12
        .padding(.vertical, 10)  // ← 14 → 10
        .glassBackground(cornerRadius: 16)  // ← 18 → 16
    }

    private func headerRow(title: String, symbol: String) -> some View {
        HStack(spacing: 8) {  // ← 10 → 8
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))  // ← 15 → 14
                .foregroundStyle(accentGradient)
                .background(accentTint, in: RoundedRectangle(cornerRadius: 10))  // ← 12 → 10
                .frame(width: 30, height: 30)  // ← 34 → 30

            Text(title)
                .font(.headline.weight(.semibold))  // ← explizit bold
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    private var accentTint: some ShapeStyle {
        Color(red: 0.78, green: 0.60, blue: 0.22).opacity(0.16)
    }

    private var accentStrong: Color {
        Color(red: 0.73, green: 0.55, blue: 0.20)
    }
}
