import Foundation
import AppKit

/// Polls the frontmost browser's active tab URL/title via AppleScript (Apple Events),
/// every 5 seconds, while that browser is frontmost. Structured so Safari/Arc can be
/// added by extending `Browser` and its script text — the polling/permission-handling
/// logic is shared.
final class BrowserTracker {
    private enum Browser {
        case chrome

        var bundleIdentifier: String { "com.google.Chrome" }

        var appleScriptSource: String {
            """
            tell application "Google Chrome"
                if (count of windows) = 0 then return "::NOWINDOW::"
                set theURL to URL of active tab of front window
                set theTitle to title of active tab of front window
                return theURL & "::SEP::" & theTitle
            end tell
            """
        }
    }

    private let onTabInfo: (_ title: String, _ url: String, _ domain: String?) -> Void
    private var timer: DispatchSourceTimer?
    private var currentBrowser: Browser?
    private var hasLoggedPermissionDenial = false

    private let pollInterval: TimeInterval = 5.0

    init(onTabInfo: @escaping (_ title: String, _ url: String, _ domain: String?) -> Void) {
        self.onTabInfo = onTabInfo
    }

    static func isSupportedBrowser(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == Browser.chrome.bundleIdentifier
    }

    func start(bundleIdentifier: String) {
        guard bundleIdentifier == Browser.chrome.bundleIdentifier else { return }
        stop()
        currentBrowser = .chrome
        hasLoggedPermissionDenial = false

        poll() // fire immediately, then on the interval
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        currentBrowser = nil
    }

    private func poll() {
        guard let browser = currentBrowser else { return }
        guard let script = NSAppleScript(source: browser.appleScriptSource) else { return }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // errAEEventNotPermitted = -1743: Automation permission not granted.
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -1743 {
                if !hasLoggedPermissionDenial {
                    Log.error("Chrome automation permission not granted — skipping tab tracking. Grant it in System Settings > Privacy & Security > Automation.")
                    hasLoggedPermissionDenial = true
                }
            } else {
                Log.error("AppleScript error polling Chrome: \(errorInfo)")
            }
            return
        }

        guard let raw = result.stringValue, raw != "::NOWINDOW::" else { return }
        let parts = raw.components(separatedBy: "::SEP::")
        guard parts.count == 2 else { return }
        let urlString = parts[0]
        let title = parts[1]
        let domain = URL(string: urlString)?.host

        onTabInfo(title, urlString, domain)
    }

    deinit { stop() }
}
