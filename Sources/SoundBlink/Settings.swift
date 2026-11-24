import Foundation

/// Static facts about the app, read from Info.plist when bundled.
enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SoundBlink"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.takuhoito.soundblink"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let repositoryURL = URL(
        string: Bundle.main.object(forInfoDictionaryKey: "SBRepositoryURL") as? String
            ?? "https://github.com/takuhoito/SoundBlink"
    )!
}

/// User preferences, persisted in the app's defaults domain.
///
/// Every key can also be changed from Terminal, e.g.
/// `defaults write io.github.takuhoito.soundblink intervalMinutes 1`.
final class Settings {
    static let shared = Settings()

    static let intervalPresets = [10, 30, 60]

    private enum Key {
        static let periodicResetEnabled = "periodicResetEnabled"
        static let intervalMinutes = "intervalMinutes"
        static let skipWhilePlaying = "skipWhilePlaying"
        static let resetOnWake = "resetOnWake"
        static let switchDelay = "switchDelay"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.periodicResetEnabled: true,
            Key.intervalMinutes: 30,
            Key.skipWhilePlaying: true,
            Key.resetOnWake: true,
            Key.switchDelay: 0.5,
        ])
    }

    var periodicResetEnabled: Bool {
        get { defaults.bool(forKey: Key.periodicResetEnabled) }
        set { defaults.set(newValue, forKey: Key.periodicResetEnabled) }
    }

    var intervalMinutes: Int {
        get { max(1, defaults.integer(forKey: Key.intervalMinutes)) }
        set { defaults.set(max(1, newValue), forKey: Key.intervalMinutes) }
    }

    /// Applies to scheduled and wake-triggered resets only; a manual reset always runs.
    var skipWhilePlaying: Bool {
        get { defaults.bool(forKey: Key.skipWhilePlaying) }
        set { defaults.set(newValue, forKey: Key.skipWhilePlaying) }
    }

    var resetOnWake: Bool {
        get { defaults.bool(forKey: Key.resetOnWake) }
        set { defaults.set(newValue, forKey: Key.resetOnWake) }
    }

    /// Seconds to stay on the intermediate device before switching back.
    var switchDelay: TimeInterval {
        min(5, max(0.05, defaults.double(forKey: Key.switchDelay)))
    }
}
