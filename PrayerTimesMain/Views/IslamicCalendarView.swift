import SwiftUI

@MainActor
struct IslamicCalendarView: View {
    @StateObject private var viewModel = IslamicCalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selectedDayEvents: IslamicDayEvents?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 3) {
                        Text("Islamischer Kalender")
                    }
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .font(.system(size: 34, weight: .ultraLight, design: .serif))
                    .frame(height: 30)

                    VStack(spacing: 6) {
                        Text(formattedGregorian(selectedDate))
                            .font(.subheadline)

                        Text(viewModel.hijriDisplayText(for: selectedDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let count = viewModel.specialDays(for: selectedDate).count
                        if count > 0 {
                            Text(count == 1 ? "1 Ereignis an diesem Tag" : "\(count) Ereignisse an diesem Tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Kein Ereignis an diesem Tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    DatePicker(
                        "Datum",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: selectedDate) { _, newValue in
                        Task {
                            await viewModel.loadYear(for: newValue)

                            let events = viewModel.specialDays(for: newValue)
                            selectedDayEvents = events.isEmpty ? nil : IslamicDayEvents(date: newValue, events: events)
                        }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 8)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        HStack {
                            Text(viewModel.sectionTitle)
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.top, 4)

                        ForEach(viewModel.specialDays) { item in
                            Button {
                                let events = viewModel.specialDays(for: item.sortDate)
                                selectedDayEvents = events.isEmpty ? nil : IslamicDayEvents(date: item.sortDate, events: events)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
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
                                .padding()
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                        TopBarActionButton(systemImage: "calendar", accessibilityLabel: "Heute") {
                            selectedDate = Date()
                            Task {
                                await viewModel.loadYear(for: selectedDate)
                                let events = viewModel.specialDays(for: selectedDate)
                                selectedDayEvents = events.isEmpty ? nil : IslamicDayEvents(date: selectedDate, events: events)
                            }
                        }
                    TopBarActionButton(systemImage: "list.bullet",accessibilityLabel: "Liste") {
                        let events = viewModel.specialDays(for: selectedDate)
                        selectedDayEvents = events.isEmpty ? nil : IslamicDayEvents(date: selectedDate, events: events)
                    }

                    TopBarActionButton( systemImage: "arrow.clockwise", accessibilityLabel:"Aktualisieren") {
                        Task {
                            await viewModel.loadYear(for: selectedDate)
                        }
                    }
                }
            }
            .sheet(item: $selectedDayEvents) { dayEvents in
                IslamicDayEventsSheet(dayEvents: dayEvents)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                await viewModel.loadYear(for: selectedDate)
            }
        }
    }

    private func formattedGregorian(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
