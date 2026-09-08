import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no main window. LSUIElement in Info.plist
        // already suppresses the Dock icon; this is a defensive belt-and-suspenders.
        NSApp.setActivationPolicy(.accessory)

        // Proactively trigger the system's Accessibility consent dialog (rather than
        // silently no-op'ing until the user finds the app in Settings themselves).
        WindowTitleTracker.requestAccessibilityPermissionIfNeeded()

        menuBarController.setup()
        TrackingCoordinator.shared.start()

        Log.info("ActivityTracker launched. Data directory: \(DatabaseManager.appSupportDirectory.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        TrackingCoordinator.shared.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
