import SwiftUI
import Combine

/// Single source of truth for the app's appearance choice (System/Hell/
/// Dunkel). One instance is created at the app root (`PrayerTimesApp`) and
/// injected via `.environmentObject(...)`, so every screen — Home,
/// calendar, Qibla, settings, day sheets — shares this exact instance
/// instead of each reading its own copy: `RootView` applies
/// `.preferredColorScheme` once from it, and `PrayerSettingsView`'s picker
/// mutates the same published property, so the choice takes effect
/// everywhere immediately, with no app restart.
///
/// This only ever affects the main app's own view hierarchy.
/// `PrayerTimesWidgetExtension` runs as a separate process and always
/// follows the iOS system appearance for its widgets, for all three modes
/// above — including "System", trivially, since the app following the
/// system doesn't change what widgets already always do. WidgetKit has no
/// supported way for a host app to force a widget's color scheme, and
/// wiring one up (e.g. writing this choice to the shared App Group and
/// having the widget read and apply it) would be exactly the kind of
/// bespoke widget/app theme sync this feature deliberately does not build.
/// The widget's own dark, glass-card design already reads clearly in both
/// system appearances regardless.
@MainActor
final class AppearanceViewModel: ObservableObject {
    @Published var appearanceMode: AppAppearance {
        didSet {
            guard oldValue != appearanceMode else { return }
            store.setAppearanceMode(appearanceMode)
        }
    }

    private let store: AppearanceSettingsStore

    init(store: AppearanceSettingsStore = AppearanceSettingsStore()) {
        self.store = store
        self.appearanceMode = store.appearanceMode()
    }

    /// `nil` for `.system` — SwiftUI then follows the live system
    /// appearance, including later system changes, on its own.
    /// `.light`/`.dark` otherwise force that scheme.
    var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
