import Foundation
import AppKit
import ApplicationServices

/// Polls the focused window's title for the frontmost app via the Accessibility API.
/// Generic — works for any app that exposes a standard AXWindow/AXTitle (Wispr Flow,
/// Notes, Terminal, etc.), not just a hardcoded list.
final class WindowTitleTracker {
    private let onTitle: (String) -> Void
    private var timer: DispatchSourceTimer?
    private var pid: pid_t?
    private var hasLoggedPermissionDenial = false

    private let pollInterval: TimeInterval = 7.0

    init(onTitle: @escaping (String) -> Void) {
        self.onTitle = onTitle
    }

    /// Actively prompts for Accessibility access (once) via the system dialog, which
    /// also auto-adds this app to System Settings > Privacy & Security > Accessibility
    /// so the user only has to flip a switch — no manually browsing the filesystem to
    /// "+ Add" the app, which is easy to fumble for an app buried in a project folder.
    /// `AXIsProcessTrusted()` alone (used elsewhere for the passive gate) never shows
    /// this dialog on its own.
    static func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start(pid: pid_t) {
        stop()
        self.pid = pid

        guard AXIsProcessTrusted() else {
            if !hasLoggedPermissionDenial {
                Log.error("Accessibility permission not granted — skipping window-title tracking. Grant it in System Settings > Privacy & Security > Accessibility.")
                hasLoggedPermissionDenial = true
            }
            return
        }

        poll()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        pid = nil
    }

    private func poll() {
        guard let pid else { return }
        guard let title = Self.focusedWindowTitle(forPid: pid) else { return }
        onTitle(title)
    }

    private static func focusedWindowTitle(forPid pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard focusedResult == .success, let windowElement = focusedWindow else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success, let title = titleValue as? String, !title.isEmpty else { return nil }
        return title
    }

    deinit { stop() }
}
