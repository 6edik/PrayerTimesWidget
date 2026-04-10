import SwiftUI

struct IslamicYearEventsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: IslamicCalendarViewModel
    let yearDate: Date
    let onSelect: (IslamicSpecialDay) -> Void

    private let cardPadding = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.58, blue: 0.20), Color.orange.opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )

    private var items: [IslamicSpecialDay] {
        viewModel.yearEvents(for: yearDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    heroCard

                    if items.isEmpty {
                        emptyCard
                    } else {
                        eventsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Ereignisse \(viewModel.yearTitle(for: yearDate))")
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
        }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle.portrait.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accentGradient)

            VStack(spacing: 8) {
                Text("Jahresereignisse")
                    .font(.largeTitle.weight(.ultraLight))
                    .fontDesign(.serif)

                Text("Alle besonderen Ereignisse des Jahres \(viewModel.yearTitle(for: yearDate)) auf einen Blick.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("\(items.count) Einträge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentStrong)
                    .textCase(.uppercase)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(cardPadding)
        .glassCard(cornerRadius: 24)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow(title: "Keine Ereignisse", symbol: "calendar.badge.exclamationmark")

            Text("Für dieses Jahr sind noch keine besonderen Ereignisse vorhanden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow(title: "Alle Einträge", symbol: "calendar")

            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accentTint)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Image(systemName: "moonphase.waxing.crescent")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(accentStrong)
                                }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(item.gregorianReadable)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("\(item.hijriDay). \(item.hijriMonth) \(item.hijriYear)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .glassBackground(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private func headerRow(title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentGradient)
                .background(accentTint, in: RoundedRectangle(cornerRadius: 12))
                .frame(width: 34, height: 34)

            Text(title)
                .font(.headline)
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
