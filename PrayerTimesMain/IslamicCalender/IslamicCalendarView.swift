import SwiftUI

@MainActor
struct IslamicCalendarView: View {
    @StateObject private var viewModel: IslamicCalendarViewModel
    @State private var selectedDate = Date()
    @State private var selectedDaySheet: IslamicDaySheetData?
    @State private var displayedMonth = Date()
    @State private var showInfoSheet = false
    @State private var showHolidayOverview = false

    init(settingsProvider: @escaping () -> AutoPrayerSettings) {
        _viewModel = StateObject(
            wrappedValue: IslamicCalendarViewModel(settingsProvider: settingsProvider)
        )
    }

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 42, maximum: .infinity), spacing: 6),
        count: 7
    )

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var displayedYear: Int {
        gregorianCalendar.component(.year, from: displayedMonth)
    }

    var body: some View {
        NavigationStack {
            AppPageContainer {
                AppPageHeader(title: "Islamischer Kalender")

                VStack(spacing: 6) {
                    Text(formattedGregorian(selectedDate))
                        .font(.subheadline)

                    Text(viewModel.hijriDisplayText(for: selectedDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let count = viewModel.allEventsForDay(selectedDate).count
                    Text(
                        count == 0
                        ? "Kein Ereignis an diesem Tag"
                        : (count == 1 ? "1 Ereignis an diesem Tag" : "\(count) Ereignisse an diesem Tag")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                calendarView
                    .padding()
                    .background(.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TopBarActionButton(systemImage: "sparkles.rectangle.stack", accessibilityLabel: "Feiertage") {
                        showHolidayOverview = true
                    }

                    TopBarActionButton(systemImage: "calendar", accessibilityLabel: "Heute") {
                        let today = Date()
                        selectedDate = today
                        displayedMonth = startOfMonth(for: today)

                        Task {
                            await viewModel.loadYear(for: today)
                            presentSheet(for: today)
                        }
                    }

                    TopBarActionButton(systemImage: "arrow.clockwise", accessibilityLabel: "Aktualisieren") {
                        Task {
                            await viewModel.reloadYear(for: selectedDate)
                            await viewModel.loadHolidayOverview(around: selectedDate)

                            if selectedDaySheet != nil {
                                presentSheet(for: selectedDate)
                            }
                        }
                    }

                    TopBarActionButton(systemImage: "info.circle", accessibilityLabel: "Hinweise") {
                        showInfoSheet = true
                    }
                }
            }
            .sheet(isPresented: $showHolidayOverview) {
                IslamicHolidayOverviewSheet(
                    viewModel: viewModel,
                    referenceDate: selectedDate
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showInfoSheet) {
                IslamicCalendarInfoSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedDaySheet) { day in
                IslamicDayEventsSheet(
                    day: day,
                    dayViewModel: viewModel.makeDaySheetViewModel(for: day.date)
                )
                .id(day.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task(id: displayedYear) {
                await viewModel.loadYear(for: displayedMonth)
            }
        }
    }

    private var calendarView: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                HStack {
                    Button {
                        moveMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text(viewModel.monthHeaderText(for: displayedMonth))
                        .font(.title2.bold())

                    Spacer()

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                }

                if let hijriSummary = viewModel.hijriMonthSummary(for: displayedMonth) {
                    Text(hijriSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 6) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(viewModel.weekdays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 20)
                    }

                    ForEach(viewModel.monthGridDays(for: displayedMonth, selectedDate: selectedDate)) { item in
                        Button {
                            selectedDate = item.date

                            if !item.isInDisplayedMonth {
                                displayedMonth = startOfMonth(for: item.date)
                            }

                            presentSheet(for: item.date)
                        } label: {
                            IslamicCalendarDayCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func formattedGregorian(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = gregorianCalendar
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        guard let interval = gregorianCalendar.dateInterval(of: .month, for: date) else {
            return date
        }
        return interval.start
    }

    private func dateInDisplayedMonth(preservingDayFrom sourceDate: Date, monthDate: Date) -> Date {
        let preferredDay = gregorianCalendar.component(.day, from: sourceDate)
        let maxDay = gregorianCalendar.range(of: .day, in: .month, for: monthDate)?.count ?? 28

        var components = gregorianCalendar.dateComponents([.year, .month], from: monthDate)
        components.day = min(preferredDay, maxDay)

        return gregorianCalendar.date(from: components) ?? monthDate
    }

    private func moveMonth(by offset: Int) {
        guard let newMonth = gregorianCalendar.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return
        }

        displayedMonth = startOfMonth(for: newMonth)
        selectedDate = dateInDisplayedMonth(
            preservingDayFrom: selectedDate,
            monthDate: displayedMonth
        )
    }

    private func presentSheet(for date: Date) {
        selectedDaySheet = IslamicDaySheetData(
            date: date,
            hijriText: viewModel.hijriDisplayText(for: date),
            events: viewModel.allEventsForDay(date)
        )
    }
}
