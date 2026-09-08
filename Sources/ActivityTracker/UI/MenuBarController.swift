import AppKit
import SwiftUI
import Combine

/// Owns the NSStatusItem, its dropdown menu, and the (lazily created) Dashboard /
/// Settings windows. This is the only AppKit chrome the app has — everything else
/// is SwiftUI hosted inside plain NSWindows.
final class MenuBarController: NSObject, NSMenuDelegate {
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
        }
    }

    private func refreshSummary() {
        let seconds = ActivityStore.shared.appTimeSummary(on: Date()).reduce(0) { $0 + $1.totalSeconds }
        summaryItem.title = "Today: \(formatDuration(seconds)) tracked"
    }

    /// A colored dot + "AT" label. Deliberately NOT a template NSImage: a custom
    /// composited icon risks rendering invisibly against the menu bar in one of the
    /// two appearance modes without a way to visually verify it here, whereas a
    /// colored attributed title always renders in its true color regardless of menu
    /// bar tint, and the text color still adapts to light/dark via `.labelColor`.
    private func updateIcon(for status: TrackingStatus) {
        let color: NSColor
        switch status {
        case .tracking: color = .systemGreen
        case .idle: color = .systemYellow
        case .paused: color = .systemRed
        }
        guard let button = statusItem.button else { return }

        let attributed = NSMutableAttributedString(
            string: "● ",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13, weight: .bold)]
        )
        attributed.append(NSAttributedString(
            string: "AT",
            attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        ))
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
