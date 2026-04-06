import SwiftUI

struct QiblaInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    private let cardPadding = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.58, blue: 0.20), Color.orange.opacity(0.92)],
        startPoint: .top, endPoint: .bottom
    )
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    heroCard
                    notesCard
                    precisionCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Hinweise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
    }
    
    // MARK: - Hero Card
    private var heroCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accentGradient)
            
            VStack(spacing: 8) {
                Text("Qibla-Kompass")
                    .font(.largeTitle.weight(.ultraLight))
                    .fontDesign(.serif)
                
                Text("Die Richtung wird aus deinem Standort zur Kaaba berechnet. Der Kompass reagiert auf deine Geräteausrichtung.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(cardPadding)
        .glassCard(cornerRadius: 24)
    }
    
    // MARK: - Notes Card
    private var notesCard: some View {
        infoCard(title: "Wichtige Hinweise", symbol: "sparkles") {
            bulletRow("Die Qibla-Zahl hängt vom aktuellen Ort ab und ist nicht überall gleich.")
            bulletRow("Beim Neujustieren wird der Standort frisch abgefragt.")
            bulletRow("Metall, Lautsprecher oder Magnetzubehör können die Kompassmessung verfälschen.")
            bulletRow("In Gebäuden ist die Orientierung oft ungenauer als im Freien.")
        }
    }
    
    // MARK: - Precision Card
    private var precisionCard: some View {
        infoCard(title: "Für bessere Genauigkeit", symbol: "scope") {
            tipPill(title: "Kalibrieren", text: "Nutze den Button oben rechts zum Neujustieren bei unruhiger Anzeige.")
            tipPill(title: "Standort", text: "Warte, bis Ortsname oder Koordinaten aktualisiert wurden.")
            tipPill(title: "Umgebung", text: "Entferne magnetische Hüllen oder halte Abstand zu Elektronik.")
        }
    }
    
    // MARK: - Components
    private func infoCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentGradient)
                    .background(accentTint, in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: 34, height: 34)
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }
    
    private func stepRow(number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(accentGradient, in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(accentStrong.opacity(0.9))
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
                    .foregroundStyle(accentStrong)
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
    
    // MARK: - Styles
    private var accentTint: some ShapeStyle {
        Color(red: 0.78, green: 0.60, blue: 0.22).opacity(0.16)
    }
    
    private var accentStrong: Color {
        Color(red: 0.73, green: 0.55, blue: 0.20)
    }
}

// MARK: - View Extensions
extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    func glassBackground(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )
            )
    }
}
