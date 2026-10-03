import SwiftUI

/// Shared "glass card" info-sheet design, established by the Qibla tab's
/// Hinweise sheet (`QiblaInfoSheet`) — the single design reference every
/// similar sheet opened from the Islamic-calendar tab (Kalender-Hinweise,
/// Ahadith, Besondere Tage) now follows too, instead of each one carrying
/// its own slightly different copy of the same colors/padding/close
/// button. Never used for Form-style pages (the personal-note editor,
/// Notification-Einstellungen) — only for this specific browsing/
/// "Hinweise" page shape.
enum IslamicCalendarPageStyle {
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.58, blue: 0.20), Color.orange.opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let accentStrong = Color(red: 0.73, green: 0.55, blue: 0.20)
    static let accentTint = Color(red: 0.78, green: 0.60, blue: 0.22).opacity(0.16)
    static let cardPadding = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
}

/// The exact close-button style every "Hinweise"-shaped sheet uses:
/// a plain xmark, 13pt semibold, in a 32×32 tap target.
struct IslamicCalendarCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Schließen")
    }
}

/// `NavigationStack` + `ScrollView` + `LazyVStack(spacing: 20)`, the exact
/// padding/background/navigation-bar conventions `QiblaInfoSheet`
/// established, plus the shared close button in the trailing toolbar
/// slot. Every "Hinweise"-shaped calendar sheet wraps its cards in this
/// instead of rebuilding the scaffold itself.
struct IslamicCalendarPageContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IslamicCalendarCloseButton { dismiss() }
                }
            }
        }
    }
}

/// The hero header every "Hinweise"-shaped sheet opens with: a plain
/// (non-circled) icon, the ultraLight serif title, and an optional
/// secondary subtitle — exactly `QiblaInfoSheet.heroCard`'s shape.
struct IslamicCalendarHeroCard: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(IslamicCalendarPageStyle.accentGradient)

            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.weight(.ultraLight))
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(IslamicCalendarPageStyle.cardPadding)
        .glassCard(cornerRadius: 24)
    }
}

/// A titled content card with a small tinted icon badge — exactly
/// `QiblaInfoSheet.infoCard`'s shape, reused by every calendar sub-page's
/// sections (color legend, Sunnah-fasting, holiday list, notes, …).
struct IslamicCalendarSectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IslamicCalendarPageStyle.accentGradient)
                    .background(IslamicCalendarPageStyle.accentTint, in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: 34, height: 34)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }
}

/// A full-width, glass-background row used for secondary navigation
/// actions inside a section card (e.g. "Ahadith anzeigen") — the same
/// shape `IslamicCalenderInfoSheet` already used, now shared.
struct IslamicCalendarActionButton: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(IslamicCalendarPageStyle.accentTint)
                        .frame(width: 32, height: 32)

                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IslamicCalendarPageStyle.accentGradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassBackground(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
