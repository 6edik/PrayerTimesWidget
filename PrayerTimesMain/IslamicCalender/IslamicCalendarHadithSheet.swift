import SwiftUI

struct IslamicCalendarHadithSheet: View {
    let items: [FastingHadithItem]

    var body: some View {
        IslamicCalendarPageContainer(title: "Ahadith zum Fasten") {
            IslamicCalendarHeroCard(
                symbol: "book.closed",
                title: "Überlieferungen zum freiwilligen Fasten",
                subtitle: "Eine kompakte Übersicht zu empfohlenen Fasttagen und besonderen Zeiten."
            )

            ForEach(items) { item in
                hadithCard(item)
            }
        }
    }

    private func hadithCard(_ item: FastingHadithItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 46, height: 46)

                    Text(item.badge)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(item.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                }

                Spacer()
            }

            Text(item.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(item.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }
}
