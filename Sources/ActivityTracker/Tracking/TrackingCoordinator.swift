import Foundation
import AppKit
import Combine

enum TrackingStatus: String {
    case tracking = "Tracking"
    case idle = "Idle"
    case paused = "Paused"
}

/// Central brain: owns the current tracking state, wires together the individual trackers,
/// and is the single place that decides "what app interval is open right now".
final class TrackingCoordinator: ObservableObject {
    static let shared = TrackingCoordinator()

    @Published private(set) var status: TrackingStatus = .tracking
    @Published private(set) var currentAppName: String = "—"

    private let store = ActivityStore.shared
    private let settings = AppSettings.shared

    private var appSwitchObserver: AppSwitchObserver!
    private var idleMonitor: IdleMonitor!
    private var browserTracker: BrowserTracker!
    private var windowTitleTracker: WindowTitleTracker!
    private var activityScoreTracker: ActivityScoreTracker!
    private var screenshotManager: ScreenshotManager!

    /// Row id of whatever app_intervals row is currently open. Shared with the
    /// activity-score and screenshot trackers so their rows can reference it.
    private(set) var currentIntervalId: Int64?

    private var isManuallyPaused = false

    private init() {
        appSwitchObserver = AppSwitchObserver { [weak self] app in
            self?.handleAppActivated(app)
        }
        idleMonitor = IdleMonitor(thresholdProvider: { [weak self] in
            self?.settings.idleThresholdSeconds ?? 180
        }, onIdleChanged: { [weak self] isIdle in
            self?.handleIdleChanged(isIdle)
        }, supplementaryIdleSecondsProvider: { [weak self] in
            self?.activityScoreTracker.secondsSinceLastEvent()
        })
        browserTracker = BrowserTracker { [weak self] title, url, domain in
            self?.store.updateOpenInterval(windowTitle: title, url: url, domain: domain)
        }
        windowTitleTracker = WindowTitleTracker { [weak self] title in
            self?.store.updateOpenInterval(windowTitle: title)
        }
        activityScoreTracker = ActivityScoreTracker { [weak self] minute, count, score in
            self?.store.recordActivityScore(minuteTimestamp: minute, eventCount: count, score: score, appIntervalId: self?.currentIntervalId)
            self?.screenshotManager.noteLatestScore(score)
        }
        screenshotManager = ScreenshotManager(intervalIdProvider: { [weak self] in self?.currentIntervalId })
    }

    func start() {
        // Seed with whatever app is frontmost right now.
        if let app = NSWorkspace.shared.frontmostApplication {
            handleAppActivated(app)
        }
        appSwitchObserver.start()
        idleMonitor.start()
        activityScoreTracker.start()
        applyScreenshotSetting()
    }

    func applyScreenshotSetting() {
        if settings.screenshotsEnabled {
            screenshotManager.start(intervalMinutes: settings.screenshotIntervalMinutes)
        } else {
            screenshotManager.stop()
        }
    }

    // MARK: - Menu bar controls

    func togglePause() {
        isManuallyPaused.toggle()
        if isManuallyPaused {
            status = .paused
            browserTracker.stop()
            windowTitleTracker.stop()
        } else {
            status = .tracking
            if let app = NSWorkspace.shared.frontmostApplication {
                handleAppActivated(app)
            }
        }
    }

    // MARK: - Internal state transitions

    private func handleAppActivated(_ app: NSRunningApplication) {
        guard !isManuallyPaused else { return }
        guard status != .idle else { return } // resumed by handleIdleChanged instead

        let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        currentAppName = name
        browserTracker.stop()
        windowTitleTracker.stop()

        if settings.isExcluded(appName: name) {
            store.closeCurrentInterval()
            currentIntervalId = nil
            return
        }

        currentIntervalId = store.startInterval(appName: name, windowTitle: nil, url: nil, domain: nil, isIdle: false)

        if BrowserTracker.isSupportedBrowser(bundleIdentifier: app.bundleIdentifier) {
            browserTracker.start(bundleIdentifier: app.bundleIdentifier!)
        } else {
            windowTitleTracker.start(pid: app.processIdentifier)
        }
    }

    private func handleIdleChanged(_ isIdle: Bool) {
        guard !isManuallyPaused else { return }
        if isIdle {
            status = .idle
            browserTracker.stop()
            windowTitleTracker.stop()
            currentIntervalId = store.startInterval(appName: "Idle", windowTitle: nil, url: nil, domain: nil, isIdle: true)
        } else {
            status = .tracking
            if let app = NSWorkspace.shared.frontmostApplication {
                handleAppActivated(app)
            }
        }
    }

    func shutdown() {
        store.closeCurrentInterval()
    }
}
