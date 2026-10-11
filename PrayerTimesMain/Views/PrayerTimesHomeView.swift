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
    // Karāha vor Dhuhr: the short window that separates Duha's own end
    // from Dhuhr's own start (see `QiratTimeResolver`'s doc comment) —
    // shown expandable on the Dhuhr tile, and also feeds `duhaWindow`
    // below and the "Aktueller Status" section.
    @State private var preDhuhrKarahaWindow: QiratTimeResolver.ApproximateWindow?
    // Duha never gets its own tile/row (see `CurrentPrayerStatusCalculator`
    // doc) — only feeds the "Aktueller Status" section below. Always
    // derived from `sunriseKarahaWindow.end`/`preDhuhrKarahaWindow.start`,
    // never a second Karāha computation (see `DuhaCalculator`).
    @State private var duhaWindow: DuhaCalculator.Window?

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

    /// The live "Aktueller Status" — current obligatory prayer, sunrise
    /// Karāha, Duha, or last third of the night, with precedence exactly
    /// as `CurrentPrayerStatusCalculator` defines it. Recomputed from the
    /// same already-cached/adjusted windows as `currentWindow` on every
    /// `now` tick, so it can never disagree with the tile highlight above.
    private var currentStatus: CurrentPrayerStatusCalculator.Status? {
        CurrentPrayerStatusCalculator.resolve(
            now: now,
            window: currentWindow,
            duhaWindow: duhaWindow,
            sunriseKarahaWindow: sunriseKarahaWindow,
            preDhuhrKarahaWindow: preDhuhrKarahaWindow,
            preMaghribKarahaWindow: asrKarahaWindow,
            lastThirdWindow: lastThirdWindow
        )
    }

    /// Today's Dhuhr/Jum'ah label, in the prayer location's own timezone —
    /// shared by the status card and (already, via `PrayerTimesMapper`) the
    /// Dhuhr tile itself, so the two can never disagree on a Friday.
    private var dhuhrTitle: String {
        PrayerDisplayNaming.dhuhrLabel(date: now, timezoneIdentifier: prayerTimes.timezone)
    }

    var body: some View {
        NavigationStack {
            AppPageContainer {
                AppPageHeader(title: "Gebetszeiten")

                // Gregorian/Hijri side by side with a "•" separator, above
                // the city/country line — same order and layout the
                // Islamischer Kalender page uses for its own date line.
                HStack(spacing: 8) {
                    Text(Self.formattedGregorianDate(Date()))
                    Text("•")
                    Text(HijriDateFormatting.displayText(for: Date()))
                }
                .font(.subheadline)

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

                if let currentStatus {
                    CurrentStatusCard(
                        status: currentStatus,
                        dhuhrTitle: dhuhrTitle,
                        lastThirdWindow: lastThirdWindow,
                        preMaghribKarahaWindow: asrKarahaWindow,
                        timezoneIdentifier: prayerTimes.timezone
                    )
                }

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
                                icon: PrayerStatusIcon.symbolName(forCanonicalRow: canonicalName),
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
                                icon: PrayerStatusIcon.symbolName(forCanonicalRow: canonicalName),
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
                                icon: PrayerStatusIcon.symbolName(forCanonicalRow: canonicalName),
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
                        case "Dhuhr":
                            PrayerTile(
                                name: row.name,
                                time: row.time,
                                icon: PrayerStatusIcon.symbolName(forCanonicalRow: canonicalName),
                                isActive: isActive,
                                isExpanded: expandedPrayer == canonicalName,
                                expandHint: "Karāha vor Dhuhr anzeigen",
                                collapseHint: "Karāha vor Dhuhr ausblenden",
                                onToggle: { toggleExpansion(canonicalName) }
                            ) {
                                if let preDhuhrKarahaWindow {
                                    karahaDetail(preDhuhrKarahaWindow)
                                }
                            }
                        default:
                            PrayerTile(
                                name: row.name,
                                time: row.time,
                                icon: PrayerStatusIcon.symbolName(forCanonicalRow: canonicalName),
                                isActive: isActive
                            )
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
        preDhuhrKarahaWindow = qiratWindows.preDhuhrKaraha

        if let todayAdjusted {
            duhaWindow = DuhaCalculator.resolve(
                now: now,
                todayTimes: todayAdjusted,
                sunriseKarahaWindow: sunriseKarahaWindow,
                preDhuhrKarahaWindow: preDhuhrKarahaWindow
            )
        } else {
            duhaWindow = nil
        }
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
    /// SF Symbol for this specific prayer — always supplied by the caller
    /// via the one central `PrayerStatusIcon` mapping, never computed
    /// here, so this view can't drift out of sync with the "Aktueller
    /// Status" section's own icon choice for the same prayer.
    let icon: String
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
        icon: String,
        isActive: Bool,
        isExpanded: Bool,
        expandHint: String,
        collapseHint: String,
        onToggle: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail
    ) {
        self.name = name
        self.time = time
        self.icon = icon
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
            // Always this prayer's own symbol (sunrise/sun/moon…) — no
            // Masjid/building glyph appears in this row at all anymore;
            // the orange tint plus bold text below is the only "active"
            // marker.
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? Color.orange : Color.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

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
    init(name: String, time: String, icon: String, isActive: Bool) {
        self.name = name
        self.time = time
        self.icon = icon
        self.isActive = isActive
        self.isExpandable = false
        self.isExpanded = false
        self.expandHint = ""
        self.collapseHint = ""
        self.onToggle = {}
        self.detail = EmptyView()
    }
}

/// The "Aktueller Status" section: shows whichever relevant window
/// (`CurrentPrayerStatusCalculator.Status`) is currently active — including
/// Duha and the sunrise Karāha, which deliberately get no tile of their own
/// in the list above. Styled distinctly from `PrayerTile`'s orange
/// obligatory-prayer highlight: a voluntary/transitional status never
/// borrows that chrome, so it can never read as "the current obligatory
/// prayer" (see `CurrentPrayerStatusDisplay.isObligatory`).
private struct CurrentStatusCard: View {
    let status: CurrentPrayerStatusCalculator.Status
    let dhuhrTitle: String
    /// Only used to locate the "Letztes Drittel" boundary marker on the
    /// bar when `status.kind == .isha` — reused as-is, never recomputed.
    let lastThirdWindow: LastThirdOfNightResolver.ResolvedWindow?
    /// Only used to locate the Karāha-vor-Maghrib boundary marker on the
    /// bar when `status.kind == .asr` — reused as-is, never recomputed.
    let preMaghribKarahaWindow: QiratTimeResolver.ApproximateWindow?
    /// The prayer location's own timezone — never the device's — for
    /// formatting `status.start`/`status.end`/the boundary marker as
    /// clock times.
    let timezoneIdentifier: String

    private var isObligatory: Bool {
        CurrentPrayerStatusDisplay.isObligatory(status.kind)
    }

    private var mainLabel: String {
        CurrentPrayerStatusDisplay.label(for: status.kind, dhuhrTitle: dhuhrTitle)
    }

    /// The fixed prayer/status sequence the app always walks in (…→
    /// Karāha → Duha → Karāha vor Dhuhr → Dhuhr → Asr → Karāha vor
    /// Maghrib → Maghrib → Isha → Fajr → …), so the bar's trailing-edge
    /// label never needs a second window lookup.
    private var trailingLabel: String {
        switch status.kind {
        case .fajr: return "Shuruk"
        case .sunriseKaraha: return "Duha"
        case .duha: return "Karāha"
        case .preDhuhrKaraha: return dhuhrTitle
        case .dhuhr: return "Asr"
        case .asr: return "Maghrib"
        case .preMaghribKaraha: return "Maghrib"
        case .maghrib: return "Isha"
        case .isha, .lastThirdOfNight: return "Fajr"
        }
    }

    /// Isha stays orange like every other obligatory prayer; Duha is also
    /// orange, matching the app's "current prayer" accent, even though it
    /// stays labeled "freiwillig". Every Karāha kind stays a dezent
    /// secondary (gray) tone — never orange (never "the current prayer"),
    /// and never "freiwillig" either (see `showsVoluntaryBadge`).
    ///
    /// Once an `additionalKind` sub-window actually becomes active — the
    /// last third of the night during Isha, or the Karāha vor Maghrib
    /// during Asr — the *entire* bar switches to that sub-window's own
    /// color instead of staying Isha's/Asr's normal orange. The last
    /// third switches to a light orange (still clearly in the same
    /// "Isha" orange family, just visibly lighter); the Karāha vor
    /// Maghrib switches to the exact same gray every other Karāha kind
    /// already uses (e.g. Karāha vor Dhuhr), not a separate color.
    /// There's no separate highlighted zone — the whole bar's color is
    /// the one live signal for "which sub-window am I in right now".
    private var accentColor: Color {
        switch status.additionalKind {
        case .lastThirdOfNight: return Self.lastThirdAccentColor
        case .preMaghribKaraha: return .secondary
        default: break
        }

        switch status.kind {
        case .lastThirdOfNight: return Self.lastThirdAccentColor
        case .fajr, .dhuhr, .asr, .maghrib, .isha, .duha: return .orange
        case .sunriseKaraha, .preDhuhrKaraha, .preMaghribKaraha: return .secondary
        }
    }

    /// A light orange for the last third of the night — still clearly in
    /// the same "Isha" orange family as the bar's own normal fill, just
    /// visibly lighter, so the switch is unmistakable once the last
    /// third actually begins.
    private static let lastThirdAccentColor = Color(red: 1.0, green: 0.75, blue: 0.3)

    /// Only Duha and the last third of the night may be labeled
    /// "freiwillig" — a Karāha window is a caution period, never a
    /// voluntary-prayer opportunity, and an obligatory prayer is neither.
    private var showsVoluntaryBadge: Bool {
        !isObligatory && !CurrentPrayerStatusDisplay.isKaraha(status.kind)
    }

    /// When "Letztes Drittel" (during Isha) or the Karāha vor Maghrib
    /// (during Asr) begins. Keyed off `status.kind` — not `additionalKind`
    /// — so this marker always shows where the boundary falls for the
    /// *whole* Isha/Asr window, not only once that sub-window has already
    /// started. Purely a time marker on the bar now — it no longer draws
    /// a separate filled zone; only the bar's own fill color (see
    /// `accentColor`) changes once the boundary is actually reached.
    private var markerStart: Date? {
        switch status.kind {
        case .isha: return lastThirdWindow?.start
        case .asr: return preMaghribKarahaWindow?.start
        default: return nil
        }
    }

    /// Where `markerStart` falls as a 0...1 fraction of the bar. `nil`
    /// whenever there's no boundary to show.
    private var markerFraction: Double? {
        guard let markerStart else { return nil }
        let total = status.end.timeIntervalSince(status.start)
        guard total > 0 else { return nil }
        let offset = markerStart.timeIntervalSince(status.start)
        return min(max(offset / total, 0), 1)
    }

    /// The clock time `markerStart` falls at — never shown without a
    /// matching position on the bar.
    private var markerLabel: String? {
        guard let markerStart else { return nil }
        return clockText(markerStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Always the status-specific symbol (sunrise/sun/moon…)
                // from the one central `PrayerStatusIcon` mapping — the
                // Masjid glyph is reserved for marking the active
                // obligatory prayer's row in the list below, not shown
                // here.
                Image(systemName: PrayerStatusIcon.symbolName(for: status.kind))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                Text(statusLine)
                    .font(.headline)
                    .foregroundStyle(accentColor)

                Spacer()

                if showsVoluntaryBadge {
                    Text("freiwillig")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            // Pulls the bar closer to the prayer name above — the
            // enclosing VStack's own `spacing: 10` is tuned for the
            // bar-to-label gap below; this specific gap reads better
            // tighter.
            .padding(.bottom, -4)

            StatusProgressBar(
                progress: status.progress,
                accentColor: accentColor,
                markerFraction: markerFraction,
                markerLabel: markerLabel
            )

            HStack {
                Text("\(mainLabel) \(clockText(status.start))")
                    .monospacedDigit()
                Spacer()
                Text("\(trailingLabel) \(clockText(status.end))")
                    .monospacedDigit()
            }
            .overlay {
                // Live, self-ticking countdown to the end of the current
                // status window — `Text(_:style:.timer)` updates on its
                // own (every second) without any extra app-side polling,
                // exactly like the widget's own "Noch" countdown. Kept on
                // one line ("noch xx:xx:xx"), centered between the two
                // prayer labels regardless of their own width.
                HStack(spacing: 4) {
                    Text("noch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(status.end, style: .timer)
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        // Same glass-card chrome as the `PrayerTile` rows below — plain
        // `.thinMaterial` alone (no stroke/shadow) made this card look
        // flatter/plainer than the rest of the page.
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
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
    }

    /// Formats an already-resolved absolute `Date` as a clock time in the
    /// *prayer location's* own timezone — never the device's.
    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// e.g. "Aktuell: Dhuhr", "Aktuell: Karāha", or, when the last third of
    /// the night overlaps an active Isha window, "Aktuell: Isha · Letztes
    /// Drittel".
    private var statusLine: String {
        guard let additionalKind = status.additionalKind else {
            return "Aktuell: \(mainLabel)"
        }
        let additionalLabel = CurrentPrayerStatusDisplay.label(for: additionalKind, dhuhrTitle: dhuhrTitle)
        return "Aktuell: \(mainLabel) · \(additionalLabel)"
    }
}

/// A capsule timeline bar with a glowing "you are here" marker, styled
/// after a night-sky progress indicator: a soft track, the fill itself
/// (`accentColor`, already switched by the caller to the right color for
/// whatever sub-window is actually active right now — see
/// `CurrentStatusCard.accentColor`), an optional small time tick for an
/// upcoming boundary (e.g. where "Letztes Drittel" begins), and a
/// blurred-halo thumb at the current progress fraction. Deliberately no
/// decorative sparkle/star overlay — a clean single icon
/// (`PrayerStatusIcon`) already conveys "night" where appropriate, so
/// this bar never duplicates that with separate dots, and no filled
/// highlighted sub-zone either — only the fill's own color changes once
/// a sub-window is actually active; the tick is a plain time marker, not
/// a colored zone. Purely presentational — every position is derived
/// from the already-resolved `progress`/`markerFraction`, no calculation
/// of its own.
private struct StatusProgressBar: View {
    let progress: Double
    let accentColor: Color
    /// Where an upcoming boundary (e.g. the start of "Letztes Drittel")
    /// falls as a 0...1 fraction of the bar. `nil` shows no marker at all.
    var markerFraction: Double? = nil
    /// Clock time `markerFraction` corresponds to, shown as a small tag
    /// above the tick. `nil` whenever `markerFraction` itself is `nil`.
    var markerLabel: String? = nil

    private let trackHeight: CGFloat = 10
    private let thumbDiameter: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(accentColor)
                    .frame(width: max(width * clampedProgress, trackHeight), height: trackHeight)

                if let markerFraction {
                    Rectangle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 1.5, height: trackHeight + 6)
                        .offset(x: width * markerFraction, y: 0)
                }

                if let markerFraction, let markerLabel {
                    Text(markerLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(
                            x: min(max(width * markerFraction - 14, 0), max(width - 30, 0)),
                            y: -12
                        )
                }

                thumb
                    .offset(x: width * clampedProgress - thumbDiameter / 2)
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
        // Top/bottom padding kept equal — together with the card's own
        // header-to-bar spacing override above, this makes the gap above
        // the bar (to the prayer name) exactly match the gap below it
        // (to the start/end labels). Still just enough room for the
        // thumb's blurred glow and the marker's time tag above.
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var thumb: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.4))
                .frame(width: thumbDiameter + 10, height: thumbDiameter + 10)
                .blur(radius: 4)

            Circle()
                .fill(Color.white)
                .frame(width: thumbDiameter, height: thumbDiameter)
                .shadow(color: accentColor.opacity(0.7), radius: 3)
        }
        .frame(width: thumbDiameter, height: thumbDiameter)
    }
}
