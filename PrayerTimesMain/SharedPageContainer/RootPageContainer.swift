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
