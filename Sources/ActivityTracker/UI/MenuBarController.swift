import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    /// Posted when the Dashboard should reload its data — on refocus, and on the
    /// shared periodic timer while the window is visible. DashboardView doesn't
    /// own a timer itself: since its NSWindow is reused (never destroyed) after
    /// first opened, SwiftUI's onAppear/onDisappear won't fire again on
    /// hide/show, so scheduling lives here in MenuBarController instead, which
    /// already knows the window's visibility.
    static let dashboardShouldRefresh = Notification.Name("dashboardShouldRefresh")
}

/// Owns the NSStatusItem, its dropdown menu, and the (lazily created) Dashboard /
/// Settings windows. This is the only AppKit chrome the app has — everything else
/// is SwiftUI hosted inside plain NSWindows.
final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var summaryRefreshTimer: Timer?

    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private let summaryItem = NSMenuItem()
    private let statusLabelItem = NSMenuItem()
    private let pauseResumeItem = NSMenuItem()

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(for: .tracking)

        let menu = NSMenu()
        menu.delegate = self

        summaryItem.isEnabled = false
        menu.addItem(summaryItem)

        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())

        pauseResumeItem.title = "Pause Tracking"
        pauseResumeItem.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
        pauseResumeItem.target = self
        pauseResumeItem.action = #selector(togglePause)
        menu.addItem(pauseResumeItem)

        let dashboardItem = NSMenuItem(title: "Open Dashboard…", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.image = NSImage(systemSymbolName: "chart.bar.doc.horizontal", accessibilityDescription: nil)
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ActivityTracker", action: #selector(quit), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)

        menu.addItem(.separator())
        let creditItem = NSMenuItem(title: "Developed by QAble", action: nil, keyEquivalent: "")
        creditItem.isEnabled = false
        menu.addItem(creditItem)

        statusItem.menu = menu

        TrackingCoordinator.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateIcon(for: status)
                self?.statusLabelItem.title = "● \(status.rawValue)"
                self?.pauseResumeItem.title = status == .paused ? "Resume Tracking" : "Pause Tracking"
                self?.pauseResumeItem.image = NSImage(
                    systemSymbolName: status == .paused ? "play.fill" : "pause.fill",
                    accessibilityDescription: nil
                )
            }
            .store(in: &cancellables)

        refreshSummary()
        summaryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshSummary()
            // Only nudge the Dashboard to reload while it's actually visible —
            // no point re-querying the DB for a window nobody's looking at.
            if self?.dashboardWindow?.isVisible == true {
                NotificationCenter.default.post(name: .dashboardShouldRefresh, object: nil)
            }
        }
    }

    private func refreshSummary() {
        let seconds = ActivityStore.shared.appTimeSummary(on: Date()).reduce(0) { $0 + $1.totalSeconds }
        summaryItem.title = "Today: \(formatDuration(seconds)) tracked"
    }

    /// Refresh immediately on refocus — so reopening the Dashboard (or clicking
    /// back into it) never shows stale data while waiting for the next periodic tick.
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === dashboardWindow else { return }
        NotificationCenter.default.post(name: .dashboardShouldRefresh, object: nil)
    }

    /// A single colored dot. Deliberately NOT a template NSImage: a custom
    /// composited icon risks rendering invisibly against the menu bar in one of the
    /// two appearance modes without a way to visually verify it here, whereas a
    /// colored attributed title always renders in its true color regardless of menu
    /// bar tint.
    private func updateIcon(for status: TrackingStatus) {
        let color: NSColor
        switch status {
        case .tracking: color = .systemGreen
        case .idle: color = .systemYellow
        case .paused: color = .systemRed
        }
        guard let button = statusItem.button else { return }

        let attributed = NSAttributedString(
            string: "●",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 15, weight: .bold)]
        )
        button.image = nil
        button.attributedTitle = attributed
        button.toolTip = "ActivityTracker — \(status.rawValue)"
    }

    @objc private func togglePause() {
        TrackingCoordinator.shared.togglePause()
    }

    @objc private func openDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Activity Dashboard"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: DashboardView())
            window.center()
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        TrackingCoordinator.shared.shutdown()
        NSApp.terminate(nil)
    }
}
