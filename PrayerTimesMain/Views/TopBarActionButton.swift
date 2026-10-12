import SwiftUI

struct TopBarActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        // Deliberately no `.buttonStyle(.plain)`, fixed frame, or
        // `.clipShape` — those used to suppress the system's automatic
        // Liquid Glass button styling in a toolbar, leaving only a flat
        // custom circle behind a plain shared capsule. Letting the
        // default button style through here is what makes this render
        // with the same glass look every other icon-only toolbar button
        // in the app already has (e.g. the info button on the
        // Benachrichtigungen page).
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.orange.opacity(0.95))
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
