import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var permissionManager = NotificationPermissionManager()

    @State private var settings = NotificationSettingsStore().load()
    private let store = NotificationSettingsStore()
    // Only shown once a Zakat-Stichtag is actually set up and active on
    // "Besondere Tage" (`IslamicHolidayOverviewSheet`) — this page never
    // lets you create or edit that entry itself, only configure whether
    // to be reminded about it.
    @State private var zakatDueDate: ZakatDueDate? = ZakatDueDateStore().load()
    @State private var showInfoSheet = false

    var body: some View {
        NavigationStack {
            AppPageHeader(title: "Benachrichtigungen")
                .fontDesign(nil)

            Form {
                if !permissionManager.isAuthorized {
                    Section {
                        permissionStatusBanner
                    }
                }

                Section("Gebete") {
                    ForEach(PrayerNotificationKind.allCases) { kind in
                        Toggle(kind.displayName, isOn: bindingForPrayer(kind).isEnabled)
                        if kind == .fajr {
                            Toggle("Duha", isOn: bindingForDuha().isEnabled)
                        }
                    }
                }

                Section("Karāha") {
                    Toggle("Sonnenaufgang, vor Dhuhr & vor Maghrib (Näherung)", isOn: bindingForQirat().isEnabled)
                }

                Section("Freiwilliges Fasten") {
                    NavigationLink {
                        VoluntaryFastingNotificationDetailView(setting: bindingForVoluntaryFasting())
                    } label: {
                        HStack {
                            Text("Montag, Donnerstag & Weiße Tage")
                            Spacer()
                            Toggle("", isOn: voluntaryFastingEnabledBinding)
                                .labelsHidden()
                        }
                    }
                }

                if zakatDueDate?.isEnabled == true {
                    Section("Zakat") {
                        NavigationLink {
                            ZakatNotificationDetailView(setting: bindingForZakat())
                        } label: {
                            HStack {
                                Text("An Zakat-Stichtage erinnern")
                                Spacer()
                                Toggle("", isOn: bindingForZakat().isEnabled)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                Section("Feiertage") {
                    ForEach(MajorIslamicHoliday.allCases) { holiday in
                        NavigationLink {
                            HolidayNotificationDetailView(holiday: holiday, setting: bindingForHoliday(holiday))
                        } label: {
                            HStack {
                                Text(holiday.displayName)
                                Spacer()
                                Toggle("", isOn: bindingForHoliday(holiday).isEnabled)
                                    .labelsHidden()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Hinweise")
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                NotificationInfoSheet()
            }
            .task {
                await permissionManager.refreshStatus()
            }
            .onAppear {
                zakatDueDate = ZakatDueDateStore().load()
            }
        }
    }

    private var permissionStatusBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Benachrichtigungen sind deaktiviert", systemImage: "bell.slash.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)

            Text(
                permissionManager.authorizationStatus == .denied
                ? "Der Zugriff wurde abgelehnt. Bitte erlaube Benachrichtigungen in den Systemeinstellungen, damit PrayerTimes erinnern kann."
                : "PrayerTimes fragt erst um Erlaubnis, wenn du eine Erinnerung unten aktivierst."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if permissionManager.authorizationStatus == .denied {
                Button("Einstellungen öffnen") {
                    permissionManager.openSystemSettings()
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func bindingForPrayer(_ kind: PrayerNotificationKind) -> Binding<PrayerNotificationSetting> {
        Binding(
            get: { settings.setting(for: kind) },
            set: { newValue in
                let wasEnabled = settings.setting(for: kind).isEnabled
                settings.setSetting(newValue, for: kind)
                persistAndReschedule()

                if newValue.isEnabled, !wasEnabled {
                    Task { await requestPermissionIfNeeded() }
                }
            }
        )
    }

    // A single convenience switch for the main list row: off clears every
    // occasion, and turning it on from fully-off enables all three — there
    // is no single underlying `isEnabled` field to bind to directly, since
    // the three occasions (Montag/Donnerstag/Weiße Tage) are independent.
    // The detail view's own three toggles remain the precise way to
    // configure which occasions are actually enabled.
    private var voluntaryFastingEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.voluntaryFasting.hasAnyEnabled },
            set: { newValue in
                var updated = settings.voluntaryFasting
                updated.monday = newValue
                updated.thursday = newValue
                updated.whiteDays = newValue
                bindingForVoluntaryFasting().wrappedValue = updated
            }
        )
    }

    private func bindingForVoluntaryFasting() -> Binding<VoluntaryFastingNotificationSetting> {
        Binding(
            get: { settings.voluntaryFasting },
            set: { newValue in
                let wasEnabled = settings.voluntaryFasting.hasAnyEnabled
                settings.voluntaryFasting = newValue
                persistAndReschedule()

                if newValue.hasAnyEnabled, !wasEnabled {
                    Task { await requestPermissionIfNeeded() }
                }
            }
        )
    }

    private func bindingForHoliday(_ holiday: MajorIslamicHoliday) -> Binding<HolidayNotificationSetting> {
        Binding(
            get: { settings.setting(for: holiday) },
            set: { newValue in
                let wasEnabled = settings.setting(for: holiday).isEnabled
                settings.setSetting(newValue, for: holiday)
                persistAndReschedule()

                if newValue.isEnabled, !wasEnabled {
                    Task { await requestPermissionIfNeeded() }
                }
            }
        )
    }

    private func bindingForZakat() -> Binding<ZakatNotificationSetting> {
        Binding(
            get: { settings.zakat },
            set: { newValue in
                let wasEnabled = settings.zakat.isEnabled
                settings.zakat = newValue
                persistAndReschedule()

                if newValue.isEnabled, !wasEnabled {
                    Task { await requestPermissionIfNeeded() }
                }
            }
        )
    }

    private func bindingForQirat() -> Binding<QiratTimesNotificationSetting> {
        Binding(
            get: { settings.qirat },
            set: { newValue in
                let wasEnabled = settings.qirat.isEnabled
                settings.qirat = newValue
                persistAndReschedule()

                if newValue.isEnabled, !wasEnabled {
                    Task { await requestPermissionIfNeeded() }
                }
            }
        )
    }

    private func bindingForDuha() -> Binding<DuhaNotificationSetting> {
        Binding(
            get: { settings.duha },
            set: { newValue in
                let wasEnabled = settings.duha.isEnabled
                settings.duha = newValue
                persistAndReschedule()

                if newValue.isEnabled, !wasEnabled {
                    Task { await requestPermissionIfNeeded() }
                }
            }
        )
    }

    // Only reaches the system prompt once, on the transition to enabled —
    // never automatically on appear.
    private func requestPermissionIfNeeded() async {
        guard permissionManager.authorizationStatus == .notDetermined else {
            await permissionManager.refreshStatus()
            return
        }

        await permissionManager.requestAuthorizationIfNeeded()
        await NotificationScheduler().reschedule()
    }

    private func persistAndReschedule() {
        store.save(settings)
        Task { await NotificationScheduler().reschedule() }
    }
}

private struct VoluntaryFastingNotificationDetailView: View {
    @Binding var setting: VoluntaryFastingNotificationSetting

    var body: some View {
        Form {
            Section("Anlässe") {
                Toggle("Montage", isOn: $setting.monday)
                Toggle("Donnerstage", isOn: $setting.thursday)
                Toggle("Weiße Tage (13., 14., 15. Hijri-Tag)", isOn: $setting.whiteDays)
            }

            if setting.hasAnyEnabled {
                Section("Zeitpunkt") {
                    Stepper(value: $setting.minutesAfterMaghrib, in: 0...60, step: 5) {
                        HStack {
                            Text("Nach Maghrib am Vorabend")
                            Spacer()
                            Text("\(setting.minutesAfterMaghrib) Min.")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground").ignoresSafeArea())
        .navigationTitle("Freiwilliges Fasten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HolidayNotificationDetailView: View {
    let holiday: MajorIslamicHoliday
    @Binding var setting: HolidayNotificationSetting

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = setting.hour
                comps.minute = setting.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                setting.hour = comps.hour ?? 9
                setting.minute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            if setting.isEnabled {
                Section("Zeitpunkt") {
                    Toggle("Am Vortag erinnern", isOn: $setting.notifyDayBefore)
                    Toggle("Am Feiertag erinnern", isOn: $setting.notifyOnDay)
                }

                Section("Uhrzeit") {
                    DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                }

                if setting.isConfigurationUseless {
                    Section {
                        Text("Wähle mindestens „Am Vortag\" oder „Am Feiertag\", damit eine Erinnerung geplant wird.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground").ignoresSafeArea())
        .navigationTitle(holiday.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ZakatNotificationDetailView: View {
    @Binding var setting: ZakatNotificationSetting

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = setting.hour
                comps.minute = setting.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                setting.hour = comps.hour ?? 9
                setting.minute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            if setting.isEnabled {
                Section("Zeitpunkt") {
                    Toggle("Zusätzlich am Vortag erinnern", isOn: $setting.notifyDayBefore)
                }

                Section("Uhrzeit") {
                    DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground").ignoresSafeArea())
        .navigationTitle("Zakat-Stichtage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every explanatory "Hinweis" text from across the Benachrichtigungen page
/// and its detail screens, consolidated behind a single info button in the
/// main page's toolbar — the same button-triggered-sheet pattern as the
/// Gebetsrichtung ("Qibla") tab's `QiblaInfoSheet`, just built as a plain
/// `Form` (not the glass-card browsing layout `IslamicCalendarPageStyle`
/// documents as off-limits for Form-style pages like this one).
private struct NotificationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Allgemein") {
                    Text("Benachrichtigungen umgehen keinen Stummmodus und keinen Fokus – sie folgen den iOS-Systemeinstellungen wie jede andere App.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Gebete") {
                    Text("Die fünf täglichen Pflichtgebete – Fajr, Dhuhr, Asr, Maghrib und Isha – sind für jeden erwachsenen Muslim verpflichtend. Sie gehören zu den fünf Säulen des Islam.")
                    Text("„Der Islam ist auf fünf Säulen errichtet: dem Glaubensbekenntnis, dem Verrichten des Gebets, dem Entrichten der Zakat, der Pilgerfahrt und dem Fasten im Ramadan.“ – überliefert von Ibn ʿUmar, Sahih al-Bukhari und Sahih Muslim (Hadith-Nummern variieren je nach Druckausgabe).")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Karāha") {
                    Text("„Karāha“ bezeichnet Zeitfenster, in denen freiwillige Gebete nach überlieferter Auffassung unterlassen werden sollen: kurz nach Sonnenaufgang, um die Zeit des Sonnenhöchststands kurz vor Dhuhr, und kurz vor Sonnenuntergang. Die fünf Pflichtgebete sind davon nicht betroffen.")
                    Text("„Der Gesandte Allahs verbot uns, zu drei Zeiten zu beten oder unsere Toten zu begraben: wenn die Sonne sichtbar aufgeht, bis sie vollständig aufgestiegen ist; wenn sie ihren Höchststand erreicht, bis sie darüber hinweg ist; und wenn sie sich zum Untergang neigt, bis sie vollständig untergegangen ist.“ – überliefert von ʿUqba ibn ʿĀmir al-Juhanī, Sahih Muslim (Hadith-Nummer je nach Ausgabe unterschiedlich).")
                    Text("Erinnert zu Beginn dreier täglicher Zeitfenster: Sonnenaufgangs-Karāha ab Shuruk (ungefähr 15–20 Minuten), einer kurzen Näherung vor Dhuhr, und einer Näherung kurz vor Maghrib.")
                    Text("Die Sonnenaufgangs-Karāha beginnt exakt mit Shuruk, nie mit Fajr. Das ist eine andere Zeit als die separate hanafitische Einschränkung für freiwillige Gebete zwischen Fajr und Sonnenaufgang, die hier nicht als Benachrichtigung angeboten wird.")
                    Text("Das Fenster vor Dhuhr endet exakt mit Dhuhrs Beginn. Das Fenster vor Maghrib beginnt NICHT mit Asr – Asr bleibt bis Maghrib gültig. Alle drei Zeitfenster-Enden/-Beginne sind einstellbare Näherungswerte, keine exakten Grenzen, da keine orts- und tagesgenaue Quelle für den exakten Beginn dieser Phasen vorliegt.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Duha") {
                    Text("Duha (auch Chasht genannt) ist ein freiwilliges Gebet (Nafl), kein Pflichtgebet. Es wird im späteren Vormittag verrichtet, nachdem die Sonnenaufgangs-Karāha vorüber ist, mit mindestens zwei, üblicherweise vier Rakʿat.")
                    Text("„Jedem Gelenk eines Menschen obliegt täglich eine Almosengabe … und zwei Rakʿat, die er als Duha betet, genügen dafür.“ – überliefert von Abū Dharr, Sahih Muslim (Hadith-Nummer je nach Ausgabe unterschiedlich).")
                    Text("Erinnert einmal täglich genau zu Beginn der Duha-Zeit – also zum Ende der Sonnenaufgangs-Karāha.")
                    Text("Es wird nie während der Sonnenaufgangs-Karāha und nie nach Beginn der Karāha vor Dhuhr erinnert.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Freiwilliges Fasten") {
                    Text("Freiwilliges Fasten (Nafl) geht über die Pflicht im Ramadan hinaus. Es ist nicht verpflichtend, gilt aber als besonders empfohlen – an Montagen, Donnerstagen und den „Weißen Tagen“ (13., 14., 15. Hijri-Tag jeden Monats).")
                    Text("„Die Taten werden am Montag und am Donnerstag vorgelegt, und so möchte ich fasten, wenn meine Taten vorgelegt werden.“ – überliefert von Abū Huraira, Sunan at-Tirmidhī (Hadith-Nummer je nach Ausgabe unterschiedlich).")
                    Text("„Wenn du im Monat [freiwillig] fasten möchtest, so faste am 13., 14. und 15.“ – überliefert von Abū Dharr, Sunan at-Tirmidhī (Hadith-Nummer je nach Ausgabe unterschiedlich).")
                    Text("Die Erinnerung wird am Vorabend des Fastentags nach Maghrib geplant – für einen Montag also nach Maghrib am Sonntag, nicht am Montag selbst.")
                    Text("Während des Ramadan sowie an Eid al-Fitr, Eid al-Adha und den drei Tagen von Tashriq danach wird keine Erinnerung für freiwilliges Fasten geplant.")
                    Text("Fehlen für den Fastentag selbst gültige Fajr- oder Maghrib-Zeiten, wird die Erinnerung ohne Dauerangabe geplant statt eine Dauer zu schätzen.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Zakat-Stichtag") {
                    Text("Zakat ist die Pflichtabgabe für wohlhabende Muslime – üblicherweise 2,5 % des zakatpflichtigen Vermögens, das ein Hijri-Jahr lang über dem Nisab-Schwellenwert lag. Sie gehört ebenfalls zu den fünf Säulen des Islam.")
                    Text("„Und verrichtet das Gebet und entrichtet die Zakat …“ – Qur'an, mehrfach gemeinsam mit dem Gebet genannt, u. a. Sure 2:43.")
                    Text("Gilt für alle Kalendereinträge, die du als Zakat-Stichtag markiert hast. Ist der Schalter in der Übersicht aus, bleiben die Einträge im Kalender sichtbar, aber es wird keine Erinnerung geplant.")
                    Text("Die App berechnet oder prüft keine Zakat – sie erinnert nur an den Termin, den du selbst eingetragen hast.")
                    Text("Bei „Jährlich nach Hijri-Datum wiederholen“ fällt eine Erinnerung in einem Jahr ohne diesen Hijri-Tag (z. B. den 30. eines kürzeren Monats) für dieses eine Jahr ersatzlos aus.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Section("Feiertage") {
                    Text("Ramadan-Beginn: Start des Pflichtfastenmonats. Eid al-Fitr: Fastenbrechen-Fest zum Monatsende. Tag von Arafah/Tag der Hadsch: Höhepunkt der jährlichen Pilgerfahrt. Eid al-Adha: Opferfest. Islamisches Neujahr: Beginn des Hijri-Jahres. Ashura: 10. Muharram. Isra' und Mi'raj: die nächtliche Reise und Himmelfahrt des Propheten.")
                    Text("Erinnert wahlweise am Vortag, am Feiertag selbst, oder an beiden Tagen, jeweils zur eingestellten Uhrzeit.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground").ignoresSafeArea())
            .navigationTitle("Hinweise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

#Preview("Light") {
    NotificationSettingsView()
}

#Preview("Dark") {
    NotificationSettingsView()
        .preferredColorScheme(.dark)
}
