import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var permissionManager = NotificationPermissionManager()

    @State private var settings = NotificationSettingsStore().load()
    private let store = NotificationSettingsStore()

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
                        NavigationLink {
                            PrayerNotificationDetailView(kind: kind, setting: bindingForPrayer(kind))
                        } label: {
                            HStack {
                                Text(kind.displayName)
                                Spacer()
                                Text(summaryText(for: settings.setting(for: kind)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Freiwilliges Fasten") {
                    NavigationLink {
                        VoluntaryFastingNotificationDetailView(setting: bindingForVoluntaryFasting())
                    } label: {
                        HStack {
                            Text("Montag, Donnerstag & Weiße Tage")
                            Spacer()
                            Text(summaryText(for: settings.voluntaryFasting))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                                Text(summaryText(for: settings.setting(for: holiday)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Hinweis") {
                    Text("Benachrichtigungen umgehen keinen Stummmodus und keinen Fokus – sie folgen den iOS-Systemeinstellungen wie jede andere App.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task {
                await permissionManager.refreshStatus()
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

    private func summaryText(for setting: PrayerNotificationSetting) -> String {
        guard setting.isEnabled else { return "Aus" }
        return setting.reminderLeadTime == .none ? "An" : "An · \(setting.reminderLeadTime.rawValue) Min. vorher"
    }

    private func summaryText(for setting: VoluntaryFastingNotificationSetting) -> String {
        guard setting.hasAnyEnabled else { return "Aus" }

        var parts: [String] = []
        if setting.monday { parts.append("Mo") }
        if setting.thursday { parts.append("Do") }
        if setting.whiteDays { parts.append("Weiße Tage") }
        return parts.joined(separator: " · ")
    }

    private func summaryText(for setting: HolidayNotificationSetting) -> String {
        guard setting.isEnabled, !setting.isConfigurationUseless else { return "Aus" }

        var parts: [String] = []
        if setting.notifyDayBefore { parts.append("Vortag") }
        if setting.notifyOnDay { parts.append("Am Tag") }
        return parts.joined(separator: " & ")
    }
}

private struct PrayerNotificationDetailView: View {
    let kind: PrayerNotificationKind
    @Binding var setting: PrayerNotificationSetting

    var body: some View {
        Form {
            Section {
                Toggle("Benachrichtigung für \(kind.displayName)", isOn: $setting.isEnabled)
            }

            if setting.isEnabled {
                Section("Zusätzliche Erinnerung") {
                    Picker("Erinnerung", selection: $setting.reminderLeadTime) {
                        ForEach(ReminderLeadTime.allCases) { lead in
                            Text(lead.title).tag(lead)
                        }
                    }
                }

                Section("Ton") {
                    Picker("Ton", selection: $setting.sound) {
                        ForEach(NotificationSoundOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
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

                Section("Ton") {
                    Picker("Ton", selection: $setting.sound) {
                        ForEach(NotificationSoundOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Hinweis") {
                Text("Die Erinnerung wird am Vorabend des Fastentags nach Maghrib geplant – für einen Montag also nach Maghrib am Sonntag, nicht am Montag selbst.")
                Text("Während des Ramadan sowie an Eid al-Fitr, Eid al-Adha und den drei Tagen von Tashriq danach wird keine Erinnerung für freiwilliges Fasten geplant.")
                Text("Fehlen für den Fastentag selbst gültige Fajr- oder Maghrib-Zeiten, wird die Erinnerung ohne Dauerangabe geplant statt eine Dauer zu schätzen.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
            Section {
                Toggle("Benachrichtigung für \(holiday.displayName)", isOn: $setting.isEnabled)
            }

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
        .navigationTitle(holiday.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
