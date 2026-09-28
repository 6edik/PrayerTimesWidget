import SwiftUI
import UIKit

enum MainPage: Int, Hashable {
    case qibla
    case prayerTimes
    case islamicCalendar
}

struct RootView: View {
    @EnvironmentObject private var appearance: AppearanceViewModel
    @State private var selectedPage: MainPage = .prayerTimes

    var body: some View {
        ZStack {
            TabView(selection: $selectedPage) {
                QiblaView(isActivePage: selectedPage == .qibla)
                    .tag(MainPage.qibla)

                PrayerTimesHomeView()
                    .tag(MainPage.prayerTimes)

                IslamicCalendarView(
                    settingsProvider: {
                        SharedPrayerSettingsStore().loadAutoSettings()
                    }
                )
                .tag(MainPage.islamicCalendar)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color("AppBackground").ignoresSafeArea())
        .ignoresSafeArea()
        // Single, central override for the whole view hierarchy — every
        // screen, sheet and popover presented anywhere below this point
        // (Home, calendar, Qibla, settings, day sheets) inherits this
        // environment value, so nothing else needs its own dark-mode code.
        .preferredColorScheme(appearance.isDarkModeEnabled ? .dark : .light)
        // `.preferredColorScheme` alone doesn't reliably reach the already-
        // running UIKit-hosted `.page`-style TabView (a UIPageViewController)
        // or sheets already on screen — their hosting controllers only pick
        // up a new trait collection on next creation, i.e. after a restart.
        // Explicitly pushing the override onto every window closes that gap
        // without recreating any view or losing navigation/input state.
        .onChange(of: appearance.isDarkModeEnabled) { _, isDarkModeEnabled in
            applyInterfaceStyleOverride(isDarkModeEnabled)
        }
        .onAppear {
            applyInterfaceStyleOverride(appearance.isDarkModeEnabled)
        }
    }

    private func applyInterfaceStyleOverride(_ isDarkModeEnabled: Bool) {
        let style: UIUserInterfaceStyle = isDarkModeEnabled ? .dark : .light

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
                if let root = window.rootViewController {
                    applyInterfaceStyleOverride(style, to: root)
                }
                // The real `UINavigationBar` backing a `.sheet`'s
                // `NavigationStack` isn't reliably reachable by walking view
                // controllers alone — SwiftUI doesn't always expose it via
                // `.children`. Walking the actual view hierarchy and setting
                // the override on every UIView guarantees it's hit directly,
                // wherever it lives, without recreating any view or losing
                // navigation/input state.
                applyInterfaceStyleOverride(style, to: window)
            }
        }
    }

    private func applyInterfaceStyleOverride(_ style: UIUserInterfaceStyle, to controller: UIViewController) {
        controller.overrideUserInterfaceStyle = style

        for child in controller.children {
            applyInterfaceStyleOverride(style, to: child)
        }

        if let presented = controller.presentedViewController {
            applyInterfaceStyleOverride(style, to: presented)
        }
    }

    private func applyInterfaceStyleOverride(_ style: UIUserInterfaceStyle, to view: UIView) {
        view.overrideUserInterfaceStyle = style

        for subview in view.subviews {
            applyInterfaceStyleOverride(style, to: subview)
        }
    }
}

#Preview("Light") {
    RootView()
        .environmentObject(AppearanceViewModel())
}

#Preview("Dark") {
    let appearance = AppearanceViewModel()
    return RootView()
        .environmentObject(appearance)
        .onAppear { appearance.isDarkModeEnabled = true }
}
