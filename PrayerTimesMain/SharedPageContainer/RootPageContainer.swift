import SwiftUI

struct AppPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal)
            .padding(.top)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppPageHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
        }
        .foregroundStyle(Color.orange.opacity(0.95))
        .font(.system(size: 34, weight: .ultraLight, design: .serif))
        .frame(height: 30)
    }
}

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
                    .fill(Color.white.opacity(0.04))
            )
    }
}
