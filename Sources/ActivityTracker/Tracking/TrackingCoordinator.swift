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
    private var meetingDetector: MeetingDetector!

    /// Row id of whatever app_intervals row is currently open. Shared with the
    /// activity-score and screenshot trackers so their rows can reference it.
    private(set) var currentIntervalId: Int64?

    private var isManuallyPaused = false

    /// State captured at the moment tracking goes idle, so that on resume we can
    /// offer to reattribute the idle stretch back to whatever was active before —
    /// see `handleIdleChanged` and the idle-resume prompt.
    private var idleStartDate: Date?
    private var idleIntervalId: Int64?
    private var appNameBeforeIdle: String?

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
        meetingDetector = MeetingDetector()
    }

    func start() {
        // Seed with whatever app is frontmost right now.
        if let app = NSWorkspace.shared.frontmostApplication {
            handleAppActivated(app)
        }
        meetingDetector.start() // independent of frontmost-app tracking — can run alongside anything
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
            // Close whatever was open and log nothing further — pausing is a
            // deliberate choice, not something to measure, so the paused stretch
            // should be a clean gap in the data, not its own tracked category
            // (unlike idle, which the app detects on its own and does log).
            // Closing here matters regardless: leaving the prior interval open
            // would let it get silently credited with the whole paused duration
            // the moment tracking resumes (starting a new interval closes the
            // old one by stamping it with "now").
            store.closeCurrentInterval()
            currentIntervalId = nil
            // Drop any in-flight idle bookkeeping — if you pause mid-idle, that
            // stretch is now fully covered by the gap above, and letting stale
            // idle-start/interval-id state survive into a later, unrelated
            // idle-resume prompt could misattribute time that already includes
            // the paused stretch.
            idleStartDate = nil
            idleIntervalId = nil
            appNameBeforeIdle = nil
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
            // Only worth remembering if there was a real, trackable app before this —
            // not the "—" placeholder (no app seen yet) or an excluded app.
            appNameBeforeIdle = (currentAppName != "—" && currentIntervalId != nil) ? currentAppName : nil
            idleStartDate = Date()
            currentIntervalId = store.startInterval(appName: "Idle", windowTitle: nil, url: nil, domain: nil, isIdle: true)
            idleIntervalId = currentIntervalId
        } else {
            let idleDuration = idleStartDate.map { Date().timeIntervalSince($0) } ?? 0
            let intervalToReattribute = idleIntervalId
            let previousApp = appNameBeforeIdle
            idleStartDate = nil
            idleIntervalId = nil
            appNameBeforeIdle = nil

            status = .tracking
            if let app = NSWorkspace.shared.frontmostApplication {
                handleAppActivated(app)
            }

            if settings.idlePromptEnabled,
               idleDuration >= settings.idlePromptThresholdSeconds,
               let intervalToReattribute, let previousApp {
                IdleResumePromptController.shared.show(idleDuration: idleDuration, previousAppName: previousApp) { [weak self] in
                    Log.info("Idle stretch (\(Int(idleDuration))s) reattributed to \(previousApp)")
                    self?.store.reattributeAsTracked(intervalId: intervalToReattribute, appName: previousApp)
                }
            }
        }
    }

    func shutdown() {
        store.closeCurrentInterval()
        meetingDetector.stop()
        store.closeAllOpenMeetingSessions()
    }
}
