import Foundation
import Combine

/// Single source of truth for the app's manual dark-mode override. One
/// instance is created at the app root (`PrayerTimesApp`) and injected via
/// `.environmentObject(...)`, so every screen — Home, calendar, Qibla,
/// settings, day sheets — shares this exact instance instead of each
/// reading its own copy: `RootView` applies `.preferredColorScheme` once
/// from it, and `PrayerSettingsView`'s toggle mutates the same published
/// property, so the switch takes effect everywhere immediately, with no
/// app restart.
///
/// This only ever affects the main app's own view hierarchy.
/// `PrayerTimesWidgetExtension` runs as a separate process and always
/// follows the iOS system appearance for its widgets — WidgetKit has no
/// supported way for a host app to force a widget's color scheme, and
/// wiring one up (e.g. writing this flag to the shared App Group and having
/// the widget read and apply it) would be exactly the kind of bespoke
/// widget/app theme sync this feature deliberately does not build. The
/// widget's own dark, glass-card design already reads clearly in both
/// system appearances regardless.
@MainActor
final class AppearanceViewModel: ObservableObject {
    @Published var isDarkModeEnabled: Bool {
        didSet {
            guard oldValue != isDarkModeEnabled else { return }
            store.setDarkModeEnabled(isDarkModeEnabled)
        }
    }

    private let store: AppearanceSettingsStore

    init(store: AppearanceSettingsStore = AppearanceSettingsStore()) {
        self.store = store
        self.isDarkModeEnabled = store.isDarkModeEnabled()
    }
}
