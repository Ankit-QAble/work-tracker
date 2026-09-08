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
        static let idlePromptEnabled = "idlePromptEnabled"
        static let idlePromptThresholdSeconds = "idlePromptThresholdSeconds"
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

    /// When you return from being idle longer than `idlePromptThresholdSeconds`, ask
    /// whether that stretch should count as tracked time (attributed to whatever app
    /// was active before you stepped away) or stay logged as idle. This is separate
    /// from `idleThresholdSeconds` (which just controls when auto-pause kicks in) —
    /// you can auto-pause quickly but only get asked about it for longer absences.
    @Published var idlePromptEnabled: Bool {
        didSet { UserDefaults.standard.set(idlePromptEnabled, forKey: Keys.idlePromptEnabled) }
    }

    @Published var idlePromptThresholdSeconds: Double {
        didSet { UserDefaults.standard.set(idlePromptThresholdSeconds, forKey: Keys.idlePromptThresholdSeconds) }
    }

    private init() {
        let defaults = UserDefaults.standard
        idleThresholdSeconds = defaults.object(forKey: Keys.idleThresholdSeconds) as? Double ?? 180
        screenshotsEnabled = defaults.object(forKey: Keys.screenshotsEnabled) as? Bool ?? false
        screenshotIntervalMinutes = defaults.object(forKey: Keys.screenshotIntervalMinutes) as? Double ?? 10
        excludedApps = defaults.stringArray(forKey: Keys.excludedApps) ?? []
        idlePromptEnabled = defaults.object(forKey: Keys.idlePromptEnabled) as? Bool ?? true
        idlePromptThresholdSeconds = defaults.object(forKey: Keys.idlePromptThresholdSeconds) as? Double ?? 300
    }

    func isExcluded(appName: String) -> Bool {
        excludedApps.contains(appName)
    }
}
