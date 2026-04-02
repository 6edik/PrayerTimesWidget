import SwiftUI

struct TopBarActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.orange.opacity(0.95))
                .frame(width: 36, height: 36)
                //.background(.thinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
