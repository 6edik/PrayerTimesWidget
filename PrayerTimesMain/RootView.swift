import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            PrayerTimesHomeView()
                .tag(0)

            IslamicCalendarView()
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}
