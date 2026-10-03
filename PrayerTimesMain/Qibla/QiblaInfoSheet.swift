import SwiftUI

/// The design reference for every "Hinweise"-shaped sheet in the app —
/// see `IslamicCalendarPageStyle.swift` for the shared components this
/// page's original hand-written layout was extracted into.
struct QiblaInfoSheet: View {
    var body: some View {
        IslamicCalendarPageContainer(title: "Hinweise") {
            IslamicCalendarHeroCard(
                symbol: "location.north.line.fill",
                title: "Qibla-Kompass",
                subtitle: "Die Richtung wird aus deinem Standort zur Kaaba berechnet. Der Kompass reagiert auf deine Geräteausrichtung."
            )

            IslamicCalendarSectionCard(title: "Wichtige Hinweise", symbol: "sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    bulletRow("Die Qibla-Zahl hängt vom aktuellen Ort ab und ist nicht überall gleich.")
                    bulletRow("Beim Neujustieren wird der Standort frisch abgefragt.")
                    bulletRow("Metall, Lautsprecher oder Magnetzubehör können die Kompassmessung verfälschen.")
                    bulletRow("In Gebäuden ist die Orientierung oft ungenauer als im Freien.")
                }
            }

            IslamicCalendarSectionCard(title: "Für bessere Genauigkeit", symbol: "scope") {
                VStack(alignment: .leading, spacing: 10) {
                    tipPill(title: "Kalibrieren", text: "Nutze den Button oben rechts zum Neujustieren bei unruhiger Anzeige.")
                    tipPill(title: "Standort", text: "Warte, bis Ortsname oder Koordinaten aktualisiert wurden.")
                    tipPill(title: "Umgebung", text: "Entferne magnetische Hüllen oder halte Abstand zu Elektronik.")
                }
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(IslamicCalendarPageStyle.accentStrong.opacity(0.9))
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func tipPill(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(IslamicCalendarPageStyle.accentStrong)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassBackground(cornerRadius: 16)
    }
}
