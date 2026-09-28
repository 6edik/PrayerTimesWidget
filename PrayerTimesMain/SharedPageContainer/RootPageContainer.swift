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
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground").ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppPageHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(Color.orange.opacity(0.95))
        .font(.system(size: 34, weight: .ultraLight, design: .serif))
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .padding(.horizontal, 32)
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
