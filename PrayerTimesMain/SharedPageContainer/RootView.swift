import SwiftUI

enum MainPage: Int, Hashable {
    case qibla
    case prayerTimes
    case islamicCalendar
}

struct RootView: View {
    @State private var selectedPage: MainPage = .prayerTimes

    var body: some View {
        ZStack {
            TabView(selection: $selectedPage) {
                QiblaView(isActivePage: selectedPage == .qibla)
                    .tag(MainPage.qibla)

                PrayerTimesHomeView()
                    .tag(MainPage.prayerTimes)

                IslamicCalendarView()
                    .tag(MainPage.islamicCalendar)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .ignoresSafeArea()
    }
}
