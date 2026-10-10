import SwiftUI

struct PrayerTimesHomeView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()
    private let refreshCoordinator = PrayerRefreshCoordinator()
    private let legacyMigrator = LegacyLocationMigrator()

    private static let placeholderTimes = PrayerTimes(
        fajr: "--:--",
        shuruk: "--:--",
        dhuhr: "--:--",
        asr: "--:--",
        maghrib: "--:--",
        isha: "--:--",
        readableDate: "--",
        readableDay: "--",
        hijriDate: "--",
        hijriDay: "--",
        timezone: "--",
    )

    // The canonical (never "Jum'ah"-renamed) kind for each row
    // `PrayerTimesMapper.rows(from:)` produces, in that exact fixed
    // order — used to match a row against `PrayerWindowResolver.Window
    // .currentName` (which is always "Dhuhr", literally, even on a
    // Friday) and against `expandedPrayer`, independent of whatever
    // display name (`row.name`) the row shows on screen.
    private static let canonicalRowNames = ["Fajr", "Shuruk", "Dhuhr", "Asr", "Maghrib", "Isha"]

    @State private var prayerTimes = PrayerTimesHomeView.placeholderTimes

    @State private var currentAddress = "--"
    @State private var currentMethod = "--"
    @State private var needsLocationConfirmation = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeSheet: ActiveSheet?
    @State private var hasLoadedInitially = false

    @State private var lastThirdWindow: LastThirdOfNightResolver.ResolvedWindow?
    // Same approximation the widget/notifications already use (see
    // `QiratTimeResolver`'s doc comment) — recomputed alongside
    // `lastThirdWindow` on every load/refresh, never a second API call.
    // `nil` whenever the window is suppressed (no cached data yet, or an
    // implausible latitude).
    @State private var asrKarahaWindow: QiratTimeResolver.ApproximateWindow?
    @State private var sunriseKarahaWindow: QiratTimeResolver.ApproximateWindow?

    // At most one tile's detail is ever open at once — set to one of
    // `canonicalRowNames` ("Isha", "Asr" or "Shuruk" in practice, the only
    // rows with a `detail` closure) or `nil`. A single shared state
    // instead of one `show…Detail` bool per tile, so switching from one
    // open tile straight to another is one atomic state change (see
    // `PrayerTile`) rather than two separate toggles that could
    // momentarily show neither or both.
    @State private var expandedPrayer: String?

    // Drives `currentWindow`/the orange "active prayer" highlight so it
    // keeps advancing (window end → next prayer, midnight day rollover)
    // while the page stays open, without a second network call — ticking
    // this is purely a local recomputation of already-cached data.
    @State private var now = Date()
    @State private var todayAdjusted: AdjustedPrayerTimes?
    @State private var previousDayAdjusted: AdjustedPrayerTimes?
    @State private var nextDayAdjusted: AdjustedPrayerTimes?

    enum ActiveSheet: Identifiable {
        case settings
        case statistics
        case manualQuery
        case notifications

        var id: Int {
            switch self {
            case .settings: return 1
            case .statistics: return 2
            case .manualQuery: return 3
            case .notifications: return 4
            }
        }
    }

    /// The live current/next prayer window, recomputed from already-
    /// resolved `AdjustedPrayerTimes` on every `now` tick — same
    /// `PrayerWindowResolver` the widget uses, so this page can never
    /// disagree with it about which prayer is "current" right now.
    private var currentWindow: PrayerWindowResolver.Window? {
        guard let todayAdjusted else { return nil }
        return PrayerWindowResolver.resolve(
            now: now,
            todayTimes: todayAdjusted,
            previousDayTimes: previousDayAdjusted,
            nextDayTimes: nextDayAdjusted
        )
    }

    /// The canonical name of the one row to highlight orange right now —
    /// `nil` whenever the window itself is unavailable, *and* whenever the
    /// current window is "Shuruk": sunrise is never treated as a regular
    /// obligatory prayer, so the gap between Shuruk and Dhuhr highlights
    /// nothing rather than the Shuruk tile.
    private var activePrayerCanonicalName: String? {
        guard let name = currentWindow?.currentName, name != "Shuruk" else { return nil }
        return name
    }

    var body: some View {
        NavigationStack {
            AppPageContainer {
                AppPageHeader(title: "Gebetszeiten")

                HStack(spacing: 8) {
                    // Computed locally with a German-locale formatter
                    // instead of showing `prayerTimes.readableDate` —
                    // AlAdhan's own `readable` string ("06 Oct 2026") is
                    // always English and never adapts to the app's German
                    // UI. Always "today", exactly like the Hijri text next
                    // to it, independent of whether prayer-time data has
                    // finished loading yet.
                    Text(Self.formattedGregorianDate(Date()))
                    Text("•")
                    // Computed locally via Umm-al-Qura instead of the
                    // AlAdhan API's own Hijri string, so this always agrees
                    // with the Islamic-calendar tab and the widget.
                    Text(HijriDateFormatting.displayText(for: Date()))
                }
                .font(.subheadline)

                HStack(spacing: 8) {
                    if prayerTimes.readableDay != "--" {
                        Text(Self.germanWeekday(for: prayerTimes.readableDay))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("•")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if prayerTimes.hijriDay != "--" {
                        Text(prayerTimes.hijriDay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(prayerTimes.timezone)
                    .foregroundStyle(.secondary)

                Text(currentAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if needsLocationConfirmation {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Ort erneut bestätigen", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Text(currentMethod)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Keyed by the fixed row position, never `PrayerRow.id`
                // (a fresh `UUID()` on every single `rows(from:)` call,
                // i.e. every body re-render — including the 30s clock
                // tick). With an ever-changing id, `ForEach` could never
                // tell "same row, property changed" from "row removed,
                // new row inserted", so every tile — not just the one
                // being expanded — was torn down and rebuilt on every
                // re-render, which is exactly what made the whole page
                // jump instead of animating smoothly. The row order from
                // `PrayerTimesMapper.rows(from:)` is fixed (same six
                // prayers, same sequence, every call), so the plain index
                // is a perfectly stable identity here.
                ForEach(Array(PrayerTimesMapper.rows(from: prayerTimes).enumerated()), id: \.offset) { index, row in
                    let canonicalName = Self.canonicalRowNames[index]
                    let isActive = canonicalName == activePrayerCanonicalName

                    VStack(alignment: .leading, spacing: 4) {
                        switch canonicalName {
                        case "Isha":
                            PrayerTile(
                                name: row.name,
                                time: row.time,
                                isActive: isActive,
                                isExpanded: expandedPrayer == canonicalName,
                                expandHint: "Letztes Drittel der Nacht anzeigen",
                                collapseHint: "Letztes Drittel der Nacht ausblenden",
                                onToggle: { toggleExpansion(canonicalName) }
                            ) {
                                if let lastThirdWindow {
                                    lastThirdDetail(lastThirdWindow)
                                }
                            }
                        case "Asr":
                            PrayerTile(
                                name: row.name,
                                time: row.time,
                                isActive: isActive,
                                isExpanded: expandedPrayer == canonicalName,
                                expandHint: "Karāha vor Maghrib anzeigen",
                                collapseHint: "Karāha vor Maghrib ausblenden",
                                onToggle: { toggleExpansion(canonicalName) }
                            ) {
                                if let asrKarahaWindow {
                                    karahaDetail(asrKarahaWindow)
                                }
                            }
                        case "Shuruk":
                            PrayerTile(
                                name: row.name,
                                time: row.time,
                                isActive: isActive,
                                isExpanded: expandedPrayer == canonicalName,
                                expandHint: "Karāha nach Shuruk anzeigen",
                                collapseHint: "Karāha nach Shuruk ausblenden",
                                onToggle: { toggleExpansion(canonicalName) }
                            ) {
                                if let sunriseKarahaWindow {
                                    karahaDetail(sunriseKarahaWindow)
                                }
                            }
                        default:
                            PrayerTile(name: row.name, time: row.time, isActive: isActive)
                        }

                        if row.name == "Jum'ah" {
                            Text(PrayerDisplayNaming.khutbaClarificationCaption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isLoading {
                    ProgressView()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Neu laden") {
                    Task {
                        await loadPrayerTimes(source: .manual, forceNetwork: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TopBarActionButton(systemImage: "magnifyingglass", accessibilityLabel: "Manuelle Suche") {
                        activeSheet = .manualQuery
                    }

                    TopBarActionButton(systemImage: "bell", accessibilityLabel: "Benachrichtigungen") {
                        activeSheet = .notifications
                    }

                    TopBarActionButton(systemImage: "gearshape", accessibilityLabel: "Einstellungen") {
                        activeSheet = .settings
                    }

                    TopBarActionButton(systemImage: "chart.bar", accessibilityLabel: "Statistiken") {
                        activeSheet = .statistics
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    PrayerSettingsView {
                        Task {
                            await loadPrayerTimes(source: .manual, forceNetwork: true)
                        }
                    }
                case .statistics:
                    StatisticsView()
                case .manualQuery:
                    ManualQueryView()
                case .notifications:
                    NotificationSettingsView()
                }
            }
        }
        .task {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            await legacyMigrator.migrateIfNeeded()
            await loadPrayerTimes(source: .appStart)
        }
        // Purely local: recomputes `currentWindow` (and therefore the
        // orange highlight) from the already-cached times roughly once a
        // minute, so the highlight advances to the next prayer right after
        // the current window ends, and keeps using the correct previous-/
        // next-day times across a midnight rollover — never a network call.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                now = Date()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, hasLoadedInitially {
                Task {
                    await loadPrayerTimes(source: .appActive)
                }
            }
        }
    }

    private func toggleExpansion(_ name: String) {
        // One calm, shared animation for every tile (per spec: low bounce,
        // no flicker) — and changing `expandedPrayer` straight from one
        // name to another (e.g. Isha → Shuruk) is a single state
        // transition, so the old detail's removal and the new detail's
        // insertion animate together in the same pass. There is never a
        // frame with two details open, or a frame with none, in between.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            expandedPrayer = (expandedPrayer == name) ? nil : name
        }
    }

    @MainActor
    private func loadPrayerTimes(
        source: RefreshSource,
        forceNetwork: Bool = false
    ) async {
        let autoSettings = settingsStore.loadAutoSettings()

        currentAddress = autoSettings.address
        currentMethod = autoSettings.method.title
        needsLocationConfirmation = settingsStore.needsLocationConfirmation()

        // Show whatever is cached for the *current* settings right away.
        // If there is nothing cached for them (e.g. right after switching
        // address/method, especially offline), fall back to the placeholder
        // instead of leaving the previous location's times on screen under
        // the new address label.
        applyCachedTimes(autoSettings: autoSettings)

        // Without a confirmed coordinate there is nothing to fetch — never
        // fall back to an address-based request. The banner above already
        // tells the user to re-confirm the place.
        guard autoSettings.location?.coordinate.isPlausible == true else {
            errorMessage = nil
            return
        }

        let shouldFetch = forceNetwork || refreshCoordinator.needsRefresh(settings: autoSettings)

        guard shouldFetch else {
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        let outcome = await refreshCoordinator.refreshIfNeeded(
            settings: autoSettings,
            source: source,
            forceNetwork: forceNetwork
        )

        switch outcome {
        case .success:
            applyCachedTimes(autoSettings: autoSettings)
            errorMessage = nil
            await NotificationScheduler().reschedule()
        case .failure(let message):
            applyCachedTimes(autoSettings: autoSettings)
            errorMessage = message
        case .skipped, .alreadyInProgressElsewhere:
            applyCachedTimes(autoSettings: autoSettings)
            errorMessage = nil
        }

        isLoading = false
    }

    @MainActor
    private func applyCachedTimes(autoSettings: AutoPrayerSettings) {
        if let cachedRawToday = store.load(for: Date(), settings: autoSettings) {
            prayerTimes = cachedRawToday.applyingAdjustments(autoSettings.adjustments)
            todayAdjusted = cachedRawToday.applyingAdjustmentsWithDayOffsets(autoSettings.adjustments)
        } else {
            prayerTimes = Self.placeholderTimes
            todayAdjusted = nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
           let cachedRawYesterday = store.load(for: yesterday, settings: autoSettings) {
            previousDayAdjusted = cachedRawYesterday.applyingAdjustmentsWithDayOffsets(autoSettings.adjustments)
        } else {
            previousDayAdjusted = nil
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
           let cachedRawTomorrow = store.load(for: tomorrow, settings: autoSettings) {
            nextDayAdjusted = cachedRawTomorrow.applyingAdjustmentsWithDayOffsets(autoSettings.adjustments)
        } else {
            nextDayAdjusted = nil
        }

        now = Date()
        lastThirdWindow = LastThirdOfNightResolver.window(store: store, settings: autoSettings)
        let qiratWindows = QiratTimeResolver.windows(store: store, settings: autoSettings)
        asrKarahaWindow = qiratWindows.lateMaghribKaraha
        sunriseKarahaWindow = qiratWindows.sunriseKaraha
    }

    /// AlAdhan's own Gregorian weekday name always comes back in English
    /// (e.g. "Thursday") — translated here purely for display, since the
    /// rest of the app (cache keys, notification scheduling) never reads
    /// this field for anything but display either.
    private static let germanWeekdayNames: [String: String] = [
        "Monday": "Montag",
        "Tuesday": "Dienstag",
        "Wednesday": "Mittwoch",
        "Thursday": "Donnerstag",
        "Friday": "Freitag",
        "Saturday": "Samstag",
        "Sunday": "Sonntag"
    ]

    private static func germanWeekday(for englishWeekday: String) -> String {
        germanWeekdayNames[englishWeekday] ?? englishWeekday
    }

    /// German-locale Gregorian date text (e.g. "6. Oktober 2026") — used
    /// instead of `PrayerTimes.readableDate`, which is AlAdhan's own
    /// English string and never adapts to the app's German UI.
    private static func formattedGregorianDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Formats an already-resolved absolute `Date` as a clock time in the
    /// *prayer location's* own timezone — never the device's — so it
    /// reads consistently with the location's other "HH:mm" prayer times.
    private func clockText(_ date: Date, timezoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Compact, subdued detail revealed under the Isha tile — reuses the
    /// already-resolved `lastThirdWindow` as-is (no second calculation, no
    /// extra network request); a neutral secondary tint, never the app's
    /// warning/orange color, since this isn't an alert. Shows the full
    /// start–end span (unlike `karahaDetail` below) because, unlike a
    /// Karāha window, the *start* of the last third is itself the whole
    /// point of this hint.
    private func lastThirdDetail(_ window: LastThirdOfNightResolver.ResolvedWindow) -> some View {
        HStack {
            Text("Letztes Drittel der Nacht")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(clockText(window.start, timezoneIdentifier: window.timezoneIdentifier)) – \(clockText(window.end, timezoneIdentifier: window.timezoneIdentifier))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Compact, subdued one-line Karāha hint shared by the Asr and Shuruk
    /// tiles — reuses an already-resolved `QiratTimeResolver
    /// .ApproximateWindow` as is (no second calculation, no extra API
    /// call). Deliberately just "Karāha von HH:mm bis HH:mm" — no separate
    /// per-tile title, no fiqh explanation: only the window's own start
    /// and end are the actionable information, and this never implies
    /// every prayer between them is equally affected — it is only ever
    /// this one concretely computed window.
    private func karahaDetail(_ window: QiratTimeResolver.ApproximateWindow) -> some View {
        Text("Karāha von \(clockText(window.start, timezoneIdentifier: window.timezoneIdentifier)) bis \(clockText(window.end, timezoneIdentifier: window.timezoneIdentifier))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One prayer-time card. Every row on this page (Fajr, Shuruk, Dhuhr/
/// Jum'ah, Asr, Maghrib, Isha) renders through this single reusable view
/// instead of three near-identical hand-rolled expand/collapse
/// implementations, so their background chrome, "current prayer"
/// highlight, and expand animation can never drift apart from one
/// another. Pass no `detail` closure (the default below) for a plain,
/// non-expandable row.
///
/// `matchedGeometryEffect` was deliberately not used here: with at most
/// one tile's detail ever open/closing at a time there's exactly one
/// source and one destination, which is the one case the API is actually
/// safe for — but a plain conditional `detail()` plus `.transition` and
/// `.geometryGroup()` already achieves the same smooth, non-janky result
/// without the extra namespace plumbing, so the simpler tool was kept.
private struct PrayerTile<Detail: View>: View {
    let name: String
    let time: String
    let isActive: Bool
    let isExpandable: Bool
    let isExpanded: Bool
    let expandHint: String
    let collapseHint: String
    let onToggle: () -> Void
    let detail: Detail

    init(
        name: String,
        time: String,
        isActive: Bool,
        isExpanded: Bool,
        expandHint: String,
        collapseHint: String,
        onToggle: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail
    ) {
        self.name = name
        self.time = time
        self.isActive = isActive
        self.isExpandable = true
        self.isExpanded = isExpanded
        self.expandHint = expandHint
        self.collapseHint = collapseHint
        self.onToggle = onToggle
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isExpandable {
                    Button(action: onToggle) {
                        rowLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isExpanded ? collapseHint : expandHint)
                } else {
                    rowLabel
                }
            }

            if isExpandable, isExpanded {
                detail
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        // Makes this tile's own size change (when its detail appears or
        // disappears) an atomic unit for the enclosing layout animation,
        // instead of letting the growth/shrink leak into a jarring,
        // separately-timed shift of the tiles below it.
        .geometryGroup()
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            if isActive {
                // No verified literal "mosque" SF Symbol exists as of this
                // writing; a dignified, clearly-not-decorative building
                // glyph stands in for it instead of risking an invented
                // symbol name that silently renders nothing.
                Image(systemName: "building.columns.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)
            }

            Text(name)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.orange : Color.primary)

            Spacer()

            if isExpandable {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            Text(time)
                .fontWeight(.semibold)
                .foregroundStyle(isActive ? Color.orange : Color.primary)
        }
        .contentShape(Rectangle())
    }
}

extension PrayerTile where Detail == EmptyView {
    init(name: String, time: String, isActive: Bool) {
        self.name = name
        self.time = time
        self.isActive = isActive
        self.isExpandable = false
        self.isExpanded = false
        self.expandHint = ""
        self.collapseHint = ""
        self.onToggle = {}
        self.detail = EmptyView()
    }
}
