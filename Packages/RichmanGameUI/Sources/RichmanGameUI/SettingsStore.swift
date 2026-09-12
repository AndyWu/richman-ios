import SwiftUI

/// How fast a roll's token-hop-and-camera-zoom animation plays. Concrete
/// durations, not just a "speed" label, so `GameViewModel.rollDice` can use
/// them directly.
enum AnimationSpeed: String, CaseIterable, Identifiable, Sendable {
    case slow, medium, fast

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Duration of one tile-hop step during the move animation.
    var hopStepDuration: TimeInterval {
        switch self {
        case .slow: return 0.38
        case .medium: return 0.22
        case .fast: return 0.10
        }
    }

    /// Duration of the camera zooming back out to the overview once a move settles.
    var zoomSettleDuration: TimeInterval {
        switch self {
        case .slow: return 0.55
        case .medium: return 0.35
        case .fast: return 0.18
        }
    }
}

/// `system` follows the device's own appearance setting; `light`/`dark` pin it.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// What to hand `.preferredColorScheme(_:)`; `nil` means "don't override."
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// User-adjustable preferences, persisted to `UserDefaults`. `RichmanGameUI`
/// is the only thing that reads or writes these — see `Docs/ARCHITECTURE.md`
/// ("if you're adding a screen or animation, you're in `RichmanGameUI`").
///
/// `soundVolume` is stored and exposed here so the setting exists and
/// persists, but nothing plays sound yet — `PlaceholderAssetProvider`
/// returns `nil` for every sound (see `RichmanAssetsKit`), so this currently
/// has no audible effect. Wiring it to real playback is a `RichmanAssetsKit`
/// change once real sound assets land.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let animationSpeed = "richman.settings.animationSpeed"
        static let theme = "richman.settings.theme"
        static let soundVolume = "richman.settings.soundVolume"
    }

    @Published var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: Keys.animationSpeed) }
    }
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }
    /// 0...1.
    @Published var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.animationSpeed = defaults.string(forKey: Keys.animationSpeed).flatMap(AnimationSpeed.init) ?? .medium
        self.theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init) ?? .system
        self.soundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 0.8
    }
}
