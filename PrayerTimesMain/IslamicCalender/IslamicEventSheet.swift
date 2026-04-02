import SwiftUI

struct IslamicDayEventsSheet: View {
    let dayEvents: IslamicDayEvents

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("Ereignisse")
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .font(.system(size: 30, weight: .ultraLight, design: .serif))

                    Text(formattedDate(dayEvents.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(dayEvents.events) { event in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(event.title)
                            .font(.headline)

                        Text("\(event.hijriDay). \(event.hijriMonth) \(event.hijriYear)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(IslamicEventInfoProvider.description(for: event.title))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}
