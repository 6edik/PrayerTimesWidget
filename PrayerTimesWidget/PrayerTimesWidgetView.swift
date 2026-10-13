import SwiftUI
import WidgetKit

struct PrayerTimesWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    private let accent = Color.orange
    private let store = SharedPrayerTimesStore()
    private let settingsStore = SharedPrayerSettingsStore()

    /// Same light-orange value `CurrentStatusCard` uses on the
    /// Gebetszeiten page for the last third of the night — visibly
    /// lighter than, but still clearly part of, the normal orange accent.
    private static let lastThirdAccentColor = Color(red: 1.0, green: 0.75, blue: 0.3)

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                homeSmallView
            case .systemMedium:
                homeMediumView
            case .accessoryInline:
                lockInlineView
            case .accessoryCircular:
                lockCircularView
            case .accessoryRectangular:
                lockRectangularView
            default:
                homeSmallView
            }
        }
        .widgetBackground()
    }

    private var homeSmallView: some View {
        let window = resolvedWindow()
        let highlights = todaysHighlightState(window: window)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(smallGregorianHeader())
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(smallHijriHeader())
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)

            Divider()
                .overlay(Color.primary.opacity(0.10))
                .padding(.top, 8)
                .padding(.bottom, 10)

            VStack(spacing: 4) {
                smallPrayerRow(
                    icon: PrayerStatusIcon.symbolName(forCanonicalRow: "Fajr"),
                    title: "Fajr",
                    time: entry.times.fajr,
                    isActive: highlights.primary == "Fajr"
                )

                smallPrayerRow(
                    icon: PrayerStatusIcon.symbolName(forCanonicalRow: "Shuruk"),
                    title: "Shuruk",
                    time: entry.times.shuruk,
                    isActive: highlights.primary == "Shuruk"
                )

                smallPrayerRow(
                    icon: PrayerStatusIcon.symbolName(forCanonicalRow: "Dhuhr"),
                    title: dhuhrTitle,
                    time: entry.times.dhuhr,
                    isActive: highlights.primary == "Dhuhr"
                )

                smallPrayerRow(
                    icon: PrayerStatusIcon.symbolName(forCanonicalRow: "Asr"),
                    title: "Asr",
                    time: entry.times.asr,
                    isActive: highlights.primary == "Asr"
                )

                smallPrayerRow(
                    icon: PrayerStatusIcon.symbolName(forCanonicalRow: "Maghrib"),
                    title: "Maghrib",
                    time: entry.times.maghrib,
                    isActive: highlights.primary == "Maghrib"
                )

                smallPrayerRow(
                    icon: PrayerStatusIcon.symbolName(forCanonicalRow: "Isha"),
                    title: "Isha",
                    time: entry.times.isha,
                    isActive: highlights.primary == "Isha"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallPrayerRow(
        icon: String,
        title: String,
        time: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 16, alignment: .leading)
                .foregroundStyle(isActive ? .primary : Color.primary.opacity(0.72))

            // No `Spacer()` here anymore — it was eating into the title's
            // own width, which is exactly what caused "Maghrib" (the
            // longest prayer name) to truncate to "Magh…" once it became
            // bold (the active row). The title already starts right
            // after the icon via its own leading-aligned flexible frame.
            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isActive ? .primary : Color.primary.opacity(0.72))

            Text(time)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .serif))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(isActive ? .primary : Color.primary.opacity(0.72))
        }
    }

    private func smallGregorianHeader() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: entry.date).uppercased()
    }

    private func smallHijriHeader() -> String {
        // Computed locally via Umm-al-Qura instead of the AlAdhan API's own
        // Hijri string, so this always agrees with the Islamic-calendar tab
        // and the home screen.
        let (hijriDayNumber, monthNumber) = HijriDateFormatting.dayAndMonth(for: entry.date)
        let day = String(hijriDayNumber)
        let month: String

        switch monthNumber {
        case 1:  month = "MUH"
        case 2:  month = "SFR"
        case 3:  month = "R-AW"
        case 4:  month = "R-TH"
        case 5:  month = "J-AW"
        case 6:  month = "J-TH"
        case 7:  month = "RAJB"
        case 8:  month = "SHBN"
        case 9:  month = "RMD"
        case 10: month = "SHWL"
        case 11: month = "DHQD"
        case 12: month = "DHHJ"
        default: month = "?"
        }

        return "\(day). \(month)"
    }

    private var homeMediumView: some View {
        let window = resolvedWindow()

        return HStack(spacing: 14) {
            if let window {
                let highlights = todaysHighlightState(window: window)
                // `status` refines the generic Shuruk-to-Dhuhr window into
                // "Karāha" or "Duha" (never shown as a plain, label-less
                // "Shuruk" span) using the exact same
                // `CurrentPrayerStatusCalculator` the Gebetszeiten page
                // uses — falls back to the raw obligatory-prayer window
                // whenever the refined status can't be resolved (e.g. the
                // sunrise-Karāha approximation is suppressed), never a
                // blank display.
                let status = currentStatus(window: window)
                let isObligatory = status.map { CurrentPrayerStatusDisplay.isObligatory($0.kind) } ?? true
                let isKaraha = status.map { CurrentPrayerStatusDisplay.isKaraha($0.kind) } ?? false
                // True whether the last third is the standalone main
                // status or riding along with Isha as `additionalKind` —
                // either way, the progress bar should turn light orange.
                let isLastThirdActive = status?.kind == .lastThirdOfNight || status?.additionalKind == .lastThirdOfNight
                let displayStart = status?.start ?? window.start
                let displayEnd = status?.end ?? window.end
                let mainLabel = status.map { CurrentPrayerStatusDisplay.label(for: $0.kind, dhuhrTitle: dhuhrTitle) } ?? displayName(for: window.currentName)
                let combinedLabel: String = {
                    guard let additionalKind = status?.additionalKind else { return mainLabel }
                    return "\(mainLabel) · \(CurrentPrayerStatusDisplay.label(for: additionalKind, dhuhrTitle: dhuhrTitle))"
                }()
                // After the sunrise Karāha, the next relevant state is
                // Duha. After Duha itself, the next *countdown target* is
                // deliberately the actual next obligatory prayer — never
                // the Karāha vor Dhuhr in between, since a caution period
                // is not something to count down "bis" (the Karāha vor
                // Dhuhr still gets shown as the main status in its own
                // right once it becomes active; it's only skipped here as
                // Duha's destination). Every other state's "next" stays
                // the actual next obligatory prayer, exactly as before.
                let nextLabel: String = {
                    switch status?.kind {
                    case .sunriseKaraha: return "Duha"
                    default: return displayName(for: window.nextName)
                    }
                }()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        Text(smallGregorianHeader())
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .kerning(0.4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(smallHijriHeader())
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .kerning(0.4)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .foregroundStyle(Color.orange.opacity(0.65))
                    .lineLimit(1)

                    VStack(alignment: .leading, spacing: 2) {
                        // The literal "Aktuell" label is gone — Duha is
                        // never worded as if it were an obligatory prayer;
                        // only a subdued "Freiwillig" marker takes its
                        // place. A Karāha window gets neither this label
                        // (it isn't a voluntary-prayer opportunity) nor the
                        // orange "current prayer" accent.
                        if !isObligatory && !isKaraha {
                            Text("Freiwillig")
                                .font(.system(size: 10, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.orange.opacity(0.85))
                        }

                        // Label stacked above the time instead of sharing
                        // a row with it: next to the bold 18pt time, the
                        // longer combined labels (e.g. "Isha · Letztes
                        // Drittel der Nacht") had no room and truncated to
                        // a few characters. Full width now goes to the
                        // label on its own line.
                        Text(combinedLabel)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.primary)

                        Text(clockText(displayStart, timezoneIdentifier: window.timezoneIdentifier))
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        let markerFractions = progressMarkerFractions(status: status, displayStart: displayStart, displayEnd: displayEnd)

                        // Countdown and destination always stay side by
                        // side ("3:14:36 bis Maghrib") — the destination
                        // never drops to a line of its own below the
                        // timer. The timer keeps layout priority so it's
                        // never the one that shrinks; the destination
                        // label scales down instead of wrapping or
                        // clipping when the combination is tight.
                        HStack(spacing: 5) {
                            Text(displayEnd, style: .timer)
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .monospacedDigit()
                                .foregroundStyle(Color.orange.opacity(0.95))
                                .layoutPriority(1)

                            Text("bis \(nextLabel)")
                                .font(.system(size: 11, weight: .medium, design: .serif))
                                .foregroundStyle(Color.primary.opacity(0.68))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }

                        // A real time-driven control instead of a
                        // `GeometryReader`/`Capsule` whose width is only
                        // ever recomputed when WidgetKit swaps in a new
                        // timeline entry: `ProgressView(timerInterval:)` is
                        // one of the few WidgetKit-supported views (like
                        // `Text(_, style: .timer)` above) that the system
                        // itself keeps animating between entries, so the
                        // bar actually advances continuously through the
                        // whole window — not just during whichever single
                        // window happened to be active the moment the
                        // timeline was last built. Uses the same refined
                        // `displayStart...displayEnd` span as the countdown
                        // above (Karāha/Duha's own bounds when active),
                        // never the raw Shuruk-to-Dhuhr span.
                        //
                        // The boundary ticks overlaid on top (e.g. where
                        // "Letztes Drittel" begins) mirror the Gebetszeiten
                        // page's own bar markers, just without a clock-time
                        // label — only the tick itself, kept to the plain
                        // positions a `GeometryReader` can compute once
                        // (static marks, unlike the live-animating fill
                        // above) without needing periodic timeline entries.
                        ZStack(alignment: .leading) {
                            ProgressView(timerInterval: displayStart...displayEnd, countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(isLastThirdActive ? Self.lastThirdAccentColor : accent)

                            GeometryReader { proxy in
                                ForEach(markerFractions.indices, id: \.self) { index in
                                    // `.position` centers the tick on the
                                    // bar's own vertical midline, so the
                                    // overhang above and below is always
                                    // identical by construction — never a
                                    // hand-tuned offset that only happens
                                    // to look centered at one specific bar
                                    // height.
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.35))
                                        .frame(width: 1.2, height: 10)
                                        .position(x: proxy.size.width * markerFractions[index], y: proxy.size.height / 2)
                                }
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text(mainLabel)
                            Spacer()
                            Text(nextLabel)
                        }
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundStyle(Color.primary.opacity(0.48))
                    }

                    // The last third of the night no longer gets its own
                    // "Letztes Drittel xx:xx–xx:xx" text line — the
                    // progress bar above already turns light orange
                    // (`isLastThirdActive`) the moment it's active, so a
                    // separate always-on line became redundant.
                    VStack(alignment: .leading, spacing: 3) {
                        // Any active Karāha window is already shown as the
                        // main status above (`combinedLabel`, with its own
                        // "vor Dhuhr"/"vor Maghrib"/"nach Shuruk"
                        // qualifier) — either as `status.kind` itself (the
                        // Karāha vor Dhuhr as the main status) or riding
                        // along as `additionalKind` (e.g. "Asr · Karāha"
                        // once the Karāha vor Maghrib starts) — never the
                        // exact same information twice down here.
                        let isKarahaStatus = status.map { CurrentPrayerStatusDisplay.isKaraha($0.kind) } ?? false
                        let additionalIsKaraha = status?.additionalKind.map { CurrentPrayerStatusDisplay.isKaraha($0) } ?? false
                        if let qiratLabel = activeQiratLabel(), !isKarahaStatus, !additionalIsKaraha {
                            Text(qiratLabel)
                                .font(.system(size: 9, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.orange.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

                VStack(spacing: 7) {
                    mediumPrayerRow(
                        title: "Fajr",
                        time: entry.times.fajr,
                        isCurrent: highlights.current == "Fajr",
                        isNext: highlights.next == "Fajr"
                    )

                    mediumPrayerRow(
                        title: "Shuruk",
                        time: entry.times.shuruk,
                        isCurrent: highlights.current == "Shuruk",
                        isNext: highlights.next == "Shuruk"
                    )

                    mediumPrayerRow(
                        title: dhuhrTitle,
                        time: entry.times.dhuhr,
                        isCurrent: highlights.current == "Dhuhr",
                        isNext: highlights.next == "Dhuhr"
                    )

                    mediumPrayerRow(
                        title: "Asr",
                        time: entry.times.asr,
                        isCurrent: highlights.current == "Asr",
                        isNext: highlights.next == "Asr"
                    )

                    mediumPrayerRow(
                        title: "Maghrib",
                        time: entry.times.maghrib,
                        isCurrent: highlights.current == "Maghrib",
                        isNext: highlights.next == "Maghrib"
                    )

                    mediumPrayerRow(
                        title: "Isha",
                        time: entry.times.isha,
                        isCurrent: highlights.current == "Isha",
                        isNext: highlights.next == "Isha"
                    )
                }
                .frame(width: 120, alignment: .leading)
            } else {
                noDataView
            }
        }
        .padding()
    }

    private func mediumPrayerRow(
        title: String,
        time: String,
        isCurrent: Bool,
        isNext: Bool
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .serif))
                .foregroundStyle(
                    isCurrent ? .primary : (isNext ? Color.orange.opacity(0.92) : Color.primary.opacity(0.62))
                )

            Spacer(minLength: 6)

            Text(time)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .serif))
                .monospacedDigit()
                .foregroundStyle(
                    isCurrent ? .primary : (isNext ? Color.orange.opacity(0.92) : Color.primary.opacity(0.62))
                )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Color.primary.opacity(0.09) : (isNext ? Color.orange.opacity(0.12) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCurrent ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }

    /// Shown instead of a fabricated window whenever `PrayerWindowResolver`
    /// can't resolve one (missing/unusable cached data for today) — an
    /// honest empty state rather than a progress bar that looks valid but
    /// is silently frozen at 0%.
    private var noDataView: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 22))
                .foregroundStyle(Color.primary.opacity(0.55))

            Text("Keine Gebetszeiten verfügbar")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color.primary.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lockInlineView: some View {
        guard let window = resolvedWindow() else {
            return AnyView(
                Text("Keine Daten")
                    .font(.system(.caption2, design: .serif))
            )
        }

        return AnyView(
            ViewThatFits(in: .horizontal) {
                inlineCountdownText(
                    symbol: PrayerStatusIcon.symbolName(forCanonicalRow: window.currentName),
                    current: shortLabel(window.currentName),
                    end: window.end,
                    next: shortLabel(window.nextName)
                )

                inlineCompactCountdownText(
                    symbol: PrayerStatusIcon.symbolName(forCanonicalRow: window.currentName),
                    current: shortLabel(window.currentName),
                    end: window.end
                )

                Text("\(shortLabel(window.currentName)) \(window.currentTime)")
                    .font(.system(.caption2, design: .serif))
                    .monospacedDigit()
            }
        )
    }

    private func inlineCountdownText(
        symbol: String,
        current: String,
        end: Date,
        next: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))

            Text(current)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.semibold)

            Text("·")

            Text(end, style: .timer)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.bold)
                .monospacedDigit()

            Text("→ \(next)")
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(.secondary)
        }
    }

    private func inlineCompactCountdownText(
        symbol: String,
        current: String,
        end: Date
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))

            Text(current)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.semibold)

            Text(end, style: .timer)
                .font(.system(.caption2, design: .serif))
                .fontWeight(.bold)
                .monospacedDigit()
        }
    }

    private var lockCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let window = resolvedWindow() {
                VStack(spacing: 1) {
                    VStack(spacing: 1) {
                        Text(shortLabel(window.currentName))
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundStyle(accent)

                        Text(window.currentTime)
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .monospacedDigit()
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 38, height: 1)

                    HStack(spacing: 2) {
                        Text(shortLabel(window.nextName))
                            .font(.system(size: 7, weight: .semibold, design: .serif))
                            .foregroundStyle(accent)

                        Text(window.nextTime)
                            .font(.system(size: 8, weight: .bold, design: .serif))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("--:--")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
            }
        }
    }

    private var lockRectangularView: some View {
        let window = resolvedWindow()

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text(window.map { "\(displayName(for: $0.currentName)) \($0.currentTime)" } ?? "Keine Daten")
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fontDesign(.serif)

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.brown.opacity(0.6))
                        .frame(width: 18, height: 18)

                    Text(dayNumber())
                        .font(.system(size: 12, weight: .light, design: .serif))
                }
            }

            HStack(spacing: 0) {
                prayerLockTile(symbol: PrayerStatusIcon.symbolName(forCanonicalRow: "Fajr"), short: "FJR", time: entry.times.fajr, showDivider: true)
                prayerLockTile(symbol: PrayerStatusIcon.symbolName(forCanonicalRow: "Shuruk"), short: "SRK", time: entry.times.shuruk, showDivider: true)
                prayerLockTile(symbol: PrayerStatusIcon.symbolName(forCanonicalRow: "Dhuhr"), short: dhuhrShortTitle, time: entry.times.dhuhr, showDivider: true)
                prayerLockTile(symbol: PrayerStatusIcon.symbolName(forCanonicalRow: "Asr"), short: "ASR", time: entry.times.asr, showDivider: true)
                prayerLockTile(symbol: PrayerStatusIcon.symbolName(forCanonicalRow: "Maghrib"), short: "MGB", time: entry.times.maghrib, showDivider: true)
                prayerLockTile(symbol: PrayerStatusIcon.symbolName(forCanonicalRow: "Isha"), short: "ISH", time: entry.times.isha, showDivider: false)
            }
            .frame(maxWidth: .infinity)

            if let lastThird = lastThirdOfNightWindow() {
                Text("Letztes Drittel \(clockText(lastThird.start, timezoneIdentifier: lastThird.timezoneIdentifier))–\(clockText(lastThird.end, timezoneIdentifier: lastThird.timezoneIdentifier))")
                    .font(.system(size: 8, weight: .light, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 2)
    }

    private func prayerLockTile(symbol: String, short: String, time: String, showDivider: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(height: 10)

                Text(short)
                    .font(.system(size: 9, weight: .light, design: .serif))
                    .foregroundStyle(.brown)

                Text(time)
                    .font(.system(size: 12, weight: .light, design: .serif))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 38)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dayNumber() -> String {
        HijriDateFormatting.dayText(for: entry.date)
    }

    /// `nil` whenever a required previous/next cached day is missing —
    /// never a fabricated window.
    private func lastThirdOfNightWindow() -> LastThirdOfNightResolver.ResolvedWindow? {
        let autoSettings = settingsStore.loadAutoSettings()
        return LastThirdOfNightResolver.window(now: entry.date, store: store, settings: autoSettings)
    }

    /// `nil` whenever a required previous/next cached day is missing —
    /// never a fabricated window. See `IshaMidnightKarahaResolver`.
    private func postMidnightKarahaWindow() -> IshaMidnightKarahaResolver.ResolvedWindow? {
        let autoSettings = settingsStore.loadAutoSettings()
        return IshaMidnightKarahaResolver.window(now: entry.date, store: store, settings: autoSettings)
    }

    /// `nil` whenever the approximation is suppressed (implausible
    /// latitude) or there's no cached data yet. See `QiratTimeResolver`.
    private func preMaghribKarahaWindow() -> QiratTimeResolver.ApproximateWindow? {
        let autoSettings = settingsStore.loadAutoSettings()
        return QiratTimeResolver.windows(now: entry.date, store: store, settings: autoSettings).lateMaghribKaraha
    }

    /// Every boundary marker to draw on the medium widget's progress bar
    /// for the given status — the same "Letztes Drittel"/post-midnight
    /// Isha Karāha/Karāha-vor-Maghrib boundaries the Gebetszeiten page's
    /// own "Aktueller Status" bar marks (see `CurrentStatusCard.markers`
    /// there), just without a clock-time label here — only the tick
    /// itself. Each value is a 0...1 fraction of `displayStart...
    /// displayEnd`.
    private func progressMarkerFractions(
        status: CurrentPrayerStatusCalculator.Status?,
        displayStart: Date,
        displayEnd: Date
    ) -> [Double] {
        guard let status else { return [] }

        let boundaries: [Date?]
        switch status.kind {
        case .isha:
            boundaries = [postMidnightKarahaWindow()?.start, lastThirdOfNightWindow()?.start]
        case .asr:
            boundaries = [preMaghribKarahaWindow()?.start]
        default:
            boundaries = []
        }

        let total = displayEnd.timeIntervalSince(displayStart)
        guard total > 0 else { return [] }

        return boundaries.compactMap { date in
            guard let date else { return nil }
            let offset = date.timeIntervalSince(displayStart)
            return min(max(offset / total, 0), 1)
        }
    }

    /// `nil` unless `entry.date` currently falls inside the Sonnenaufgangs-
    /// Karāha window (starts exactly at Shuruk, never Fajr) or the
    /// approximate Karāha-vor-Maghrib window (see `QiratTimeResolver`) — a
    /// live "avoid voluntary prayer right now" indicator, not a static
    /// schedule (that's the Home screen's job — which no longer shows
    /// Karāha at all). Never implies Asr itself is impermissible — the
    /// pre-Maghrib window only ever starts a fixed approximation before
    /// Maghrib, never at Asr.
    private func activeQiratLabel() -> String? {
        let autoSettings = settingsStore.loadAutoSettings()
        let windows = QiratTimeResolver.windows(now: entry.date, store: store, settings: autoSettings)

        if let window = windows.sunriseKaraha, entry.date >= window.start, entry.date < window.end {
            return "Karāha (Sonnenaufgang)"
        }
        if let window = windows.preDhuhrKaraha, entry.date >= window.start, entry.date < window.end {
            return "Karāha (vor Dhuhr)"
        }
        if let window = windows.lateMaghribKaraha, entry.date >= window.start, entry.date < window.end {
            return "Karāha (vor Maghrib)"
        }
        return nil
    }

    /// Formats an already-resolved absolute `Date` as a clock time in the
    /// *prayer location's* own timezone — never the device's.
    private func clockText(_ date: Date, timezoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Resolves the current/next prayer window for `entry.date` purely from
    /// data already carried on the entry (`times`/`previousDayTimes`/
    /// `nextDayTimes`, all baked in once by the `Provider` when the entry
    /// was built) — no extra App-Group read from inside the view layer, and
    /// the exact same `PrayerWindowResolver` every widget family uses, so
    /// they can never disagree. `nil` means there genuinely isn't enough
    /// cached data to resolve a window — callers must show an honest empty
    /// state, never a fabricated one.
    private func resolvedWindow() -> PrayerWindowResolver.Window? {
        let todayAdjusted = AdjustedPrayerTimes(times: entry.times, dayOffsets: entry.dayOffsets)
        let previousAdjusted = entry.previousDayTimes.map {
            AdjustedPrayerTimes(times: $0, dayOffsets: entry.previousDayOffsets)
        }
        let nextAdjusted = entry.nextDayTimes.map {
            AdjustedPrayerTimes(times: $0, dayOffsets: entry.nextDayOffsets)
        }

        return PrayerWindowResolver.resolve(
            now: entry.date,
            todayTimes: todayAdjusted,
            previousDayTimes: previousAdjusted,
            nextDayTimes: nextAdjusted
        )
    }

    /// Refines `window` into the Karāha/Duha/last-third-aware status the
    /// medium widget's big tile displays — the exact same
    /// `CurrentPrayerStatusCalculator` the Gebetszeiten page uses, fed
    /// from data already carried on the entry (no extra App-Group read
    /// beyond what `activeQiratLabel()`/`lastThirdOfNightWindow()` already
    /// perform elsewhere in this view). `nil` whenever none of the
    /// underlying windows are resolvable or active — callers fall back to
    /// `window` itself.
    private func currentStatus(window: PrayerWindowResolver.Window) -> CurrentPrayerStatusCalculator.Status? {
        let autoSettings = settingsStore.loadAutoSettings()
        let qiratWindows = QiratTimeResolver.windows(now: entry.date, store: store, settings: autoSettings)
        let todayAdjusted = AdjustedPrayerTimes(times: entry.times, dayOffsets: entry.dayOffsets)
        let duhaWindow = DuhaCalculator.resolve(
            now: entry.date,
            todayTimes: todayAdjusted,
            sunriseKarahaWindow: qiratWindows.sunriseKaraha,
            preDhuhrKarahaWindow: qiratWindows.preDhuhrKaraha
        )

        return CurrentPrayerStatusCalculator.resolve(
            now: entry.date,
            window: window,
            duhaWindow: duhaWindow,
            sunriseKarahaWindow: qiratWindows.sunriseKaraha,
            preDhuhrKarahaWindow: qiratWindows.preDhuhrKaraha,
            preMaghribKarahaWindow: qiratWindows.lateMaghribKaraha,
            lastThirdWindow: lastThirdOfNightWindow(),
            postMidnightKarahaWindow: postMidnightKarahaWindow()
        )
    }

    private func todaysHighlightState(window: PrayerWindowResolver.Window?) -> (
        current: String?,
        next: String?,
        primary: String?
    ) {
        guard let window else { return (nil, nil, nil) }

        let calendar = Calendar.current

        let currentToday = calendar.isDate(window.start, inSameDayAs: entry.date) ? window.currentName : nil
        let nextToday = calendar.isDate(window.end, inSameDayAs: entry.date) ? window.nextName : nil
        let primary = currentToday ?? nextToday

        return (
            current: currentToday,
            next: nextToday,
            primary: primary
        )
    }

    private func shortLabel(_ value: String) -> String {
        switch value {
        case "Fajr": return "FJR"
        case "Shuruk": return "SRK"
        case "Dhuhr": return dhuhrShortTitle
        case "Asr": return "ASR"
        case "Maghrib": return "MGB"
        case "Isha": return "ISH"
        default: return String(value.prefix(3)).uppercased()
        }
    }

    private func displayName(for value: String) -> String {
        switch value {
        case "Dhuhr": return dhuhrTitle
        default: return value
        }
    }

    /// Every "Dhuhr" moment reaching `displayName`/`shortLabel` here is
    /// always *today's* Dhuhr (traced through `resolvedWindow()`/
    /// `PrayerWindowResolver`: only today's own moments carry the "Dhuhr"
    /// name — yesterday only contributes Isha, tomorrow only Fajr), so
    /// `entry.date` is always the correct calendar day for the
    /// Friday/Jum'ah check, in the location's own timezone via
    /// `entry.times.timezone`.
    private var dhuhrTitle: String {
        PrayerDisplayNaming.dhuhrLabel(date: entry.date, timezoneIdentifier: entry.times.timezone)
    }

    private var dhuhrShortTitle: String {
        PrayerDisplayNaming.dhuhrShortLabel(date: entry.date, timezoneIdentifier: entry.times.timezone)
    }
}

extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                WidgetBackgroundGradient()
            }
        } else {
            self.background(WidgetBackgroundGradient())
        }
    }
}

/// The widget's own page background — the near-black gradient this app
/// has always used in dark mode (unchanged), and a cream gradient in
/// light mode matching the main app's own light-mode look exactly (the
/// same RGB values as `Assets.xcassets/AppBackground.colorset`'s light
/// variant). Reads `colorScheme` straight from the environment, so it
/// follows the iPhone's own system Light/Dark Mode setting — widgets have
/// no access to the app's own in-app appearance override
/// (`AppearanceSettingsStore`), and this never needs one: the system
/// setting is exactly what's being asked for here.
private struct WidgetBackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.black.opacity(0.96), Color.black.opacity(0.88)]
                : [
                    Color(red: 1.0, green: 0.99, blue: 0.97),
                    Color(red: 0.980, green: 0.973, blue: 0.953)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private func previewEntry() -> PrayerEntry {
    let today = PrayerTimes(
        fajr: "05:30", shuruk: "07:00", dhuhr: "12:15", asr: "14:45",
        maghrib: "17:15", isha: "18:45",
        readableDate: "2 Jan 2026", readableDay: "Friday",
        hijriDate: "--", hijriDay: "--", timezone: "Europe/Berlin"
    )
    return PrayerEntry(
        date: Date(),
        times: today,
        dayOffsets: .zero,
        previousDayTimes: today,
        previousDayOffsets: .zero,
        nextDayTimes: today,
        nextDayOffsets: .zero
    )
}

#Preview("Small", as: .systemSmall) {
    PrayerTimesWidgetStructure()
} timeline: {
    previewEntry()
}

#Preview("Medium", as: .systemMedium) {
    PrayerTimesWidgetStructure()
} timeline: {
    previewEntry()
}

#Preview("Lock Inline", as: .accessoryInline) {
    PrayerTimesWidgetStructure()
} timeline: {
    previewEntry()
}

#Preview("Lock Circular", as: .accessoryCircular) {
    PrayerTimesWidgetStructure()
} timeline: {
    previewEntry()
}

#Preview("Lock Rectangular", as: .accessoryRectangular) {
    PrayerTimesWidgetStructure()
} timeline: {
    previewEntry()
}
