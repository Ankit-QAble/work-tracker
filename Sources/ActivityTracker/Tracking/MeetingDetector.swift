import Foundation
import AppKit
import ApplicationServices

/// Detects an in-progress meeting in a supported app (currently Microsoft Teams),
/// independent of whether that app is frontmost — so a Teams call keeps accruing
/// its own time even while you're actively working in a different app (e.g. Chrome
/// on a second monitor). Logs to `meeting_sessions`, a separate table from
/// `app_intervals` specifically because it's allowed to overlap.
///
/// Heuristic (best-effort — there's no public "am I in a call" API for a
/// third-party local tool to query):
///
/// Derived from watching real Teams windows across three states: not in a meeting,
/// a scheduled channel meeting, and an ad-hoc 1:1 call started from a chat. Window
/// *title* wording varies a lot between those ("Meeting in <channel>" vs. just the
/// other person's name, with no "meeting" wording at all) — but structurally, in
/// every meeting state Teams opens a *second* window distinct from the normal
/// single "Chat | ..." browsing window. So: 2+ windows, at least one NOT titled
/// like a "Chat | ..." browsing view, is treated as "in a meeting".
///
/// Known false-positive risk: popping a chat out into its own separate window
/// (a real Teams feature) without being in a call would also produce 2+ windows
/// and could be mistaken for a meeting. Flagged here for future refinement rather
/// than silently accepted — if this turns out to misfire in practice, the fix is
/// to also require a positive signal (e.g. a window title containing "Meeting",
/// which was present in both meeting states we captured, just not guaranteed for
/// every meeting type).
final class MeetingDetector {
    private struct SupportedApp {
        let bundleIDs: [String]
        let displayName: String
    }

    private let supportedApps = [
        SupportedApp(bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"], displayName: "Microsoft Teams")
    ]

    private var timer: DispatchSourceTimer?
    private var inMeeting: Set<String> = [] // display names currently considered "in a meeting"

    private let pollInterval: TimeInterval = 10.0

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 3, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
        Log.info("MeetingDetector started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard AXIsProcessTrusted() else { return } // same permission WindowTitleTracker needs; degrade silently

        for app in supportedApps {
            let running = NSWorkspace.shared.runningApplications.first {
                guard let id = $0.bundleIdentifier else { return false }
                return app.bundleIDs.contains(id)
            }

            guard let running else {
                // App isn't even running — make sure we don't leave a session open.
                if inMeeting.contains(app.displayName) {
                    inMeeting.remove(app.displayName)
                    ActivityStore.shared.endOpenMeetingSession(appName: app.displayName)
                    Log.info("Meeting ended (app quit): \(app.displayName)")
                }
                continue
            }

            let titles = windowTitles(pid: running.processIdentifier)
            let nowInMeeting = Self.looksLikeMeeting(windowTitles: titles)
            let wasInMeeting = inMeeting.contains(app.displayName)

            if nowInMeeting, !wasInMeeting {
                inMeeting.insert(app.displayName)
                ActivityStore.shared.startMeetingSessionIfNeeded(appName: app.displayName)
                Log.info("Meeting detected: \(app.displayName)")
            } else if !nowInMeeting, wasInMeeting {
                inMeeting.remove(app.displayName)
                ActivityStore.shared.endOpenMeetingSession(appName: app.displayName)
                Log.info("Meeting ended: \(app.displayName)")
            }
        }
    }

    static func looksLikeMeeting(windowTitles: [String]) -> Bool {
        guard windowTitles.count >= 2 else { return false }
        return windowTitles.contains { !$0.lowercased().hasPrefix("chat |") }
    }

    private func windowTitles(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            var titleRef: AnyObject?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
            return titleRef as? String
        }
    }

    deinit { stop() }
}
