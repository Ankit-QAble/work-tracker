import Foundation
import Combine

/// User-configurable settings, persisted to UserDefaults. Backs the Settings panel.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let idleThresholdSeconds = "idleThresholdSeconds"
        static let screenshotsEnabled = "screenshotsEnabled"
        static let screenshotIntervalMinutes = "screenshotIntervalMinutes"
        static let excludedApps = "excludedApps"
    }

    @Published var idleThresholdSeconds: Double {
        didSet { UserDefaults.standard.set(idleThresholdSeconds, forKey: Keys.idleThresholdSeconds) }
    }

    @Published var screenshotsEnabled: Bool {
        didSet { UserDefaults.standard.set(screenshotsEnabled, forKey: Keys.screenshotsEnabled) }
    }

    @Published var screenshotIntervalMinutes: Double {
        didSet { UserDefaults.standard.set(screenshotIntervalMinutes, forKey: Keys.screenshotIntervalMinutes) }
    }

    /// App names (NSRunningApplication.localizedName) excluded from all tracking:
    /// no interval rows, no window titles, no URLs, no screenshots while frontmost.
    @Published var excludedApps: [String] {
        didSet { UserDefaults.standard.set(excludedApps, forKey: Keys.excludedApps) }
    }

    private init() {
        let defaults = UserDefaults.standard
        idleThresholdSeconds = defaults.object(forKey: Keys.idleThresholdSeconds) as? Double ?? 180
        screenshotsEnabled = defaults.object(forKey: Keys.screenshotsEnabled) as? Bool ?? false
        screenshotIntervalMinutes = defaults.object(forKey: Keys.screenshotIntervalMinutes) as? Double ?? 10
        excludedApps = defaults.stringArray(forKey: Keys.excludedApps) ?? []
    }

    func isExcluded(appName: String) -> Bool {
        excludedApps.contains(appName)
    }
}
