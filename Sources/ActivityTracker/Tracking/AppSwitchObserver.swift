import AppKit

/// Wraps NSWorkspace's app-activation notification. Every app switch calls back once,
/// with whatever app just became frontmost.
final class AppSwitchObserver {
    private let onActivate: (NSRunningApplication) -> Void
    private var observer: NSObjectProtocol?

    init(onActivate: @escaping (NSRunningApplication) -> Void) {
        self.onActivate = onActivate
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.onActivate(app)
        }
        Log.info("AppSwitchObserver started")
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    deinit { stop() }
}
