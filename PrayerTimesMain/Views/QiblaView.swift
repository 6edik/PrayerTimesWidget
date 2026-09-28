import SwiftUI
import UIKit

struct QiblaView: View {
    let isActivePage: Bool

    @StateObject private var viewModel = QiblaViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showInfoSheet = false

    private let compassSize: CGFloat = 312
    private let alignmentHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            AppPageContainer {
                AppPageHeader(title: "Gebetsrichtung")
                headerSection

                if viewModel.canUseLiveLocation {
                    compassSection
                } else {
                    // Ohne Standortfreigabe funktioniert der Kompass nicht —
                    // statt ihn (nicht funktionsfähig) anzuzeigen, steht die
                    // Freigabe-Karte direkt sichtbar an seiner Stelle, statt
                    // weit unten auf der Seite.
                    locationPermissionCard
                }

                if viewModel.canUseLiveLocation, let errorMessage = viewModel.state.errorMessage {
                    errorSection(errorMessage)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TopBarActionButton(
                        systemImage: "scope",
                        accessibilityLabel: "Standort für Qibla aktualisieren"
                    ) {
                        viewModel.activateLocationAccess()
                    }

                    TopBarActionButton(
                        systemImage: "info.circle",
                        accessibilityLabel: "Hinweise"
                    ) {
                        showInfoSheet = true
                    }
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                QiblaInfoSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                if viewModel.canUseLiveLocation {
                    bottomBar
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            alignmentHaptic.prepare()

            if isActivePage, scenePhase == .active {
                viewModel.start()
            }
        }
        .onChange(of: isAligned) { _, newValue in
            guard isActivePage, scenePhase == .active else { return }

            if newValue {
                alignmentHaptic.impactOccurred(intensity: 3)
                alignmentHaptic.prepare()
            }
        }
        .onChange(of: isActivePage) { _, newValue in
            if newValue {
                viewModel.start()
                alignmentHaptic.prepare()
            } else {
                viewModel.stop()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard isActivePage else { return }

            switch newPhase {
            case .active:
                viewModel.start()
                alignmentHaptic.prepare()
            case .inactive:
                break
            case .background:
                viewModel.stop()
            @unknown default:
                break
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            if viewModel.canUseLiveLocation {
                Text(viewModel.state.cityLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(viewModel.state.coordinateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(alignmentText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(alignmentColor)
                    .padding(.top, 2)
            }
        }
    }

    private var compassSection: some View {
        VStack(spacing: 18) {
            // Isolated in its own view observing the needle animator
            // directly, so the up-to-120Hz rotation animation only
            // re-renders this small dial instead of the whole page
            // (header, bottom bar, gradients) on every frame.
            QiblaCompassDial(
                needleAnimator: viewModel.needleAnimator,
                qiblaBearing: viewModel.state.qiblaBearing,
                compassSize: compassSize
            )
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(directionInstruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Entfernung zur Kaaba: \(viewModel.state.distanceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Kompassbezug: \(viewModel.state.headingReference.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
        }
    }

    private var locationPermissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Standortzugriff erforderlich")
                .font(.headline)

            Text(
                viewModel.state.authorizationDenied
                ? "Der Kompass braucht deinen Standort für die Gebetsrichtung. Bitte erlaube den Zugriff in den Einstellungen."
                : "Der Kompass braucht deinen Standort, um die Gebetsrichtung (Qibla) korrekt zu berechnen. Ohne Freigabe zeigt er keine Richtung an."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button(viewModel.state.authorizationDenied ? "Einstellungen öffnen" : "Standort freigeben") {
                viewModel.activateLocationAccess()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: compassSize)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorSection(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            bottomMetric(title: "Qibla", value: viewModel.state.bearingText)
            bottomMetric(title: "Gerät", value: viewModel.state.userHeadingText)
            bottomMetric(title: "Abweich.", value: offsetText)
            bottomMetric(title: "Genauigk.", value: viewModel.state.accuracyText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 340)
        .background(.thinMaterial)
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

    private func bottomMetric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var alignmentDelta: Double {
        let raw = QiblaCalculator.normalized(
            viewModel.state.qiblaBearing - viewModel.needleAnimator.displayedHeading
        )
        return raw > 180 ? raw - 360 : raw
    }

    private var isAligned: Bool {
        abs(alignmentDelta) <= 5
    }

    private var alignmentText: String {
        isAligned ? "Richtig ausgerichtet" : "Noch nicht ausgerichtet"
    }

    private var alignmentColor: Color {
        isAligned ? .green : Color.orange.opacity(0.95)
    }

    private var directionInstruction: String {
        if isAligned {
            return "Du bist zur Qibla ausgerichtet"
        }

        return alignmentDelta > 0
            ? "Drehe dich leicht nach rechts"
            : "Drehe dich leicht nach links"
    }

    private var offsetText: String {
        "\(Int(abs(alignmentDelta).rounded()))°"
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.985, green: 0.975, blue: 0.95),
                Color(red: 0.965, green: 0.945, blue: 0.90),
                Color(red: 0.95, green: 0.925, blue: 0.865)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The rotating needle dial, isolated so it can observe `needleAnimator`
/// directly. Its `displayedHeading` changes up to ~120 times per second
/// while the compass is settling; keeping that observation scoped to just
/// this small view (instead of the whole `QiblaView`) means only this dial
/// re-renders per frame — not the header, bottom bar and their gradients.
private struct QiblaCompassDial: View {
    @ObservedObject var needleAnimator: QiblaNeedleAnimator
    let qiblaBearing: Double
    let compassSize: CGFloat

    private var alignmentDelta: Double {
        let raw = QiblaCalculator.normalized(qiblaBearing - needleAnimator.displayedHeading)
        return raw > 180 ? raw - 360 : raw
    }

    private var isAligned: Bool {
        abs(alignmentDelta) <= 5
    }

    var body: some View {
        ZStack {
            rotatingCompassLayer
            centerPin
        }
        .frame(width: compassSize, height: compassSize)
    }

    private var rotatingCompassLayer: some View {
        ZStack {
            Image("qiblaCompassBg")
                .resizable()
                .scaledToFill()
                .frame(width: compassSize, height: compassSize)
                .scaleEffect(1.035)

            QiblaRingMarker(
                angle: qiblaBearing,
                isAligned: isAligned
            )
            .frame(width: compassSize, height: compassSize)
        }
        .frame(width: compassSize, height: compassSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.72, blue: 0.34),
                            Color(red: 0.78, green: 0.55, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
        }
        .shadow(color: Color.orange.opacity(0.14), radius: 24, y: 8)
        .rotationEffect(.degrees(-needleAnimator.displayedHeading))
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var centerPin: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            Circle()
                .fill(Color(red: 0.71, green: 0.54, blue: 0.22))
                .frame(width: 5, height: 5)
        }
    }
}

private struct QiblaRingMarker: View {
    let angle: Double
    let isAligned: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.355

            ZStack {
                marker
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private var marker: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(glowColor)
                    .frame(width: 26, height: 26)
                    .blur(radius: 8)

                DiamondMarker()
                    .fill(markerGradient)
                    .frame(width: 16, height: 16)
                    .overlay {
                        DiamondMarker()
                            .stroke(Color.white.opacity(0.55), lineWidth: 0.9)
                    }
            }

            Capsule()
                .fill(markerGradient)
                .frame(width: 3, height: 18)

            Circle()
                .fill(markerBaseColor)
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
    }

    private var markerBaseColor: Color {
        isAligned
            ? Color.green.opacity(0.95)
            : Color(red: 0.88, green: 0.63, blue: 0.20)
    }

    private var glowColor: Color {
        isAligned
            ? Color.green.opacity(0.28)
            : Color(red: 0.95, green: 0.72, blue: 0.28).opacity(0.34)
    }

    private var markerGradient: LinearGradient {
        LinearGradient(
            colors: isAligned
                ? [
                    Color.green.opacity(1.0),
                    Color.green.opacity(0.72)
                ]
                : [
                    Color(red: 0.98, green: 0.76, blue: 0.30),
                    Color(red: 0.78, green: 0.52, blue: 0.16)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct DiamondMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

#Preview("Qibla view (Light)") {
    QiblaView(isActivePage: true)
        .environmentObject(AppearanceViewModel())
}

#Preview("Qibla view (Dark)") {
    QiblaView(isActivePage: true)
        .environmentObject(AppearanceViewModel())
        .preferredColorScheme(.dark)
}

// Bypasses the location-permission gate so the compass image itself (and
// its light/dark asset variants) can be checked directly.
#Preview("Compass dial (Light)") {
    QiblaCompassDial(needleAnimator: QiblaNeedleAnimator(), qiblaBearing: 120, compassSize: 312)
        .padding(40)
}

#Preview("Compass dial (Dark)") {
    QiblaCompassDial(needleAnimator: QiblaNeedleAnimator(), qiblaBearing: 120, compassSize: 312)
        .padding(40)
        .preferredColorScheme(.dark)
}
