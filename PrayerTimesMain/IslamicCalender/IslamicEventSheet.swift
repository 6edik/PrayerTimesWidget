import SwiftUI

struct IslamicDayEventsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: IslamicDaySheetData
    @StateObject private var dayViewModel: IslamicDaySheetViewModel
    @ObservedObject var personalCalendarViewModel: PersonalCalendarViewModel

    @State private var showAddEntrySheet = false
    @State private var entryToEdit: PersonalCalendarEntry?
    @State private var entryPendingDeletion: PersonalCalendarEntry?
    @State private var zakatDueDate: ZakatDueDate? = ZakatDueDateStore().load()

    private var zakatMatchesToday: Bool {
        guard let zakatDueDate, zakatDueDate.isEnabled else { return false }
        return ZakatOccurrenceCalculator.matches(
            hijriDay: zakatDueDate.hijriDay,
            hijriMonth: zakatDueDate.hijriMonth,
            date: day.date
        )
    }

    init(
        day: IslamicDaySheetData,
        dayViewModel: @autoclosure @escaping () -> IslamicDaySheetViewModel,
        personalCalendarViewModel: PersonalCalendarViewModel
    ) {
        self.day = day
        _dayViewModel = StateObject(wrappedValue: dayViewModel())
        self.personalCalendarViewModel = personalCalendarViewModel
    }

    private var personalEntries: [PersonalCalendarEntry] {
        personalCalendarViewModel.entries(for: day.date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    eventsSection
                    prayerTimesSection
                    personalEntriesSection
                }
                .padding()
            }
            .background(Color("AppBackground").ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IslamicCalendarCloseButton { dismiss() }
                }
            }
        }
        .task {
            dayViewModel.load()
        }
        .onDisappear {
            // Discards a still-in-flight single-day request (if any) so a
            // late result can never land back into this closed sheet.
            dayViewModel.cancel()
        }
        .sheet(isPresented: $showAddEntrySheet) {
            PersonalCalendarEntryFormView(viewModel: personalCalendarViewModel, mode: .create(date: day.date))
        }
        .sheet(item: $entryToEdit) { entry in
            PersonalCalendarEntryFormView(viewModel: personalCalendarViewModel, mode: .edit(entry))
        }
        .alert(
            "Notiz löschen?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { entryPendingDeletion = nil }
                }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button("Löschen", role: .destructive) {
                personalCalendarViewModel.delete(entry)
                entryPendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { _ in
            Text("Diese Notiz wird dauerhaft gelöscht.")
        }
    }

    private var personalEntriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meine Notizen")
                .font(.headline)

            if personalEntries.isEmpty {
                Text("Keine Notizen an diesem Tag")
                    .foregroundStyle(.secondary)
            } else {
                // Not inside a `List`, so `.swipeActions` has no effect here
                // — an explicit, always-visible delete button next to each
                // row instead, sized well above the 44pt touch-target
                // minimum.
                ForEach(personalEntries) { entry in
                    HStack(spacing: 8) {
                        Button {
                            entryToEdit = entry
                        } label: {
                            PersonalCalendarEntryRow(entry: entry, showsDate: false, isCompact: true)
                        }
                        .buttonStyle(.plain)

                        Button {
                            entryPendingDeletion = entry
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Notiz löschen")
                    }
                }
            }

            Button {
                showAddEntrySheet = true
            } label: {
                Label("Notiz hinzufügen", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Notiz für diesen Tag hinzufügen")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedGregorian(day.date))
                .font(.headline)

            Text(day.hijriText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var prayerTimesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gebetszeiten")
                    .font(.headline)
                Spacer()
                sourceBadge
            }

            switch dayViewModel.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Lade Gebetszeiten …")
                        .foregroundStyle(.secondary)
                }

            case .loaded(let raw, let adjusted, _):
                VStack(spacing: 8) {
                    prayerRow("Fajr", adjusted.fajr)
                    prayerRow("Shuruq", adjusted.shuruk)
                    prayerRow(
                        PrayerDisplayNaming.dhuhrLabel(date: dayViewModel.date, timezoneIdentifier: raw.timezone),
                        adjusted.dhuhr
                    )
                    prayerRow("Asr", adjusted.asr)
                    prayerRow("Maghrib", adjusted.maghrib)
                    prayerRow("Isha", adjusted.isha)
                }

                if PrayerDisplayNaming.isJumuahDhuhr(date: dayViewModel.date, timezoneIdentifier: raw.timezone) {
                    Text(PrayerDisplayNaming.khutbaClarificationCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if adjusted != raw {
                    Label("Persönliche Justierung angewendet", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                fastingDurationSection

            case .offline:
                Label(
                    "Keine Internetverbindung. Für diesen Tag ist kein passender Cache-Eintrag vorhanden.",
                    systemImage: "wifi.slash"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Marks, next to the "Gebetszeiten" heading, whether the shown times
    /// came from the existing Auto-Cache or from a temporary single-day
    /// fetch — never persisted, so it's worth being explicit about it.
    @ViewBuilder
    private var sourceBadge: some View {
        if case .loaded(_, _, let source) = dayViewModel.state {
            switch source {
            case .cached:
                Label("Aus Cache", systemImage: "internaldrive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .fetched:
                Label("Einzelabfrage", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // Hidden entirely (no "Ereignisse" title, no empty-state text) when
    // this day has no relevant event — `day.events` already only ever
    // contains AlAdhan entries that survived `IslamicHolidayClassifier
    // .filterRelevant` (excluded titles like "Urs of …"/"Birth of …" never
    // reach here), so an empty list here always means "no relevant event",
    // never "events exist but were filtered for display only". The user's
    // own Zakat-due-date (`zakatMatchesToday`, from the separate
    // `ZakatDueDateStore` — never an AlAdhan entry) counts as relevant too
    // and can make this block visible even when `day.events` is empty.
    @ViewBuilder
    private var eventsSection: some View {
        if !day.events.isEmpty || zakatMatchesToday {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ereignisse")
                    .font(.headline)

                if zakatMatchesToday, let zakatDueDate {
                    zakatEventCard(zakatDueDate)
                }

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

    /// Visually distinct from the plain AlAdhan event cards above/below it
    /// — its own colored icon badge (green, never the gold/orange
    /// used for curated holidays elsewhere) so it reads as its own
    /// category at a glance, not just another AlAdhan entry.
    private func zakatEventCard(_ zakatDueDate: ZakatDueDate) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.9), Color.green.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "banknote")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Zakat-Stichtag")
                    .font(.headline)

                Text("Jedes Hijri-Jahr am \(zakatDueDate.hijriDay). \(HijriDateFormatting.monthName(zakatDueDate.hijriMonth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Voluntary-fasting estimate for this day, computed centrally by
    /// `FastingDurationCalculator` (adjusted Maghrib minus adjusted Fajr, as
    /// full `Date`s in the location's own timezone) — the same calculation
    /// `NotificationScheduler` uses for existing fasting reminders. Omitted
    /// entirely when this day has no valid Fajr/Maghrib to compute it from,
    /// never a guessed or partial duration.
    @ViewBuilder
    private var fastingDurationSection: some View {
        if let fasting = dayViewModel.fastingDuration {
            Divider()

            HStack {
                Label("Voraussichtliche Fastendauer", systemImage: "moon.stars")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(FastingDurationCalculator.formattedDuration(fasting.duration))
                    .fontWeight(.semibold)
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

private func previewDay() -> IslamicDaySheetData {
    IslamicDaySheetData(
        date: Date(),
        hijriText: "17. Rabi' II 1448",
        events: []
    )
}

private func previewDayViewModel() -> IslamicDaySheetViewModel {
    IslamicDaySheetViewModel(
        date: Date(),
        prayerStore: SharedPrayerTimesStore(),
        settingsProvider: { AutoPrayerSettings() }
    )
}

#Preview("Light") {
    IslamicDayEventsSheet(
        day: previewDay(),
        dayViewModel: previewDayViewModel(),
        personalCalendarViewModel: PersonalCalendarViewModel()
    )
}

#Preview("Dark") {
    IslamicDayEventsSheet(
        day: previewDay(),
        dayViewModel: previewDayViewModel(),
        personalCalendarViewModel: PersonalCalendarViewModel()
    )
    .preferredColorScheme(.dark)
}
