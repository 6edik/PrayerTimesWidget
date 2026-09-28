import SwiftUI

struct IslamicCalendarHadithSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [FastingHadithItem]

    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.58, blue: 0.20), Color.orange.opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    introCard

                    ForEach(items) { item in
                        hadithCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Color("AppBackground").ignoresSafeArea())
            .navigationTitle("Ahadith zum Fasten")
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
        }
    }

    private var introCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: 56, height: 56)

                Image(systemName: "book.closed")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentGradient)
            }

            VStack(spacing: 6) {
                Text("Überlieferungen zum freiwilligen Fasten")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Eine kompakte Übersicht zu empfohlenen Fasttagen und besonderen Zeiten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassCard(cornerRadius: 22)
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
