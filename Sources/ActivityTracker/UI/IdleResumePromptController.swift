import AppKit
import SwiftUI

/// A small floating, non-activating panel shown when you return from an idle
/// stretch longer than the configured threshold, asking whether that time should
/// count as tracked work or stay logged as idle. Deliberately not a system
/// notification (`UNUserNotificationCenter`) — that needs its own permission grant
/// and an actionable-notification delegate, which is a lot of moving parts for a
/// two-button prompt. A plain floating panel needs no extra permission, appears
/// instantly, and auto-dismisses (defaulting to "stay idle", i.e. no data change)
/// if ignored, so it can never block tracking or pile up waiting for a response.
final class IdleResumePromptController {
    static let shared = IdleResumePromptController()

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    private let autoDismissSeconds: TimeInterval = 20

    private init() {}

    func show(idleDuration: TimeInterval, previousAppName: String, onKeepAsWork: @escaping () -> Void) {
        dismiss()

        let view = IdleResumePromptView(
            idleDuration: idleDuration,
            previousAppName: previousAppName,
            onKeep: { [weak self] in
                onKeepAsWork()
                self?.dismiss()
            },
            onDiscard: { [weak self] in
                self?.dismiss()
            }
        )

        let size = NSSize(width: 300, height: 118)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)

        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: screenFrame.maxX - size.width - 16, y: screenFrame.maxY - size.height - 16)
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
        self.panel = panel

        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissSeconds, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.close()
        panel = nil
    }
}

private struct IdleResumePromptView: View {
    let idleDuration: TimeInterval
    let previousAppName: String
    let onKeep: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Welcome back")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text("You were idle for \(formatDuration(idleDuration)). Count it as \(previousAppName), or leave it as idle?")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Keep as \(previousAppName)", action: onKeep)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Discard", action: onDiscard)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial)
    }
}
